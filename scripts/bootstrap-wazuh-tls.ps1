param(
    [switch]$ResetExistingCerts
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$wazuhDir = Join-Path $repoRoot "infrastructure/wazuh"
$certsDir = Join-Path $wazuhDir "config/wazuh_indexer_ssl_certs"
$generatorCompose = Join-Path $wazuhDir "generate-certs.yml"
$topologyConfig = Join-Path $wazuhDir "config/certs.yml"
$requiredArtifacts = @(
    "root-ca.pem",
    "admin.pem",
    "admin-key.pem",
    "wazuh.indexer.pem",
    "wazuh.indexer-key.pem",
    "wazuh.manager.pem",
    "wazuh.manager-key.pem",
    "wazuh.dashboard.pem",
    "wazuh.dashboard-key.pem"
)

function Get-DockerComposeCommand {
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        return @("docker", "compose")
    }

    if (Get-Command "docker-compose" -ErrorAction SilentlyContinue) {
        return @("docker-compose")
    }

    throw "No se encontró Docker Compose. Instalá Docker Desktop o docker-compose antes de continuar."
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $composeCommand = Get-DockerComposeCommand
    $commandName = $composeCommand[0]
    $baseArgs = if ($composeCommand.Length -gt 1) { $composeCommand[1..($composeCommand.Length - 1)] } else { @() }
    & $commandName @baseArgs @Arguments
}

if (-not (Test-Path -LiteralPath $wazuhDir)) {
    throw "No existe el directorio esperado de Wazuh: $wazuhDir"
}

if (-not (Test-Path -LiteralPath $certsDir)) {
    throw "No existe el directorio de certificados esperado: $certsDir"
}

if (-not (Test-Path -LiteralPath $generatorCompose)) {
    throw "No existe el compose de generación esperado: $generatorCompose"
}

if (-not (Test-Path -LiteralPath $topologyConfig)) {
    throw "No existe el archivo de topología TLS esperado: $topologyConfig"
}

if ($ResetExistingCerts) {
    Write-Host "Eliminando certificados locales existentes de Wazuh..." -ForegroundColor Yellow
    Get-ChildItem -LiteralPath $certsDir -File | Where-Object { $_.Name -notin @("README.md", ".gitkeep") } | Remove-Item -Force
}

$composeArgs = @(
    "--project-directory", $wazuhDir,
    "-f", $generatorCompose,
    "run", "--rm", "generator"
)

Write-Host "Generando certificados TLS locales de Wazuh..." -ForegroundColor Cyan
Write-Host "Topología fuente: $topologyConfig" -ForegroundColor DarkCyan
Write-Host "Directorio destino: $certsDir" -ForegroundColor DarkCyan

Invoke-DockerCompose -Arguments $composeArgs

$missingArtifacts = @($requiredArtifacts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $certsDir $_)) })
if ($missingArtifacts.Count -gt 0) {
    throw "La regeneración terminó pero faltan archivos esperados: $($missingArtifacts -join ', ')"
}

Write-Host "Bootstrap TLS de Wazuh completado. Archivos principales presentes:" -ForegroundColor Green
$requiredArtifacts | ForEach-Object { Write-Host " - $_" -ForegroundColor Green }
