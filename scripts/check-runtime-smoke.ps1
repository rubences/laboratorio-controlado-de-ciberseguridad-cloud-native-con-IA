param(
    [ValidateSet('All', 'Wazuh', 'Caldera')]
    [string]$Stack = 'All',

    [ValidateSet('Precheck', 'Auto', 'Runtime')]
    [string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'runtime-smoke-helpers.ps1')

$results = @()
switch ($Stack) {
    'All' {
        $results += Invoke-WazuhRuntimeSmoke -RepoRoot $repoRoot -Mode $Mode
        $results += Invoke-CalderaRuntimeSmoke -RepoRoot $repoRoot -Mode $Mode
    }
    'Wazuh' {
        $results += Invoke-WazuhRuntimeSmoke -RepoRoot $repoRoot -Mode $Mode
    }
    'Caldera' {
        $results += Invoke-CalderaRuntimeSmoke -RepoRoot $repoRoot -Mode $Mode
    }
}

$totalFails = ($results | Measure-Object -Property FailCount -Sum).Sum
$totalWarnings = ($results | Measure-Object -Property WarnCount -Sum).Sum
$totalOk = ($results | Measure-Object -Property OkCount -Sum).Sum

$summaryColor = if ($totalFails -gt 0) { 'Red' } elseif ($totalWarnings -gt 0) { 'Yellow' } else { 'Green' }

Write-Host "" 
Write-Host ("Runtime smoke consolidado -> Stack={0} Mode={1} OK={2} WARN={3} FAIL={4}" -f $Stack, $Mode.ToUpperInvariant(), $totalOk, $totalWarnings, $totalFails) -ForegroundColor $summaryColor

if ($totalFails -gt 0) {
    exit 1
}

exit 0
