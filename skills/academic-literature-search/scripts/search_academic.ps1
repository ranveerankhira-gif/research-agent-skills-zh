[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('crossref', 'pubmed', 'arxiv', 'openalex', 'semantic-scholar')]
    [string]$Source,

    [string]$Query,

    [string]$Identifier,

    [ValidateRange(1, 50)]
    [int]$Limit = 10,

    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($Query) -eq [string]::IsNullOrWhiteSpace($Identifier)) {
    throw 'Provide exactly one of -Query or -Identifier.'
}

$retrievedAt = [DateTimeOffset]::UtcNow.ToString('o')
$headers = @{
    'User-Agent' = 'CodexAcademicLiteratureSearch/0.1.0'
    'Accept' = 'application/json, application/atom+xml, application/xml;q=0.9, */*;q=0.1'
}

function Encode-Value([string]$Value) {
    return [Uri]::EscapeDataString($Value.Trim())
}

function Get-ObjectProperty([object]$Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-NestedObjectProperty([object]$Object, [string[]]$Path) {
    $value = $Object
    foreach ($name in $Path) {
        $value = Get-ObjectProperty $value $name
        if ($null -eq $value) { return $null }
    }
    return $value
}

function Get-FirstValue([object]$Value) {
    if ($null -eq $Value) { return $null }
    $values = @($Value)
    if ($values.Count -eq 0) { return $null }
    return $values[0]
}

function Remove-Html([object]$Value) {
    if ($null -eq $Value) { return $null }
    return [Net.WebUtility]::HtmlDecode(([regex]::Replace([string]$Value, '<[^>]+>', ' '))).Trim()
}

function Get-CrossrefAuthors([object]$Authors) {
    if ($null -eq $Authors) { return @() }
    return @($Authors | ForEach-Object {
        (@($_.given, $_.family) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' '
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-CrossrefYear([object]$Item) {
    foreach ($field in @('published-print', 'published-online', 'issued', 'created')) {
        $value = Get-ObjectProperty $Item $field
        $dateParts = Get-ObjectProperty $value 'date-parts'
        if ($null -ne $dateParts) {
            $firstDate = Get-FirstValue $dateParts
            $year = Get-FirstValue $firstDate
            if ($null -ne $year) {
                return [int]$year
            }
        }
    }
    return $null
}

try {
    $results = @()

    switch ($Source) {
        'crossref' {
            if ($Identifier) {
                $doi = $Identifier.Trim() -replace '^https?://(dx\.)?doi\.org/', '' -replace '^doi:', ''
                $uri = 'https://api.crossref.org/works/' + (Encode-Value $doi)
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
                $items = @($response.message)
            }
            else {
                $uri = 'https://api.crossref.org/works?query.bibliographic=' + (Encode-Value $Query) + '&rows=' + $Limit + '&select=DOI,title,author,published-print,published-online,issued,created,container-title,type,URL,abstract,is-referenced-by-count'
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
                $items = @($response.message.items)
            }

            $results = @($items | ForEach-Object {
                [ordered]@{
                    source = 'Crossref'
                    title = Get-FirstValue (Get-ObjectProperty $_ 'title')
                    authors = @(Get-CrossrefAuthors (Get-ObjectProperty $_ 'author'))
                    year = Get-CrossrefYear $_
                    venue = Get-FirstValue (Get-ObjectProperty $_ 'container-title')
                    type = Get-ObjectProperty $_ 'type'
                    doi = Get-ObjectProperty $_ 'DOI'
                    url = Get-ObjectProperty $_ 'URL'
                    abstract = Remove-Html (Get-ObjectProperty $_ 'abstract')
                    cited_by_count = Get-ObjectProperty $_ 'is-referenced-by-count'
                }
            })
        }

        'pubmed' {
            if ($Identifier) {
                $term = if ($Identifier.Trim() -match '^\d+$') { $Identifier.Trim() + '[pmid]' } else { ($Identifier.Trim() -replace '^doi:', '') + '[doi]' }
                $retmax = 1
            }
            else {
                $term = $Query
                $retmax = $Limit
            }

            $searchUri = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax=' + $retmax + '&term=' + (Encode-Value $term)
            $search = Invoke-RestMethod -Uri $searchUri -Headers $headers -TimeoutSec $TimeoutSeconds
            $ids = @($search.esearchresult.idlist)
            if ($ids.Count -gt 0) {
                $summaryUri = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&id=' + ($ids -join ',')
                $summary = Invoke-RestMethod -Uri $summaryUri -Headers $headers -TimeoutSec $TimeoutSeconds
                $results = @($ids | ForEach-Object {
                    $item = $summary.result.$_
                    $doi = Get-FirstValue @($item.articleids | Where-Object { $_.idtype -eq 'doi' } | ForEach-Object { $_.value })
                    [ordered]@{
                        source = 'PubMed'
                        title = Remove-Html $item.title
                        authors = @($item.authors | ForEach-Object { $_.name })
                        year = if ($item.pubdate -match '\d{4}') { [int]$Matches[0] } else { $null }
                        venue = $item.fulljournalname
                        type = @($item.pubtype)
                        pmid = $_
                        doi = $doi
                        url = 'https://pubmed.ncbi.nlm.nih.gov/' + $_ + '/'
                        abstract = $null
                        cited_by_count = $null
                    }
                })
            }
        }

        'arxiv' {
            if ($Identifier) {
                $uri = 'https://export.arxiv.org/api/query?id_list=' + (Encode-Value ($Identifier.Trim() -replace '^arxiv:', ''))
            }
            else {
                $uri = 'https://export.arxiv.org/api/query?search_query=all:' + (Encode-Value $Query) + '&start=0&max_results=' + $Limit + '&sortBy=relevance&sortOrder=descending'
            }

            $raw = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
            [xml]$xml = $raw.Content
            $entries = @($xml.feed.entry)
            $results = @($entries | ForEach-Object {
                $entryUrl = ([string]$_.id) -replace '^http://arxiv\.org/', 'https://arxiv.org/'
                $arxivId = ($entryUrl -split '/abs/')[-1]
                $doiNode = @($_.ChildNodes | Where-Object { $_.LocalName -eq 'doi' } | Select-Object -First 1)
                [ordered]@{
                    source = 'arXiv'
                    title = ([string]$_.title -replace '\s+', ' ').Trim()
                    authors = @($_.author | ForEach-Object { [string]$_.name })
                    year = if ([string]$_.published -match '^\d{4}') { [int]$Matches[0] } else { $null }
                    venue = 'arXiv'
                    type = 'preprint'
                    arxiv_id = $arxivId
                    doi = if ($doiNode.Count -gt 0) { [string]$doiNode[0].InnerText } else { $null }
                    url = $entryUrl
                    abstract = ([string]$_.summary -replace '\s+', ' ').Trim()
                    cited_by_count = $null
                }
            })
        }

        'openalex' {
            if ($Identifier) {
                $id = $Identifier.Trim() -replace '^https?://(dx\.)?doi\.org/', '' -replace '^doi:', ''
                $uri = 'https://api.openalex.org/works?filter=doi:' + (Encode-Value $id) + '&per-page=1'
            }
            else {
                $uri = 'https://api.openalex.org/works?search=' + (Encode-Value $Query) + '&per-page=' + $Limit
            }

            $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
            if ($response -is [string]) {
                $response = $response | ConvertFrom-Json -AsHashtable
            }
            $results = @($response.results | ForEach-Object {
                $authorships = Get-ObjectProperty $_ 'authorships'
                [ordered]@{
                    source = 'OpenAlex'
                    title = Get-ObjectProperty $_ 'title'
                    authors = @($authorships | ForEach-Object {
                        Get-NestedObjectProperty $_ @('author', 'display_name')
                    } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
                    year = Get-ObjectProperty $_ 'publication_year'
                    venue = Get-NestedObjectProperty $_ @('primary_location', 'source', 'display_name')
                    type = Get-ObjectProperty $_ 'type'
                    openalex_id = Get-ObjectProperty $_ 'id'
                    doi = Get-ObjectProperty $_ 'doi'
                    url = Get-ObjectProperty $_ 'id'
                    abstract = $null
                    is_open_access = Get-NestedObjectProperty $_ @('open_access', 'is_oa')
                    cited_by_count = Get-ObjectProperty $_ 'cited_by_count'
                }
            })
        }

        'semantic-scholar' {
            $fields = 'paperId,title,authors,year,venue,publicationTypes,externalIds,url,abstract,citationCount,isOpenAccess,openAccessPdf'
            if ($Identifier) {
                $uri = 'https://api.semanticscholar.org/graph/v1/paper/' + (Encode-Value $Identifier) + '?fields=' + $fields
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
                $items = @($response)
            }
            else {
                $uri = 'https://api.semanticscholar.org/graph/v1/paper/search?query=' + (Encode-Value $Query) + '&limit=' + $Limit + '&fields=' + $fields
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
                $items = @($response.data)
            }

            $results = @($items | ForEach-Object {
                $openAccessPdf = Get-ObjectProperty $_ 'openAccessPdf'
                $authors = Get-ObjectProperty $_ 'authors'
                [ordered]@{
                    source = 'Semantic Scholar'
                    title = Get-ObjectProperty $_ 'title'
                    authors = @($authors | ForEach-Object {
                        Get-ObjectProperty $_ 'name'
                    } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
                    year = Get-ObjectProperty $_ 'year'
                    venue = Get-ObjectProperty $_ 'venue'
                    type = @(Get-ObjectProperty $_ 'publicationTypes')
                    semantic_scholar_id = Get-ObjectProperty $_ 'paperId'
                    external_ids = Get-ObjectProperty $_ 'externalIds'
                    url = Get-ObjectProperty $_ 'url'
                    abstract = Get-ObjectProperty $_ 'abstract'
                    is_open_access = Get-ObjectProperty $_ 'isOpenAccess'
                    open_access_pdf = Get-ObjectProperty $openAccessPdf 'url'
                    cited_by_count = Get-ObjectProperty $_ 'citationCount'
                }
            })
        }
    }

    [ordered]@{
        source = $Source
        retrieved_at = $retrievedAt
        query = if ($Query) { $Query } else { $null }
        identifier = if ($Identifier) { $Identifier } else { $null }
        returned = $results.Count
        results = $results
    } | ConvertTo-Json -Depth 10
}
catch {
    [Console]::Error.WriteLine(('Academic search failed for {0}: {1}' -f $Source, $_.Exception.Message))
    exit 1
}
