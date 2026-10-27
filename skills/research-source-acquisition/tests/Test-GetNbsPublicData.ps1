[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Get-NbsPublicData.ps1')).Path
$global:NbsPublicDataTestRequests = @()

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Label)
    if (-not $Condition) { throw "$Label failed." }
}

function global:Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers,
        [string]$Method,
        [string]$ContentType,
        [string]$Body,
        [int]$TimeoutSec
    )
    $global:NbsPublicDataTestRequests += [pscustomobject]@{
        Uri = $Uri; Method = $Method; Body = $Body; TimeoutSec = $TimeoutSec
    }
    if ($Uri -like '*queryIndexTreeAsync?pid=&code=3') {
        return [pscustomobject]@{ success = $true; data = @([pscustomobject]@{ _id = 'root'; name = '年度数据' }) }
    }
    if ($Uri -like '*queryIndexTreeAsync?pid=root&code=3') {
        return [pscustomobject]@{ success = $true; data = @([pscustomobject]@{ _id = 'gdp'; name = '国内生产总值'; _name = '国内生产总值' }) }
    }
    if ($Uri -like '*queryIndicatorsByCid?cid=gdp*') {
        return [pscustomobject]@{
            success = $true
            data = [pscustomobject]@{
                list = @([pscustomobject]@{ _id = 'A0201'; i_showname = '国内生产总值'; _name = 'GDP' })
            }
        }
    }
    if ($Uri -like '*/stream/esData') {
        return [pscustomobject]@{
            success = $true
            data = @([pscustomobject]@{
                name = '2024年'; code = '2024'
                values = @([pscustomobject]@{
                    i_showname = '国内生产总值'; value = '100'; du_name = '亿元'
                    da_name = '全国'; da = '000000000000'; _id = 'A0201'
                })
            })
        }
    }
    throw "Unexpected mocked URI: $Uri"
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('nbs-public-data-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
    $rows = @(& $scriptPath -CatalogPath '国内生产总值' -Indicator '国内生产总值' -DateSpec '2024' -TimeoutSeconds 17)
    Assert-True ($rows.Count -eq 1) 'Expected one normalized row'
    Assert-True ($rows[0].value -eq '100') 'Expected mocked value'
    Assert-True (@($global:NbsPublicDataTestRequests | Where-Object { $_.TimeoutSec -ne 17 }).Count -eq 0) 'Timeout forwarding'

    $output = Join-Path $temporaryRoot 'result.csv'
    & $scriptPath -CatalogPath '国内生产总值' -Indicator '国内生产总值' -DateSpec '2024' -OutCsv $output | Out-Null
    Assert-True (Test-Path -LiteralPath $output -PathType Leaf) 'CSV output created'
    Assert-True (@(Get-ChildItem -LiteralPath $temporaryRoot -Filter '*.partial').Count -eq 0) 'No partial files remain'

    $collisionRejected = $false
    try {
        & $scriptPath -CatalogPath '国内生产总值' -Indicator '国内生产总值' -DateSpec '2024' -OutCsv $output | Out-Null
    }
    catch {
        $collisionRejected = $_.Exception.Message -like '*拒绝覆盖*'
    }
    Assert-True $collisionRejected 'Existing output rejected'

    $missingParentRejected = $false
    try {
        & $scriptPath -CatalogPath '国内生产总值' -Indicator '国内生产总值' -DateSpec '2024' -OutCsv (Join-Path $temporaryRoot 'missing\result.csv') | Out-Null
    }
    catch {
        $missingParentRejected = $_.Exception.Message -like '*拒绝自行创建*'
    }
    Assert-True $missingParentRejected 'Missing output directory rejected'

    'PASS: NBS helper mocked endpoints, timeout, atomic output, and collision guards.'
}
finally {
    Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    Remove-Variable NbsPublicDataTestRequests -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
