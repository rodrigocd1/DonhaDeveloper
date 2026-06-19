param()

function Write-Status {
    param([string]$Status)
    Write-Output $Status
    exit 0
}

$requiredVars = @(
    'SF_ELERA_USERNAME',
    'SF_ELERA_CLIENT_ID',
    'SF_ELERA_JWT_KEY_FILE',
    'SF_ELERA_INSTANCE_URL'
)

foreach ($name in $requiredVars) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Status 'AUTH_ERROR'
    }
}

if (-not (Test-Path -LiteralPath $env:SF_ELERA_JWT_KEY_FILE -PathType Leaf)) {
    Write-Status 'AUTH_ERROR'
}

& sf org login jwt `
    --username $env:SF_ELERA_USERNAME `
    --client-id $env:SF_ELERA_CLIENT_ID `
    --jwt-key-file $env:SF_ELERA_JWT_KEY_FILE `
    --instance-url $env:SF_ELERA_INSTANCE_URL `
    --alias elera-work-check `
    --json *> $null

if ($LASTEXITCODE -eq 0) {
    Write-Status 'AUTH_OK'
}

Write-Status 'AUTH_ERROR'
