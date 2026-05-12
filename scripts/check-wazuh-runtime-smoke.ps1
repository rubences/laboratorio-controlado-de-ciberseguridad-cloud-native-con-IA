param(
    [ValidateSet('Precheck', 'Auto', 'Runtime')]
    [string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'runtime-smoke-helpers.ps1')

$result = Invoke-WazuhRuntimeSmoke -RepoRoot $repoRoot -Mode $Mode
if ($result.FailCount -gt 0) {
    exit 1
}

exit 0
