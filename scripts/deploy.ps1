[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

& azd up
if ($LASTEXITCODE -ne 0) {
    throw "'azd up' failed."
}
