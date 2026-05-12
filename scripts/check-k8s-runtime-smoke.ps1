param(
    [ValidateSet('Precheck', 'Auto', 'Runtime')]
    [string]$Mode = 'Auto',

    [string]$ExpectedKindClusterName = 'argos-lab'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'k8s-smoke-helpers.ps1')

$result = Invoke-K8sRuntimeSmoke -RepoRoot $repoRoot -Mode $Mode -ExpectedKindClusterName $ExpectedKindClusterName
if ($result.FailCount -gt 0) {
    exit 1
}

exit 0
