[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\search_academic.ps1')).Path
$global:AcademicLiteratureSearchTestUris = @()

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)] [object]$Actual,
        [Parameter(Mandatory = $true)] [object]$Expected,
        [Parameter(Mandatory = $true)] [string]$Label
    )
    if ([string]$Actual -ne [string]$Expected) {
        throw "${Label}: expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)] [bool]$Condition,
        [Parameter(Mandatory = $true)] [string]$Label
    )
    if (-not $Condition) {
        throw "${Label}: condition was false."
    }
}

function global:Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec
    )
    $global:AcademicLiteratureSearchTestUris += $Uri

    if ($Uri -like 'https://api.crossref.org/works?*') {
        return [pscustomobject]@{
            message = [pscustomobject]@{
                items = @([pscustomobject]@{
                    DOI = '10.1000/test'
                    title = @('Crossref test title')
                    author = @([pscustomobject]@{ given = 'Ada'; family = 'Lovelace' })
                    'published-print' = [pscustomobject]@{ 'date-parts' = @(@(2024, 1, 2)) }
                    'container-title' = @()
                    type = 'journal-article'
                    URL = 'https://doi.org/10.1000/test'
                    abstract = '<jats:p>Test abstract</jats:p>'
                    'is-referenced-by-count' = 7
                })
            }
        }
    }

    if ($Uri -like 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?*') {
        return [pscustomobject]@{ esearchresult = [pscustomobject]@{ idlist = @('12345') } }
    }

    if ($Uri -like 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?*') {
        $result = [pscustomobject]@{}
        $result | Add-Member -NotePropertyName '12345' -NotePropertyValue ([pscustomobject]@{
            title = 'PubMed test title'
            authors = @([pscustomobject]@{ name = 'Grace Hopper' })
            pubdate = '2023 Jan'
            fulljournalname = 'Biomedical Test Journal'
            pubtype = @('Journal Article')
            articleids = @([pscustomobject]@{ idtype = 'doi'; value = '10.1000/pubmed' })
        })
        return [pscustomobject]@{ result = $result }
    }

    if ($Uri -like 'https://api.openalex.org/works?*') {
        return [pscustomobject]@{
            results = @(
                [pscustomobject]@{
                    title = 'OpenAlex test title'
                    authorships = @([pscustomobject]@{ author = [pscustomobject]@{ display_name = 'Katherine Johnson' } })
                    publication_year = 2022
                    primary_location = [pscustomobject]@{ source = [pscustomobject]@{ display_name = 'OpenAlex Journal' } }
                    type = 'article'
                    id = 'https://openalex.org/W123'
                    doi = 'https://doi.org/10.1000/openalex'
                    open_access = [pscustomobject]@{ is_oa = $true }
                    cited_by_count = 11
                }
                [pscustomobject]@{
                    title = 'OpenAlex sparse record'
                    authorships = @()
                    publication_year = 2020
                    primary_location = $null
                    type = 'article'
                    id = 'https://openalex.org/W456'
                    doi = $null
                    open_access = $null
                    cited_by_count = 0
                }
            )
        }
    }

    if ($Uri -like 'https://api.semanticscholar.org/graph/v1/paper/search?*') {
        return [pscustomobject]@{
            data = @([pscustomobject]@{
                paperId = 'S2-123'
                title = 'Semantic Scholar test title'
                authors = @([pscustomobject]@{ name = 'Dorothy Vaughan' })
                year = 2021
                venue = 'S2 Journal'
                publicationTypes = @('JournalArticle')
                externalIds = [pscustomobject]@{ DOI = '10.1000/s2' }
                url = 'https://www.semanticscholar.org/paper/S2-123'
                abstract = 'Semantic Scholar abstract'
                citationCount = 13
                isOpenAccess = $true
                openAccessPdf = [pscustomobject]@{ url = 'https://example.org/test.pdf' }
            })
        }
    }

    throw "Unexpected mocked REST URI: $Uri"
}

function global:Invoke-WebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec,
        [switch]$UseBasicParsing
    )
    $global:AcademicLiteratureSearchTestUris += $Uri
    if ($Uri -notlike 'https://export.arxiv.org/api/query?*') {
        throw "Unexpected mocked web URI: $Uri"
    }
    return [pscustomobject]@{
        Content = @'
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
  <entry>
    <id>https://arxiv.org/abs/2401.00001v1</id>
    <published>2024-01-01T00:00:00Z</published>
    <title>arXiv test title</title>
    <summary>arXiv test abstract</summary>
    <author><name>Mary Jackson</name></author>
    <arxiv:doi>10.1000/arxiv</arxiv:doi>
  </entry>
</feed>
'@
    }
}

function Invoke-TestSearch {
    param(
        [Parameter(Mandatory = $true)] [string]$Source,
        [Parameter(Mandatory = $true)] [string]$Query
    )
    $json = & $scriptPath -Source $Source -Query $Query -Limit 2
    return $json | ConvertFrom-Json
}

try {
    $crossref = Invoke-TestSearch -Source 'crossref' -Query 'test search'
    Assert-Equal $crossref.returned 1 'Crossref result count'
    Assert-Equal $crossref.results[0].doi '10.1000/test' 'Crossref DOI'
    Assert-Equal $crossref.results[0].authors[0] 'Ada Lovelace' 'Crossref author'
    Assert-True ($null -eq $crossref.results[0].venue) 'Crossref missing optional venue'

    $pubmed = Invoke-TestSearch -Source 'pubmed' -Query 'test search'
    Assert-Equal $pubmed.results[0].pmid '12345' 'PubMed PMID'
    Assert-Equal $pubmed.results[0].doi '10.1000/pubmed' 'PubMed DOI'

    $arxiv = Invoke-TestSearch -Source 'arxiv' -Query 'test search'
    Assert-Equal $arxiv.results[0].arxiv_id '2401.00001v1' 'arXiv identifier'
    Assert-Equal $arxiv.results[0].doi '10.1000/arxiv' 'arXiv DOI'
    Assert-True ($arxiv.results[0].url -like 'https://arxiv.org/*') 'arXiv HTTPS record URL'

    $openAlex = Invoke-TestSearch -Source 'openalex' -Query 'heat mortality'
    Assert-Equal $openAlex.results[0].openalex_id 'https://openalex.org/W123' 'OpenAlex identifier'
    Assert-True ([bool]$openAlex.results[0].is_open_access) 'OpenAlex open-access flag'
    Assert-Equal $openAlex.returned 2 'OpenAlex sparse result retained'
    Assert-True ($null -eq $openAlex.results[1].venue) 'OpenAlex missing optional venue'
    Assert-Equal $openAlex.results[1].authors.Count 0 'OpenAlex missing optional authors'

    $semanticScholar = Invoke-TestSearch -Source 'semantic-scholar' -Query 'test search'
    Assert-Equal $semanticScholar.results[0].semantic_scholar_id 'S2-123' 'Semantic Scholar identifier'
    Assert-Equal $semanticScholar.results[0].cited_by_count 13 'Semantic Scholar citation count'

    Assert-True ($global:AcademicLiteratureSearchTestUris.Count -eq 6) 'Expected mocked request count'
    Assert-True (@($global:AcademicLiteratureSearchTestUris | Where-Object { $_ -match '^http://' }).Count -eq 0) 'HTTPS-only endpoint invariant'
    Assert-True (@($global:AcademicLiteratureSearchTestUris | Where-Object { $_ -like '*heat%20mortality*' }).Count -eq 1) 'Query encoding invariant'

    $caught = $false
    try {
        & $scriptPath -Source 'crossref' -Query 'x' -Identifier '10.1000/x' | Out-Null
    }
    catch {
        $caught = $_.Exception.Message -like '*exactly one*'
    }
    Assert-True $caught 'Mutually-exclusive query and identifier guard'

    $caught = $false
    try {
        & $scriptPath -Source 'crossref' | Out-Null
    }
    catch {
        $caught = $_.Exception.Message -like '*exactly one*'
    }
    Assert-True $caught 'Required query or identifier guard'

    'PASS: academic literature search mocked all five sources and parameter guards.'
}
finally {
    Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
    Remove-Variable AcademicLiteratureSearchTestUris -Scope Global -ErrorAction SilentlyContinue
}
