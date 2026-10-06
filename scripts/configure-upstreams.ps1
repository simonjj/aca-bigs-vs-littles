[CmdletBinding()]
param(
    [ValidateRange(1, 90)]
    [int]$SasLifetimeDays = 7
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$values = Get-AzdEnvironmentValues
$resourceGroup = Get-RequiredValue -Values $values -Name 'AZURE_RESOURCE_GROUP'
$littlesStorageName = Get-RequiredValue -Values $values -Name 'LITTLES_STORAGE_NAME'
$bigsStorageName = Get-RequiredValue -Values $values -Name 'BIGS_STORAGE_NAME'
$littlesBaseUrl = Get-RequiredValue -Values $values -Name 'LITTLES_UPSTREAM_BASE_URL'
$bigsBaseUrl = Get-RequiredValue -Values $values -Name 'BIGS_UPSTREAM_BASE_URL'
$littlesAppName = Get-RequiredValue -Values $values -Name 'LITTLES_APP_NAME'
$bigsAppName = Get-RequiredValue -Values $values -Name 'BIGS_APP_NAME'

$payloadPath = Join-Path ([System.IO.Path]::GetTempPath()) "aca-lvb-payload-$([guid]::NewGuid().ToString('N')).json"
'{"status":"ok","source":"aca-bigs-vs-littles-upstream"}' |
    Set-Content -Path $payloadPath -Encoding utf8NoBOM

$targets = @(
    @{
        Scenario = 'Littles'
        StorageName = $littlesStorageName
        BaseUrl = $littlesBaseUrl
        AppName = $littlesAppName
        SavedImage = if ($values.ContainsKey('LITTLES_IMAGE')) { [string]$values.LITTLES_IMAGE } else { '' }
    },
    @{
        Scenario = 'Bigs'
        StorageName = $bigsStorageName
        BaseUrl = $bigsBaseUrl
        AppName = $bigsAppName
        SavedImage = if ($values.ContainsKey('BIGS_IMAGE')) { [string]$values.BIGS_IMAGE } else { '' }
    }
)

$sasExpiry = (Get-Date).ToUniversalTime().AddDays($SasLifetimeDays).ToString('yyyy-MM-ddTHH:mmZ')

try {
    foreach ($target in $targets) {
        Write-Host "Configuring the private $($target.Scenario) upstream..."

        $storageKey = Invoke-AzCommand `
            -Operation "read $($target.Scenario) storage key" `
            -CaptureOutput `
            -Arguments @(
                'storage', 'account', 'keys', 'list',
                '--resource-group', $resourceGroup,
                '--account-name', $target.StorageName,
                '--query', '[0].value',
                '--output', 'tsv',
                '--only-show-errors'
            )

        Invoke-AzCommand `
            -Operation "upload $($target.Scenario) upstream payload" `
            -Arguments @(
                'storage', 'blob', 'upload',
                '--account-name', $target.StorageName,
                '--account-key', $storageKey,
                '--container-name', 'upstream',
                '--name', 'payload.json',
                '--file', $payloadPath,
                '--overwrite', 'true',
                '--content-type', 'application/json',
                '--output', 'none',
                '--only-show-errors'
            )

        $sasToken = Invoke-AzCommand `
            -Operation "create $($target.Scenario) read-only SAS" `
            -CaptureOutput `
            -Arguments @(
                'storage', 'blob', 'generate-sas',
                '--account-name', $target.StorageName,
                '--account-key', $storageKey,
                '--container-name', 'upstream',
                '--name', 'payload.json',
                '--permissions', 'r',
                '--expiry', $sasExpiry,
                '--https-only',
                '--output', 'tsv',
                '--only-show-errors'
            )

        $upstreamUrl = "$($target.BaseUrl)?$sasToken"
        Invoke-AzCommand `
            -Operation "set $($target.Scenario) upstream secret" `
            -Arguments @(
                'containerapp', 'secret', 'set',
                '--resource-group', $resourceGroup,
                '--name', $target.AppName,
                '--secrets', "upstream-url=$upstreamUrl",
                '--output', 'none',
                '--only-show-errors'
            )

        if (-not [string]::IsNullOrWhiteSpace($target.SavedImage) -and
            $target.SavedImage -ne 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest') {
            Invoke-AzCommand `
                -Operation "restore $($target.Scenario) application image" `
                -Arguments @(
                    'containerapp', 'update',
                    '--resource-group', $resourceGroup,
                    '--name', $target.AppName,
                    '--image', $target.SavedImage,
                    '--output', 'none',
                    '--only-show-errors'
                )
        }
    }
} finally {
    Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Private upstream payloads and $SasLifetimeDays-day read-only SAS secrets are configured."
