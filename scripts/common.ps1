Set-StrictMode -Version Latest

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Get-AzdEnvironmentValues {
    Assert-Command -Name 'azd'

    $rawValues = & azd env get-values --output json
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the selected azd environment.'
    }

    $rawValues | ConvertFrom-Json -AsHashtable
}

function Get-RequiredValue {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Values.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$Name])) {
        return [string]$Values[$Name]
    }

    throw "Required azd environment value '$Name' is missing. Run 'azd provision' first."
}

function Invoke-AzCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation,
        [switch]$CaptureOutput
    )

    Assert-Command -Name 'az'
    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | Out-String).Trim()
        throw "Azure CLI operation '$Operation' failed. $detail"
    }

    if ($CaptureOutput) {
        return ($output | Out-String).Trim()
    }
}
