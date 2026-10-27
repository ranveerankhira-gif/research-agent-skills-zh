Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$script:ApiVersion = '2.1.0'
$script:DefaultMaxBytes = 10737418240
$script:MaximumApiResponseBytes = 16777216
$script:MaximumRedirects = 8
$script:DownloadBufferBytes = 1048576

function Test-IsLoopbackHost {
    param([Parameter(Mandatory = $true)][Uri]$Uri)
    $Uri.Host -in @('127.0.0.1', 'localhost', '::1')
}

function Test-IsDryadAssetHost {
    param([Parameter(Mandatory = $true)][string]$HostName)
    $HostName -match '^dryad-assetstore-[a-z0-9-]+\.s3(?:\.[a-z0-9-]+)?\.amazonaws\.com$'
}

function Assert-ApiBaseUri {
    param([Parameter(Mandatory = $true)][Uri]$Uri, [switch]$AllowLoopback)
    if ($AllowLoopback -and (Test-IsLoopbackHost -Uri $Uri) -and $Uri.Scheme -in @('http', 'https')) { return }
    if ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'datadryad.org' -or
        -not $Uri.AbsolutePath.StartsWith('/api/v2/', [StringComparison]::Ordinal)) {
        throw 'ApiBaseUri must be https://datadryad.org/api/v2/. The loopback override is reserved for offline tests.'
    }
}

function Test-IsAllowedApiUri {
    param([Parameter(Mandatory = $true)][Uri]$Uri, [switch]$AllowLoopback)
    if ($AllowLoopback -and (Test-IsLoopbackHost -Uri $Uri) -and $Uri.Scheme -in @('http', 'https')) { return $true }
    $Uri.Scheme -eq 'https' -and $Uri.Host -eq 'datadryad.org' -and
        $Uri.AbsolutePath.StartsWith('/api/v2/', [StringComparison]::Ordinal)
}

function Test-IsAllowedDownloadUri {
    param([Parameter(Mandatory = $true)][Uri]$Uri, [switch]$AllowLoopback)
    if ($AllowLoopback -and (Test-IsLoopbackHost -Uri $Uri) -and $Uri.Scheme -in @('http', 'https')) { return $true }
    if ($Uri.Scheme -ne 'https') { return $false }
    if ($Uri.Host -eq 'datadryad.org' -and
        ($Uri.AbsolutePath.StartsWith('/api/v2/', [StringComparison]::Ordinal) -or
         $Uri.AbsolutePath.StartsWith('/downloads/file_stream/', [StringComparison]::Ordinal))) { return $true }
    Test-IsDryadAssetHost -HostName $Uri.Host
}

function Resolve-LinkedUri {
    param([Parameter(Mandatory = $true)][Uri]$BaseUri, [Parameter(Mandatory = $true)][string]$Href)
    if ([string]::IsNullOrWhiteSpace($Href)) { throw 'Dryad API returned an empty link.' }
    [Uri]::new($BaseUri, $Href)
}

function Resolve-DryadIdentifier {
    param([Parameter(Mandatory = $true)][string]$Value)
    $candidate = $Value.Trim()
    if ($candidate -match '^https?://doi\.org/(10\.[^?#\s]+/[^?#\s]+)') {
        $candidate = [Uri]::UnescapeDataString($Matches[1])
    } elseif ($candidate -match '^https://datadryad\.org/(?:stash/)?dataset/doi(?::|%3A)([^?#]+)') {
        $candidate = [Uri]::UnescapeDataString($Matches[1])
    } elseif ($candidate.StartsWith('doi:', [StringComparison]::OrdinalIgnoreCase)) {
        $candidate = $candidate.Substring(4)
    }
    if ($candidate -notmatch '^10\.\d{4,9}/\S+$' -or $candidate -match '[?#]') {
        throw 'Dataset must be a Dryad DOI or a datadryad.org dataset URL.'
    }
    $encodedIdentifier = [Uri]::EscapeDataString("doi:$candidate")
    [pscustomobject]@{
        doi = $candidate
        encoded_identifier = $encodedIdentifier
        landing_url = "https://datadryad.org/dataset/$encodedIdentifier"
    }
}

function Read-ConfigFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'ConfigPath does not identify a file.' }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ConfigPath must not be a reparse point.' }
    if ($item.Length -gt 65536) { throw 'Config file exceeds 64 KiB.' }
    try { $config = (Get-Content -Raw -LiteralPath $item.FullName -Encoding UTF8 | ConvertFrom-Json) }
    catch { throw 'Config file is not valid UTF-8 JSON.' }
    $allowed = @('opencli', 'maxBytes', 'challengeTimeoutSeconds')
    foreach ($property in $config.PSObject.Properties.Name) {
        if ($property -notin $allowed) { throw "Unsupported config field: $property" }
    }
    $config
}

function Get-OptionalPropertyValue {
    param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    $property.Value
}

function New-DryadHttpClient {
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromMinutes(10)
    $client.DefaultRequestHeaders.Accept.ParseAdd('application/json')
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('codex-skills-zh-dryad-data-fetcher/0.2.0')
    $client.DefaultRequestHeaders.Add('X-API-Version', $script:ApiVersion)
    $client
}

function Read-ResponseBytes {
    param([Parameter(Mandatory = $true)][Net.Http.HttpResponseMessage]$Response,
          [Parameter(Mandatory = $true)][long]$MaximumBytes)
    $declared = $Response.Content.Headers.ContentLength
    if ($null -ne $declared -and $declared -gt $MaximumBytes) {
        throw "Response declares $declared bytes, above the maximum of $MaximumBytes bytes."
    }
    $bytes = $Response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    if ($bytes.LongLength -gt $MaximumBytes) {
        throw "Response contains $($bytes.LongLength) bytes, above the maximum of $MaximumBytes bytes."
    }
    $bytes
}

function Invoke-ApiJson {
    param([Parameter(Mandatory = $true)][Net.Http.HttpClient]$Client,
          [Parameter(Mandatory = $true)][Uri]$Uri, [switch]$AllowLoopback)
    $current = $Uri
    for ($hop = 0; $hop -le $script:MaximumRedirects; $hop++) {
        if (-not (Test-IsAllowedApiUri -Uri $current -AllowLoopback:$AllowLoopback)) {
            throw "Refusing API request to a non-Dryad host: $($current.Host)"
        }
        $response = $Client.GetAsync($current, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $status = [int]$response.StatusCode
            if ($status -ge 300 -and $status -lt 400) {
                if ($null -eq $response.Headers.Location) { throw "Dryad API redirect omitted Location (HTTP $status)." }
                if ($hop -eq $script:MaximumRedirects) { throw "Dryad API exceeded $($script:MaximumRedirects) redirects." }
                $current = [Uri]::new($current, $response.Headers.Location)
                continue
            }
            if (-not $response.IsSuccessStatusCode) { throw "Dryad API request failed with HTTP $status." }
            $contentType = if ($response.Content.Headers.ContentType) { $response.Content.Headers.ContentType.MediaType } else { '' }
            if ($contentType -and $contentType -notmatch '(?i)(?:application/(?:hal\+)?json|text/json)') {
                throw "Dryad API returned unexpected Content-Type: $contentType"
            }
            $jsonText = [Text.Encoding]::UTF8.GetString((Read-ResponseBytes -Response $response -MaximumBytes $script:MaximumApiResponseBytes))
            try { return ($jsonText | ConvertFrom-Json) }
            catch { throw 'Dryad API returned malformed JSON.' }
        } finally { $response.Dispose() }
    }
    throw 'Dryad API redirect handling ended unexpectedly.'
}

function Get-DryadFilesFromApi {
    param([Parameter(Mandatory = $true)][Net.Http.HttpClient]$Client,
          [Parameter(Mandatory = $true)][Uri]$BaseUri,
          [Parameter(Mandatory = $true)][string]$EncodedIdentifier, [switch]$AllowLoopback)
    $dataset = Invoke-ApiJson -Client $Client -Uri ([Uri]::new($BaseUri, "datasets/$EncodedIdentifier")) -AllowLoopback:$AllowLoopback
    $versionHref = [string]$dataset._links.'stash:version'.href
    if ([string]::IsNullOrWhiteSpace($versionHref)) { throw 'Dryad API did not identify the latest public dataset version.' }
    $version = Invoke-ApiJson -Client $Client -Uri (Resolve-LinkedUri -BaseUri $BaseUri -Href $versionHref) -AllowLoopback:$AllowLoopback
    $filesHref = [string]$version._links.'stash:files'.href
    if ([string]::IsNullOrWhiteSpace($filesHref)) { throw 'Dryad API did not provide a file-list link for the latest version.' }

    $files = [Collections.Generic.List[object]]::new()
    $pageUri = Resolve-LinkedUri -BaseUri $BaseUri -Href $filesHref
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($null -ne $pageUri) {
        if (-not $seen.Add($pageUri.AbsoluteUri)) { throw 'Dryad API file pagination contains a loop.' }
        $page = Invoke-ApiJson -Client $Client -Uri $pageUri -AllowLoopback:$AllowLoopback
        foreach ($entry in @($page._embedded.'stash:files')) {
            $path = [string]$entry.path
            $downloadHref = [string]$entry._links.'stash:download'.href
            if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($downloadHref)) {
                throw 'Dryad API returned an incomplete file record.'
            }
            $selfHref = [string]$entry._links.self.href
            $fileId = if ($selfHref -match '/files/(\d+)$') { $Matches[1] } else { $null }
            if ([string]::IsNullOrWhiteSpace($fileId)) {
                throw 'Dryad API returned a file record without a numeric public file ID.'
            }
            $files.Add([pscustomobject]@{
                id = $fileId
                name = $path
                size = if ($null -eq $entry.size) { $null } else { [long]$entry.size }
                mime_type = [string]$entry.mimeType
                digest = ([string]$entry.digest).ToLowerInvariant()
                digest_type = ([string]$entry.digestType).ToLowerInvariant()
                api_download_url = Resolve-LinkedUri -BaseUri $BaseUri -Href $downloadHref
                download_url = Resolve-LinkedUri -BaseUri $BaseUri -Href "/downloads/file_stream/$fileId"
            })
        }
        $nextProperty = $page._links.PSObject.Properties['next']
        $nextHref = if ($null -eq $nextProperty -or $null -eq $nextProperty.Value) { '' } else { [string]$nextProperty.Value.href }
        $pageUri = if ([string]::IsNullOrWhiteSpace($nextHref)) { $null } else { Resolve-LinkedUri -BaseUri $BaseUri -Href $nextHref }
    }
    @($files)
}

function Get-SafeFileName {
    param([Parameter(Mandatory = $true)][string]$Name)
    $normalized = $Name.Replace('\', '/')
    $segments = @($normalized -split '/')
    if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:' -or
        @($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -in @('.', '..') }).Count -gt 0) {
        throw "Dryad returned a path-traversal-style file name: $Name"
    }
    $leaf = $segments[-1]
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf -in @('.', '..')) { throw "Dryad returned an unsafe file name: $Name" }
    if ($leaf.Length -gt 180) { throw "Dryad file name exceeds the 180-character safety limit: $Name" }
    if ($leaf.EndsWith(' ') -or $leaf.EndsWith('.')) { throw "Dryad returned a Windows-unsafe file name: $Name" }
    if ($leaf -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw "Dryad returned a reserved Windows device name: $Name" }
    foreach ($character in [IO.Path]::GetInvalidFileNameChars()) {
        if ($leaf.Contains([string]$character)) { throw "Dryad returned a file name containing an invalid character: $Name" }
    }
    $leaf
}

function Assert-NoReparsePointInExistingPath {
    param([Parameter(Mandatory = $true)][string]$FullPath)
    $current = $FullPath
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Output path traverses a reparse point: $($item.FullName)"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Resolve-SafeOutputDirectory {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'Downloading requires an explicit -OutputDirectory.' }
    $fullPath = [IO.Path]::GetFullPath($Value)
    $skillRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    $skillPrefix = $skillRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($fullPath.Equals($skillRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($skillPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputDirectory must not be the Skill directory or a directory inside it.'
    }
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) { throw 'OutputDirectory points to a file.' }
    Assert-NoReparsePointInExistingPath -FullPath $fullPath
    [IO.Directory]::CreateDirectory($fullPath) | Out-Null
    Assert-NoReparsePointInExistingPath -FullPath $fullPath
    (Get-Item -LiteralPath $fullPath -Force).FullName
}

function Resolve-ConfiguredCommand {
    param([string]$Configured, [string]$Name)
    $candidate = if ([string]::IsNullOrWhiteSpace($Configured)) { $Name } else { $Configured }
    $looksLikePath = [IO.Path]::IsPathRooted($candidate) -or $candidate.Contains([IO.Path]::DirectorySeparatorChar) -or $candidate.Contains([IO.Path]::AltDirectorySeparatorChar)
    if ($looksLikePath) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "Configured $Name command not found." }
        $resolvedPath = (Resolve-Path -LiteralPath $candidate).Path
        if ([IO.Path]::GetExtension($resolvedPath) -in @('.cmd', '.bat')) {
            $pathCommand = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $pathCommand -and $pathCommand.Source -eq $resolvedPath) {
                return $Name
            }
            throw "A full Windows .$([IO.Path]::GetExtension($resolvedPath).TrimStart('.')) shim path can corrupt JavaScript arguments. Add its directory to PATH and configure the command name '$Name' instead."
        }
        return $resolvedPath
    }
    $command = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) { throw "$Name is not installed or configured. Set OPENCLI_BIN, use config, or pass -OpenCli." }
    $candidate
}

function Invoke-CapturedCommand {
    param([Parameter(Mandatory = $true)][string]$Command,
          [Parameter(Mandatory = $true)][string[]]$Arguments, [switch]$AllowFailure)
    Write-Verbose "OpenCLI invocation mode=$([IO.Path]::GetExtension($Command)), argument_count=$($Arguments.Count), trailing_command=$(if($Arguments.Count -ge 2){$Arguments[-2]}else{'none'})"
    # PowerShell 7 can corrupt a complex JavaScript argument when the whole
    # argument vector is splatted into an npm .cmd shim. Pass the eval payload
    # separately through the standard OpenCLI command literal.
    $lines = if ($Command -eq 'opencli') {
        if ($Arguments.Count -eq 6 -and $Arguments[0] -eq '--profile' -and
            $Arguments[2] -eq 'browser' -and $Arguments[4] -eq 'eval') {
            $profileName = $Arguments[1]
            $sessionName = $Arguments[3]
            $javascript = $Arguments[5]
            & opencli --profile $profileName browser $sessionName eval $javascript 2>&1
        } else {
            & opencli @Arguments 2>&1
        }
    } else {
        & $Command @Arguments 2>&1
    }
    $exitCode = $LASTEXITCODE
    $captured = ($lines | ForEach-Object { $_.ToString() }) -join "`n"
    if (-not $AllowFailure -and $exitCode -ne 0) { throw "External command failed with exit code $exitCode.`n$captured" }
    [pscustomobject]@{ ExitCode = $exitCode; Text = $captured }
}

function ConvertFrom-FirstJsonObject {
    param([Parameter(Mandatory = $true)][string]$Text)
    $start = $Text.IndexOf('{'); $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { throw 'No JSON object found in external command output.' }
    $Text.Substring($start, $end - $start + 1) | ConvertFrom-Json
}

function ConvertFrom-BrowserPayload {
    param([Parameter(Mandatory = $true)][string]$Text)
    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -gt 16384) { continue }
        if ($trimmed.StartsWith('DRYAD|')) {
            $legacy = $trimmed -split '\|', 5
            if ($legacy.Count -eq 5) {
                return [pscustomobject]@{ marker = $legacy[0]; status = $legacy[1]; content_type = $legacy[2]; content_length = $legacy[3]; url_base64 = $legacy[4] }
            }
        }
        $candidate = $trimmed
        if ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
            try {
                $candidate = [string]($trimmed | ConvertFrom-Json)
            } catch { }
        }
        if ($candidate.StartsWith('{') -and $candidate.EndsWith('}')) {
            try {
                $object = $candidate | ConvertFrom-Json
                if ([string]$object.marker -eq 'DRYAD') {
                    return [pscustomobject]@{
                        marker = [string]$object.marker
                        status = [string]$object.status
                        content_type = [string]$object.contentType
                        content_length = [string]$object.contentLength
                        url_base64 = [string]$object.urlBase64
                    }
                }
            } catch { }
        }
    }
    throw 'No valid Dryad payload found in browser evaluation output.'
}

function Resolve-OpenCliProfile {
    param([Parameter(Mandatory = $true)][string]$OpenCliCommand, [string]$RequestedProfile)
    $profiles = Invoke-CapturedCommand -Command $OpenCliCommand -Arguments @('profile', 'list')
    if ($RequestedProfile) {
        if ($profiles.Text -notmatch "(?m)^\s*$([regex]::Escape($RequestedProfile))\b.*connected") {
            throw "Requested OpenCLI profile is not connected: $RequestedProfile"
        }
        return $RequestedProfile
    }
    $defaultMatch = [regex]::Match($profiles.Text, '(?m)^\s*(\S+)\s+default\s+.*connected')
    if ($defaultMatch.Success) { return $defaultMatch.Groups[1].Value }
    $connected = @([regex]::Matches($profiles.Text, '(?m)^\s*(\S+).*connected') | ForEach-Object { $_.Groups[1].Value })
    if ($connected.Count -eq 1) { return $connected[0] }
    throw 'Multiple OpenCLI profiles are connected and no default profile could be determined. Pass -Profile explicitly.'
}

function Resolve-DownloadUriWithBrowser {
    param([Parameter(Mandatory = $true)][Uri]$DownloadUri,
          [Parameter(Mandatory = $true)][string]$LandingUrl,
          [string]$ConfiguredOpenCli, [string]$RequestedProfile,
          [Parameter(Mandatory = $true)][int]$TimeoutSeconds, [switch]$AllowLoopback)
    $openCliCommand = Resolve-ConfiguredCommand -Configured $ConfiguredOpenCli -Name 'opencli'
    $selectedProfile = Resolve-OpenCliProfile -OpenCliCommand $openCliCommand -RequestedProfile $RequestedProfile
    $session = "dryad-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 12))"
    $prefix = @('--profile', $selectedProfile, 'browser', $session)
    $createdPages = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        $opened = ConvertFrom-FirstJsonObject -Text (Invoke-CapturedCommand -Command $openCliCommand -Arguments ($prefix + @('open', $LandingUrl, '--window', 'background'))).Text
        if (-not $opened.page) { throw 'OpenCLI did not return the created Dryad page ID.' }
        [void]$createdPages.Add([string]$opened.page)
        Start-Sleep -Seconds 3
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $attempts = 0
        do {
            $fetchTarget = if ($DownloadUri.Host -eq 'datadryad.org') { $DownloadUri.PathAndQuery } else { $DownloadUri.AbsoluteUri }
            $escapedTarget = $fetchTarget.Replace('\', '\\').Replace("'", "\'").Replace("`r", '\r').Replace("`n", '\n')
            $literal = "'$escapedTarget'"
            $browserScript = "fetch($literal, { cache: 'no-store' }).then(function (r) { return JSON.stringify({ marker: 'DRYAD', status: r.status, contentType: r.headers.get('content-type'), contentLength: r.headers.get('content-length'), urlBase64: btoa(r.url) }) })"
            $evaluation = Invoke-CapturedCommand -Command $openCliCommand -Arguments ($prefix + @('eval', $browserScript)) -AllowFailure
            Write-Verbose "Dryad browser eval exit code: $($evaluation.ExitCode)"
            $challenge = $false
            if ($evaluation.ExitCode -eq 0) {
                try {
                    $payload = ConvertFrom-BrowserPayload -Text $evaluation.Text
                    if ($payload.marker -eq 'DRYAD' -and $payload.url_base64.Length -le 12288) {
                        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload.url_base64))
                        if ($decoded.Length -gt 8192) { throw 'Browser returned an overlong asset URL.' }
                        $finalUri = [Uri]$decoded
                        $allowedFinalUri = Test-IsAllowedDownloadUri -Uri $finalUri -AllowLoopback:$AllowLoopback
                        Write-Verbose "Dryad browser eval status=$($payload.status), content_type=$($payload.content_type), allowed_host=$allowedFinalUri"
                        if ($payload.status -eq '200' -and $payload.content_type -notmatch '^text/html' -and $allowedFinalUri) { return $finalUri }
                        if (($finalUri.Host -eq 'datadryad.org' -or ($AllowLoopback -and (Test-IsLoopbackHost -Uri $finalUri))) -and
                            $payload.content_type -match '^text/html') { $challenge = $true }
                    }
                } catch [FormatException] {
                    throw 'Browser returned malformed Base64 for the asset URL.'
                } catch {
                    Write-Verbose "Dryad browser payload was not ready: $($_.Exception.Message)"
                }
            }
            if ($challenge -and $attempts -lt 2) {
                $attempts++
                $challengeOpen = Invoke-CapturedCommand -Command $openCliCommand -Arguments ($prefix + @('open', $DownloadUri.AbsoluteUri, '--window', 'background')) -AllowFailure
                if ($challengeOpen.ExitCode -eq 0) {
                    try {
                        $challengeObject = ConvertFrom-FirstJsonObject -Text $challengeOpen.Text
                        if ($challengeObject.page) { [void]$createdPages.Add([string]$challengeObject.page) }
                    } catch { }
                }
                Start-Sleep -Seconds 15
                $returned = ConvertFrom-FirstJsonObject -Text (Invoke-CapturedCommand -Command $openCliCommand -Arguments ($prefix + @('open', $LandingUrl, '--window', 'background'))).Text
                if (-not $returned.page) { throw 'OpenCLI did not return a page ID after Dryad browser verification.' }
                [void]$createdPages.Add([string]$returned.page)
                Start-Sleep -Seconds 3
                continue
            }
            Start-Sleep -Seconds 3
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "Dryad browser verification did not yield an allowed asset URL within $TimeoutSeconds seconds."
    } finally {
        foreach ($pageId in $createdPages) {
            [void](Invoke-CapturedCommand -Command $openCliCommand -Arguments ($prefix + @('tab', 'close', $pageId)) -AllowFailure)
        }
        [void](Invoke-CapturedCommand -Command $openCliCommand -Arguments ($prefix + @('close')) -AllowFailure)
    }
}

function Receive-DownloadToTemporaryFile {
    param([Parameter(Mandatory = $true)][Net.Http.HttpClient]$Client,
          [Parameter(Mandatory = $true)][Uri]$InitialUri,
          [Parameter(Mandatory = $true)][string]$TemporaryPath,
          [Parameter(Mandatory = $true)][long]$MaximumBytes, [switch]$AllowLoopback)
    $current = $InitialUri
    for ($hop = 0; $hop -le $script:MaximumRedirects; $hop++) {
        if (-not (Test-IsAllowedDownloadUri -Uri $current -AllowLoopback:$AllowLoopback)) {
            throw "Refusing download from unexpected host: $($current.Host)"
        }
        $response = $Client.GetAsync($current, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $status = [int]$response.StatusCode
            if ($status -ge 300 -and $status -lt 400) {
                if ($null -eq $response.Headers.Location) { throw "Download redirect omitted Location (HTTP $status)." }
                if ($hop -eq $script:MaximumRedirects) { throw "Download exceeded $($script:MaximumRedirects) redirects." }
                $current = [Uri]::new($current, $response.Headers.Location)
                continue
            }
            $contentType = if ($response.Content.Headers.ContentType) { $response.Content.Headers.ContentType.MediaType } else { '' }
            $dryadOrTest = $current.Host -eq 'datadryad.org' -or ($AllowLoopback -and (Test-IsLoopbackHost -Uri $current))
            $challengeStatus = $status -in @(200, 401, 403, 429, 503)
            if ($dryadOrTest -and $challengeStatus -and $contentType -match '^text/html') {
                return [pscustomobject]@{ ChallengeRequired = $true; FinalUri = $current; ContentType = $contentType }
            }
            if (-not $response.IsSuccessStatusCode) { throw "Download failed with HTTP $status." }
            if ($contentType -match '^text/html') { throw 'Downloaded response is HTML rather than a data file.' }
            $declared = $response.Content.Headers.ContentLength
            if ($null -ne $declared -and $declared -gt $MaximumBytes) {
                throw "Download declares $declared bytes, above -MaxBytes $MaximumBytes."
            }
            $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            try {
                $outputStream = [IO.File]::Open($TemporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $buffer = New-Object byte[] $script:DownloadBufferBytes
                    [long]$written = 0
                    while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $written += $read
                        if ($written -gt $MaximumBytes) { throw "Download exceeded -MaxBytes $MaximumBytes while streaming." }
                        $outputStream.Write($buffer, 0, $read)
                    }
                } finally { $outputStream.Dispose() }
            } finally { $inputStream.Dispose() }
            return [pscustomobject]@{ ChallengeRequired = $false; FinalUri = $current; ContentType = $contentType }
        } finally { $response.Dispose() }
    }
    throw 'Download redirect handling ended unexpectedly.'
}

function Get-HashForDigestType {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$DigestType)
    switch -Regex ($DigestType) {
        '^(sha-?256)$' { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant(); break }
        '^md5$' { (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToLowerInvariant(); break }
        '^$' { $null; break }
        default { throw "Dryad supplied an unsupported digest type: $DigestType" }
    }
}

function Assert-RegularDestinationFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return }
        throw "Destination exists but is not a regular file: $Path"
    }
}

function Move-TemporaryFileAtomically {
    param([Parameter(Mandatory = $true)][string]$TemporaryPath,
          [Parameter(Mandatory = $true)][string]$Destination)
    try { [IO.File]::Move($TemporaryPath, $Destination); $true }
    catch [IO.IOException] {
        if (Test-Path -LiteralPath $Destination -PathType Leaf) { $false } else { throw }
    }
}

function Place-DownloadedFile {
    param([Parameter(Mandatory = $true)][string]$TemporaryPath,
          [Parameter(Mandatory = $true)][string]$Directory,
          [Parameter(Mandatory = $true)][string]$Name,
          [Parameter(Mandatory = $true)][string]$Sha256)
    $destination = Join-Path $Directory $Name
    Assert-RegularDestinationFile -Path $destination
    if (-not (Test-Path -LiteralPath $destination) -and
        (Move-TemporaryFileAtomically -TemporaryPath $TemporaryPath -Destination $destination)) {
        return [pscustomobject]@{ Path = $destination; Reused = $false }
    }
    Assert-RegularDestinationFile -Path $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Sha256) {
        Remove-Item -LiteralPath $TemporaryPath -Force
        return [pscustomobject]@{ Path = $destination; Reused = $true }
    }

    $extension = [IO.Path]::GetExtension($Name)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($Name)
    $maximumBaseLength = [Math]::Max(1, 240 - $extension.Length - 66)
    if ($baseName.Length -gt $maximumBaseLength) { $baseName = $baseName.Substring(0, $maximumBaseLength) }
    $candidate = Join-Path $Directory "$baseName--$Sha256$extension"
    Assert-RegularDestinationFile -Path $candidate
    if (-not (Test-Path -LiteralPath $candidate) -and
        (Move-TemporaryFileAtomically -TemporaryPath $TemporaryPath -Destination $candidate)) {
        return [pscustomobject]@{ Path = $candidate; Reused = $false }
    }
    Assert-RegularDestinationFile -Path $candidate
    if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256) {
        throw "Hash-named collision destination contains different bytes: $candidate"
    }
    Remove-Item -LiteralPath $TemporaryPath -Force
    [pscustomobject]@{ Path = $candidate; Reused = $true }
}

function Save-DryadFile {
    param([Parameter(Mandatory = $true)][Net.Http.HttpClient]$Client,
          [Parameter(Mandatory = $true)]$File,
          [Parameter(Mandatory = $true)][string]$Directory,
          [Parameter(Mandatory = $true)][string]$LandingUrl,
          [Parameter(Mandatory = $true)][long]$MaximumBytes,
          [string]$ConfiguredOpenCli, [string]$RequestedProfile,
          [Parameter(Mandatory = $true)][int]$TimeoutSeconds, [switch]$AllowLoopback)
    if ($null -ne $File.size -and [long]$File.size -gt $MaximumBytes) {
        throw "Dryad reports $($File.size) bytes for '$($File.name)', above -MaxBytes $MaximumBytes."
    }
    $safeName = Get-SafeFileName -Name $File.name
    $temporaryPath = Join-Path $Directory ".$safeName.$([Guid]::NewGuid().ToString('N')).partial"
    $browserFallback = $false
    try {
        $received = Receive-DownloadToTemporaryFile -Client $Client -InitialUri $File.download_url -TemporaryPath $temporaryPath -MaximumBytes $MaximumBytes -AllowLoopback:$AllowLoopback
        if ($received.ChallengeRequired) {
            $resolved = Resolve-DownloadUriWithBrowser -DownloadUri $File.download_url -LandingUrl $LandingUrl -ConfiguredOpenCli $ConfiguredOpenCli -RequestedProfile $RequestedProfile -TimeoutSeconds $TimeoutSeconds -AllowLoopback:$AllowLoopback
            $browserFallback = $true
            $received = Receive-DownloadToTemporaryFile -Client $Client -InitialUri $resolved -TemporaryPath $temporaryPath -MaximumBytes $MaximumBytes -AllowLoopback:$AllowLoopback
            if ($received.ChallengeRequired) { throw 'Dryad still returned an HTML challenge after browser verification.' }
        }
        $item = Get-Item -LiteralPath $temporaryPath
        if ($item.Length -le 0) { throw 'Downloaded file is empty.' }
        if ($null -ne $File.size -and [long]$File.size -ne $item.Length) {
            throw "Downloaded byte count $($item.Length) does not match Dryad metadata size $($File.size)."
        }
        $sampleLength = [Math]::Min(1024, [int]$item.Length)
        $sampleBytes = New-Object byte[] $sampleLength
        $sampleStream = [IO.File]::OpenRead($temporaryPath)
        try { [void]$sampleStream.Read($sampleBytes, 0, $sampleLength) } finally { $sampleStream.Dispose() }
        if ([Text.Encoding]::UTF8.GetString($sampleBytes) -match '(?is)<\s*(?:!doctype\s+html|html|head|body)\b') {
            throw 'Downloaded bytes are HTML rather than the requested data file.'
        }
        $sha256 = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($File.digest)) {
            if ((Get-HashForDigestType -Path $temporaryPath -DigestType $File.digest_type) -ne $File.digest) {
                throw "Downloaded digest does not match Dryad metadata for '$($File.name)'."
            }
        }
        $placed = Place-DownloadedFile -TemporaryPath $temporaryPath -Directory $Directory -Name $safeName -Sha256 $sha256
        $finalItem = Get-Item -LiteralPath $placed.Path
        [pscustomobject]@{
            id = $File.id; name = $File.name; path = $finalItem.FullName; bytes = $finalItem.Length
            sha256 = $sha256; content_type = $received.ContentType
            reused_existing = $placed.Reused; browser_fallback_used = $browserFallback
        }
    } catch {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
        throw
    }
}

function Invoke-DryadDataFetch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Dataset,
        [string]$OutputDirectory, [string]$FileName, [switch]$All, [switch]$ListOnly,
        [string]$Profile, [string]$OpenCli, [string]$ConfigPath,
        [int]$ChallengeTimeoutSeconds, [long]$MaxBytes,
        [Parameter(DontShow = $true)][Uri]$ApiBaseUri = [Uri]'https://datadryad.org/api/v2/',
        [Parameter(DontShow = $true)][switch]$AllowTestApiBaseUri
    )
    $config = Read-ConfigFile -Path $ConfigPath
    $configuredOpenCli = Get-OptionalPropertyValue -Object $config -Name 'opencli'
    $configuredMaxBytes = Get-OptionalPropertyValue -Object $config -Name 'maxBytes'
    $configuredTimeout = Get-OptionalPropertyValue -Object $config -Name 'challengeTimeoutSeconds'
    if (-not $PSBoundParameters.ContainsKey('OpenCli')) {
        $OpenCli = if ($configuredOpenCli) { [string]$configuredOpenCli } else { [string]$env:OPENCLI_BIN }
    }
    if (-not $PSBoundParameters.ContainsKey('MaxBytes')) {
        $MaxBytes = if ($null -ne $configuredMaxBytes) { [long]$configuredMaxBytes } else { $script:DefaultMaxBytes }
    }
    if (-not $PSBoundParameters.ContainsKey('ChallengeTimeoutSeconds')) {
        $ChallengeTimeoutSeconds = if ($null -ne $configuredTimeout) { [int]$configuredTimeout } else { 75 }
    }
    if ($MaxBytes -le 0) { throw '-MaxBytes must be greater than zero.' }
    if ($ChallengeTimeoutSeconds -lt 15 -or $ChallengeTimeoutSeconds -gt 180) {
        throw '-ChallengeTimeoutSeconds must be between 15 and 180.'
    }
    if ($All -and $FileName) { throw 'Use either -All or -FileName, not both.' }
    if ($ListOnly -and ($All -or $FileName)) { throw '-ListOnly cannot be combined with -All or -FileName.' }

    Assert-ApiBaseUri -Uri $ApiBaseUri -AllowLoopback:$AllowTestApiBaseUri
    $identifier = Resolve-DryadIdentifier -Value $Dataset
    $client = New-DryadHttpClient
    try {
        $available = @(Get-DryadFilesFromApi -Client $client -BaseUri $ApiBaseUri -EncodedIdentifier $identifier.encoded_identifier -AllowLoopback:$AllowTestApiBaseUri)
        if ($available.Count -eq 0) { throw 'The latest public Dryad version contains no files.' }
        if ($ListOnly) {
            return ([pscustomobject]@{
                status = 'listed'; doi = $identifier.doi; dataset_url = $identifier.landing_url
                files = @($available | ForEach-Object {
                    [pscustomobject]@{ id = $_.id; name = $_.name; bytes = $_.size; content_type = $_.mime_type; digest = $_.digest; digest_type = $_.digest_type }
                })
            })
        }

        if ($All) { $selected = $available }
        elseif ($FileName) {
            $selected = @($available | Where-Object { $_.name -ceq $FileName })
            if ($selected.Count -eq 0) { throw "File not found in the latest Dryad version: $FileName" }
            if ($selected.Count -gt 1) { throw "Dryad returned duplicate file paths for: $FileName" }
        } elseif ($available.Count -eq 1) { $selected = $available }
        else {
            $names = ($available | ForEach-Object { $_.name }) -join "`n - "
            throw "Dataset contains multiple files. Use -ListOnly, -FileName, or explicit -All.`n - $names"
        }

        $safeDirectory = Resolve-SafeOutputDirectory -Value $OutputDirectory
        $downloads = foreach ($file in $selected) {
            Save-DryadFile -Client $client -File $file -Directory $safeDirectory -LandingUrl $identifier.landing_url -MaximumBytes $MaxBytes -ConfiguredOpenCli $OpenCli -RequestedProfile $Profile -TimeoutSeconds $ChallengeTimeoutSeconds -AllowLoopback:$AllowTestApiBaseUri
        }
        [pscustomobject]@{
            status = 'downloaded_and_verified'; doi = $identifier.doi; dataset_url = $identifier.landing_url
            files = @($downloads)
        }
    } finally { $client.Dispose() }
}

Export-ModuleMember -Function Invoke-DryadDataFetch
