[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Dataset,
    [string]$OutputDirectory,
    [string]$FileName,
    [switch]$All,
    [switch]$ListOnly,
    [string]$Profile,
    [string]$OpenCli,
    [string]$ConfigPath,
    [int]$ChallengeTimeoutSeconds,
    [long]$MaxBytes,
    [Parameter(DontShow = $true)][Uri]$ApiBaseUri = [Uri]'https://datadryad.org/api/v2/',
    [Parameter(DontShow = $true)][switch]$AllowTestApiBaseUri
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DryadDataFetcher.psm1') -Force
$result = Invoke-DryadDataFetch @PSBoundParameters
$result | ConvertTo-Json -Depth 7
