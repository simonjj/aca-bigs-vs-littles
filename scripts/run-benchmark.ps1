[CmdletBinding()]
param(
    [int]$Repetitions = 3,
    [int]$ThreadsPerEngine = 500,
    [int]$DurationSeconds = 180,
    [int]$RampUpSeconds = 15,
    [int]$WarmupThreadsPerEngine = 100,
    [int]$WarmupDurationSeconds = 60,
    [switch]$SkipWarmup,
    [switch]$ConfirmBenchmarkRun,
    [string]$OutputPrefix = 'benchmark-runs'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $ConfirmBenchmarkRun) {
    throw 'Azure Load Testing runs are billable. Re-run with -ConfirmBenchmarkRun after reviewing the requested load and duration.'
}

foreach ($value in @($Repetitions, $ThreadsPerEngine, $DurationSeconds, $RampUpSeconds, $WarmupThreadsPerEngine, $WarmupDurationSeconds)) {
    if ($value -lt 0) {
        throw 'Benchmark numeric parameters cannot be negative.'
    }
}
if ($Repetitions -lt 1 -or $ThreadsPerEngine -lt 1 -or $DurationSeconds -lt 1) {
    throw 'Repetitions, ThreadsPerEngine, and DurationSeconds must be at least 1.'
}

$values = Get-AzdEnvironmentValues
$resourceGroup = Get-RequiredValue -Values $values -Name 'AZURE_RESOURCE_GROUP'
$loadTestingName = Get-RequiredValue -Values $values -Name 'LOAD_TESTING_NAME'
$testId = if ($values.ContainsKey('LOAD_TEST_ID')) { [string]$values.LOAD_TEST_ID } else { 'littles-vs-bigs' }
$littlesFqdn = Get-RequiredValue -Values $values -Name 'LITTLES_FQDN'
$bigsFqdn = Get-RequiredValue -Values $values -Name 'BIGS_FQDN'
$root = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $root 'artifacts'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

function Invoke-LoadRun {
    param(
        [Parameter(Mandatory)][string]$Scenario,
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][int]$Threads,
        [Parameter(Mandatory)][int]$Duration,
        [Parameter(Mandatory)][int]$RampUp
    )

    Write-Host "Starting $RunId against $Scenario ($HostName)..."
    Invoke-AzCommand `
        -Operation "start load-test run $RunId" `
        -Arguments @(
            'load', 'test-run', 'create',
            '--resource-group', $resourceGroup,
            '--load-test-resource', $loadTestingName,
            '--test-id', $testId,
            '--test-run-id', $RunId,
            '--display-name', $RunId,
            '--description', "$Scenario; 4 engines; $Threads threads/engine; ${Duration}s duration",
            '--env',
                "webapp_host=$HostName",
                'webapp_protocol=https',
                'webapp_path=/work',
                "threads=$Threads",
                "duration=$Duration",
                "ramp_up=$RampUp",
            '--output', 'none',
            '--only-show-errors'
        )

    $resultJson = Invoke-AzCommand `
        -Operation "read load-test run $RunId" `
        -CaptureOutput `
        -Arguments @(
            'load', 'test-run', 'show',
            '--resource-group', $resourceGroup,
            '--load-test-resource', $loadTestingName,
            '--test-run-id', $RunId,
            '--output', 'json',
            '--only-show-errors'
        )
    $result = $resultJson | ConvertFrom-Json

    function Get-MetricData {
        param(
            [Parameter(Mandatory)][string]$MetricName,
            [Parameter(Mandatory)][string]$Aggregation
        )

        $metricJson = Invoke-AzCommand `
            -Operation "read $MetricName/$Aggregation metrics for $RunId" `
            -CaptureOutput `
            -Arguments @(
                'load', 'test-run', 'metrics', 'list',
                '--resource-group', $resourceGroup,
                '--load-test-resource', $loadTestingName,
                '--test-run-id', $RunId,
                '--metric-namespace', 'LoadTestRunMetrics',
                '--metric-name', $MetricName,
                '--aggregation', $Aggregation,
                '--interval', 'PT5M',
                '--output', 'json',
                '--only-show-errors'
            )
        $metric = $metricJson | ConvertFrom-Json
        @($metric | ForEach-Object { $_.data } | Where-Object { $_ })
    }

    $requestData = Get-MetricData -MetricName 'TotalRequests' -Aggregation 'Total'
    $errorData = Get-MetricData -MetricName 'Errors' -Aggregation 'Total'
    $averageData = Get-MetricData -MetricName 'ResponseTime' -Aggregation 'Average'
    $p90Data = Get-MetricData -MetricName 'ResponseTime' -Aggregation 'Percentile90'
    $p95Data = Get-MetricData -MetricName 'ResponseTime' -Aggregation 'Percentile95'
    $p99Data = Get-MetricData -MetricName 'ResponseTime' -Aggregation 'Percentile99'

    $sampleCount = ($requestData | Measure-Object -Property value -Sum).Sum
    $errorCount = ($errorData | Measure-Object -Property value -Sum).Sum
    if ($null -eq $errorCount) {
        $errorCount = 0
    }

    $weightedResponseTotal = 0.0
    foreach ($averagePoint in $averageData) {
        $requestPoint = $requestData |
            Where-Object { $_.timestamp -eq $averagePoint.timestamp } |
            Select-Object -First 1
        if ($requestPoint) {
            $weightedResponseTotal += [double]$averagePoint.value * [double]$requestPoint.value
        }
    }
    $meanResponseMs = if ($sampleCount -gt 0) { $weightedResponseTotal / $sampleCount } else { 0 }

    [pscustomobject]@{
        scenario = $Scenario
        runId = $RunId
        status = $result.status
        startedAt = $result.startDateTime
        endedAt = $result.endDateTime
        engines = 4
        threadsPerEngine = $Threads
        totalVirtualUsers = 4 * $Threads
        durationSeconds = $Duration
        sampleCount = [double]$sampleCount
        errorCount = [double]$errorCount
        errorPct = if ($sampleCount -gt 0) { 100.0 * $errorCount / $sampleCount } else { 0 }
        throughputRps = if ($Duration -gt 0) { $sampleCount / $Duration } else { 0 }
        meanResponseMs = [math]::Round($meanResponseMs, 2)
        p90ResponseMs = [double](($p90Data | Measure-Object -Property value -Maximum).Maximum)
        p95ResponseMs = [double](($p95Data | Measure-Object -Property value -Maximum).Maximum)
        p99ResponseMs = [double](($p99Data | Measure-Object -Property value -Maximum).Maximum)
    }
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$summary = @()

if (-not $SkipWarmup) {
    $summary += Invoke-LoadRun `
        -Scenario 'littles-warmup' `
        -HostName $littlesFqdn `
        -RunId "littles-warmup-$stamp" `
        -Threads $WarmupThreadsPerEngine `
        -Duration $WarmupDurationSeconds `
        -RampUp 10

    $summary += Invoke-LoadRun `
        -Scenario 'bigs-warmup' `
        -HostName $bigsFqdn `
        -RunId "bigs-warmup-$stamp" `
        -Threads $WarmupThreadsPerEngine `
        -Duration $WarmupDurationSeconds `
        -RampUp 10
}

for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
    $summary += Invoke-LoadRun `
        -Scenario 'littles' `
        -HostName $littlesFqdn `
        -RunId "littles-$iteration-$stamp" `
        -Threads $ThreadsPerEngine `
        -Duration $DurationSeconds `
        -RampUp $RampUpSeconds

    $summary += Invoke-LoadRun `
        -Scenario 'bigs' `
        -HostName $bigsFqdn `
        -RunId "bigs-$iteration-$stamp" `
        -Threads $ThreadsPerEngine `
        -Duration $DurationSeconds `
        -RampUp $RampUpSeconds
}

$summaryJsonPath = Join-Path $artifacts "$OutputPrefix.json"
$summaryCsvPath = Join-Path $artifacts "$OutputPrefix.csv"
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryJsonPath -Encoding utf8NoBOM
$summary | Export-Csv -Path $summaryCsvPath -NoTypeInformation -Encoding utf8

Write-Host "Run summary written to $summaryJsonPath and $summaryCsvPath"
$summary |
    Format-Table scenario, runId, sampleCount, errorPct, throughputRps, meanResponseMs, p95ResponseMs, p99ResponseMs -AutoSize
