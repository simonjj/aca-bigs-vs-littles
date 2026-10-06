[CmdletBinding()]
param(
    [string]$TestId = 'littles-vs-bigs'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$values = Get-AzdEnvironmentValues
$resourceGroup = Get-RequiredValue -Values $values -Name 'AZURE_RESOURCE_GROUP'
$loadTestingName = Get-RequiredValue -Values $values -Name 'LOAD_TESTING_NAME'
$littlesFqdn = Get-RequiredValue -Values $values -Name 'LITTLES_FQDN'
$bigsFqdn = Get-RequiredValue -Values $values -Name 'BIGS_FQDN'
$littlesAppName = Get-RequiredValue -Values $values -Name 'LITTLES_APP_NAME'
$bigsAppName = Get-RequiredValue -Values $values -Name 'BIGS_APP_NAME'
$root = Split-Path -Parent $PSScriptRoot
$testPlanPath = Join-Path (Join-Path $root 'load-tests') 'benchmark.jmx'

& az extension show --name load --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-AzCommand `
        -Operation 'install Azure Load Testing CLI extension' `
        -Arguments @('extension', 'add', '--name', 'load', '--upgrade', '--yes', '--only-show-errors')
}

function Wait-ForEndpoint {
    param(
        [Parameter(Mandatory)][string]$Scenario,
        [Parameter(Mandatory)][string]$Fqdn
    )

    foreach ($path in @('/health', '/work')) {
        $uri = "https://$Fqdn$path"
        for ($attempt = 1; $attempt -le 60; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri $uri -TimeoutSec 15
                if ($response.StatusCode -eq 200) {
                    break
                }
            } catch {
                if ($attempt -eq 60) {
                    throw "$Scenario endpoint '$uri' did not become healthy."
                }
                Start-Sleep -Seconds 10
            }
        }
    }
}

Wait-ForEndpoint -Scenario 'Littles' -Fqdn $littlesFqdn
Wait-ForEndpoint -Scenario 'Bigs' -Fqdn $bigsFqdn

$testExists = $true
& az load test show `
    --resource-group $resourceGroup `
    --load-test-resource $loadTestingName `
    --test-id $TestId `
    --output none `
    --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) {
    $testExists = $false
}

$testArguments = @(
    '--resource-group', $resourceGroup,
    '--load-test-resource', $loadTestingName,
    '--test-id', $TestId,
    '--display-name', 'Littles vs Bigs fixed-scale benchmark',
    '--description', 'Four-engine comparison of 32 x 0.5-vCPU single-process replicas and 16 x 1-vCPU two-worker PM2 replicas.',
    '--test-plan', $testPlanPath,
    '--engine-instances', '4',
    '--autostop', 'disable',
    '--env',
        "webapp_host=$littlesFqdn",
        'webapp_protocol=https',
        'webapp_path=/work',
        'threads=100',
        'duration=60',
        'ramp_up=10',
    '--output', 'none',
    '--only-show-errors'
)

if ($testExists) {
    Invoke-AzCommand -Operation 'update Azure Load Testing definition' -Arguments (@('load', 'test', 'update') + $testArguments)
} else {
    Invoke-AzCommand -Operation 'create Azure Load Testing definition' -Arguments (@('load', 'test', 'create') + $testArguments)
}

$littlesImage = Invoke-AzCommand `
    -Operation 'read deployed Littles image' `
    -CaptureOutput `
    -Arguments @(
        'containerapp', 'show',
        '--resource-group', $resourceGroup,
        '--name', $littlesAppName,
        '--query', "properties.template.containers[?name=='simulation'].image | [0]",
        '--output', 'tsv',
        '--only-show-errors'
    )
$bigsImage = Invoke-AzCommand `
    -Operation 'read deployed Bigs image' `
    -CaptureOutput `
    -Arguments @(
        'containerapp', 'show',
        '--resource-group', $resourceGroup,
        '--name', $bigsAppName,
        '--query', "properties.template.containers[?name=='simulation'].image | [0]",
        '--output', 'tsv',
        '--only-show-errors'
    )

& azd env set LOAD_TEST_ID $TestId
if ($LASTEXITCODE -ne 0) {
    throw 'Could not save LOAD_TEST_ID to the azd environment.'
}
& azd env set LITTLES_IMAGE $littlesImage
if ($LASTEXITCODE -ne 0) {
    throw 'Could not save the deployed Littles image to the azd environment.'
}
& azd env set BIGS_IMAGE $bigsImage
if ($LASTEXITCODE -ne 0) {
    throw 'Could not save the deployed Bigs image to the azd environment.'
}

Write-Host "Deployment is healthy. Azure Load Testing test '$TestId' is registered but has not been run."
