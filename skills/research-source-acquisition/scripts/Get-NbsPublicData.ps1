[CmdletBinding()]
param(
    [ValidateSet('month', 'quarter', 'year')]
    [string]$Period = 'year',

    [Parameter(Mandatory)]
    [string[]]$CatalogPath,

    [string]$Indicator = '*',

    [Parameter(Mandatory)]
    [string]$DateSpec,

    [string]$OutCsv,

    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$baseUrl = 'https://data.stats.gov.cn/dg/website'
$periodCode = @{ month = 1; quarter = 2; year = 3 }[$Period]
$headers = @{
    Accept = 'application/json'
    Referer = "$baseUrl/page.html"
    'User-Agent' = 'Mozilla/5.0'
}

function Invoke-NbsGet {
    param([Parameter(Mandatory)][string]$Path)

    $response = Invoke-RestMethod -Uri "$baseUrl$Path" -Headers $headers -Method Get -TimeoutSec $TimeoutSeconds
    if (-not $response.success) {
        throw "国家统计局接口返回失败：$($response.message)"
    }
    return $response.data
}

$root = @(Invoke-NbsGet -Path "/publicrelease/web/external/new/queryIndexTreeAsync?pid=&code=$periodCode")
if ($root.Count -ne 1) {
    throw "未能唯一确定 $Period 根目录，实际返回 $($root.Count) 项。"
}

$rootId = $root[0]._id
$current = $root[0]

foreach ($segment in $CatalogPath) {
    $encodedPid = [uri]::EscapeDataString([string]$current._id)
    $children = @(Invoke-NbsGet -Path "/publicrelease/web/external/new/queryIndexTreeAsync?pid=$encodedPid&code=$periodCode")
    $normalizedSegment = $segment.Trim()
    $matches = @($children | Where-Object {
        ([string]$_.name).Trim() -eq $normalizedSegment -or
        ([string]$_._name).Trim() -eq $normalizedSegment
    })
    if ($matches.Count -ne 1) {
        $available = ($children | ForEach-Object { $_.name }) -join '、'
        throw "目录‘$segment’未唯一匹配。当前层可选项：$available"
    }
    $current = $matches[0]
}

$cid = [uri]::EscapeDataString([string]$current._id)
$indicatorResponse = Invoke-RestMethod `
    -Uri "$baseUrl/publicrelease/web/external/new/queryIndicatorsByCid?cid=$cid&dt=&name=" `
    -Headers $headers `
    -Method Get `
    -TimeoutSec $TimeoutSeconds

if (-not $indicatorResponse.success) {
    throw "指标接口返回失败：$($indicatorResponse.message)"
}

$indicators = @($indicatorResponse.data.list | Where-Object {
    $_.i_showname -like $Indicator -or $_._name -like $Indicator
})

if ($indicators.Count -eq 0) {
    $available = ($indicatorResponse.data.list | ForEach-Object { $_.i_showname.Trim() }) -join '、'
    throw "没有指标匹配‘$Indicator’。当前目录可选指标：$available"
}

$body = @{
    cid = [string]$current._id
    indicatorIds = @($indicators | ForEach-Object { [string]$_._id })
    daCatalogId = ''
    das = @(@{ text = '全国'; value = '000000000000' })
    showType = '1'
    dts = @($DateSpec)
    rootId = [string]$rootId
} | ConvertTo-Json -Depth 8

$result = Invoke-RestMethod `
    -Uri "$baseUrl/publicrelease/web/external/stream/esData" `
    -Headers $headers `
    -Method Post `
    -ContentType 'application/json; charset=utf-8' `
    -Body $body `
    -TimeoutSec $TimeoutSeconds

if (-not $result.success) {
    throw "数据接口返回失败：$($result.message)"
}

$rows = foreach ($periodItem in $result.data) {
    foreach ($valueItem in $periodItem.values) {
        [pscustomobject]@{
            period = $periodItem.name
            period_code = $periodItem.code
            indicator = $valueItem.i_showname.Trim()
            value = $valueItem.value
            unit = $valueItem.du_name
            area = $valueItem.da_name
            area_code = $valueItem.da
            indicator_id = $valueItem._id
            catalog = ($CatalogPath -join ' / ')
        }
    }
}

if ($OutCsv) {
    $resolvedOut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutCsv)
    if (Test-Path -LiteralPath $resolvedOut) {
        throw "输出文件已存在，拒绝覆盖：$resolvedOut"
    }
    $parent = Split-Path -Parent $resolvedOut
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "输出目录不存在，拒绝自行创建：$parent"
    }
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($resolvedOut) + '.' + [guid]::NewGuid().ToString('N') + '.partial')
    try {
        $rows | Export-Csv -LiteralPath $temporary -NoTypeInformation -Encoding utf8BOM
        if (Test-Path -LiteralPath $resolvedOut) {
            throw "写入期间目标文件出现，拒绝覆盖：$resolvedOut"
        }
        Move-Item -LiteralPath $temporary -Destination $resolvedOut
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
    Write-Verbose "已保存：$resolvedOut"
}

$rows
