param(
    [Parameter(Position = 0)]
    [string]$Work
)

function Write-Status {
    param([string]$Status)
    Write-Output $Status
    exit 0
}

function Normalize-Work {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $candidate = $Value.Trim() -replace '\\', '/'
    $candidate = $candidate -replace '^works/', ''
    $candidate = $candidate.Trim('/')

    $markdownLink = [regex]::Match($candidate, '^\[(?<text>[^\]]+)\]\((?<url>[^)]+)\)$')
    if ($markdownLink.Success) {
        $candidate = $markdownLink.Groups['text'].Value.Trim()
    }

    $match = [regex]::Match($candidate, '^(?<prefix>[Ww])[-\s]*(?<number>\d{1,6})$')
    if (-not $match.Success) {
        return $null
    }

    $number = [int]$match.Groups['number'].Value
    return ('W-{0:D6}' -f $number)
}

$normalizedWork = Normalize-Work $Work
if ($null -eq $normalizedWork) {
    Write-Status 'INVALID_WORK'
}

& sf org display --target-org elera-work-check --json *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Status 'AUTH_ERROR'
}

$escapedWork = $normalizedWork -replace "'", "''"
$query = "SELECT Id FROM agf__ADM_Work__c WHERE Name = '$escapedWork' LIMIT 1"
$queryOutput = & sf data query --target-org elera-work-check --query $query --json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Status 'AUTH_ERROR'
}

try {
    $result = $queryOutput | ConvertFrom-Json
    if ($result.result.totalSize -gt 0) {
        Write-Status 'FOUND'
    }

    Write-Status 'NOT_FOUND'
} catch {
    Write-Status 'AUTH_ERROR'
}
