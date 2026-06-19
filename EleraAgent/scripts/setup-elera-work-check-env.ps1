param(
    [Parameter(Position = 0)]
    [string]$ClientId,

    [string]$Username = "integration.cli@elera.io",

    [string]$JwtKeyFile = "$env:USERPROFILE\.salesforce-jwt\elera-work-check.key",

    [string]$InstanceUrl = "https://login.salesforce.com",

    [switch]$ProcessOnly
)

function Write-Status {
    param([string]$Status)
    Write-Output $Status
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ClientId)) {
    $ClientId = [Environment]::GetEnvironmentVariable("SF_ELERA_CLIENT_ID")
}

if ([string]::IsNullOrWhiteSpace($ClientId)) {
    Write-Status "MISSING_CLIENT_ID"
}

if (-not (Test-Path -LiteralPath $JwtKeyFile -PathType Leaf)) {
    Write-Status "MISSING_JWT_KEY_FILE"
}

$scope = if ($ProcessOnly) { "Process" } else { "User" }

[Environment]::SetEnvironmentVariable("SF_ELERA_USERNAME", $Username, $scope)
[Environment]::SetEnvironmentVariable("SF_ELERA_CLIENT_ID", $ClientId, $scope)
[Environment]::SetEnvironmentVariable("SF_ELERA_JWT_KEY_FILE", $JwtKeyFile, $scope)
[Environment]::SetEnvironmentVariable("SF_ELERA_INSTANCE_URL", $InstanceUrl, $scope)

$env:SF_ELERA_USERNAME = $Username
$env:SF_ELERA_CLIENT_ID = $ClientId
$env:SF_ELERA_JWT_KEY_FILE = $JwtKeyFile
$env:SF_ELERA_INSTANCE_URL = $InstanceUrl

Write-Status "ENV_OK"
