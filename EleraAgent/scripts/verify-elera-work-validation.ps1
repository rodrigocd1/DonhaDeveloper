param(
    [Parameter(Position = 0)]
    [string]$Work = "W-018973"
)

function Write-Check {
    param(
        [string]$Name,
        [string]$Status
    )

    Write-Output ("{0}={1}" -f $Name, $Status)
}

$sfCommand = Get-Command sf -ErrorAction SilentlyContinue
if ($null -eq $sfCommand) {
    Write-Check "SF_CLI" "MISSING"
} else {
    Write-Check "SF_CLI" "FOUND"
}

$requiredVars = @(
    "SF_ELERA_USERNAME",
    "SF_ELERA_CLIENT_ID",
    "SF_ELERA_JWT_KEY_FILE",
    "SF_ELERA_INSTANCE_URL"
)

$missingVars = @()
foreach ($name in $requiredVars) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        $missingVars += $name
    }
}

if ($missingVars.Count -eq 0) {
    Write-Check "ENV_VARS" "FOUND"
} else {
    Write-Check "ENV_VARS" "MISSING"
}

$keyPath = [Environment]::GetEnvironmentVariable("SF_ELERA_JWT_KEY_FILE")
if (-not [string]::IsNullOrWhiteSpace($keyPath) -and (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
    Write-Check "JWT_KEY_FILE" "FOUND"
} else {
    Write-Check "JWT_KEY_FILE" "MISSING"
}

& sf org display --target-org elera-work-check --json *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Check "ALIAS" "FOUND"
} else {
    Write-Check "ALIAS" "AUTH_ERROR"
}

$checkScript = Join-Path $PSScriptRoot "check-work.ps1"
if (-not (Test-Path -LiteralPath $checkScript -PathType Leaf)) {
    Write-Check "CHECK_WORK_SCRIPT" "MISSING"
    exit 0
}

Write-Check "CHECK_WORK_SCRIPT" "FOUND"

$workResult = & $checkScript $Work
if ($workResult -in @("FOUND", "NOT_FOUND", "INVALID_WORK", "AUTH_ERROR")) {
    Write-Check "WORK_RESULT" $workResult
} else {
    Write-Check "WORK_RESULT" "UNKNOWN"
}
