param(
    [switch]$RemoveCerts,
    [switch]$RemoveVolumes
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$wazuhDir = Join-Path $repoRoot "infrastructure/wazuh"
$composeFile = Join-Path $wazuhDir "docker-compose.yml"
$certsDir = Join-Path $wazuhDir "config/wazuh_indexer_ssl_certs"

function Get-DockerComposeCommand {
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        return "docker"
    }

    if (Get-Command "docker-compose" -ErrorAction SilentlyContinue) {
        return "docker-compose"
    }

    throw "No se encontró Docker Compose. Instalá Docker Desktop o docker-compose antes de continuar."
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $composeCommand = Get-DockerComposeCommand
    if ($composeCommand -eq "docker") {
        & docker compose @Arguments
        return
    }

    & docker-compose @Arguments
}

if (-not (Test-Path -LiteralPath $wazuhDir)) {
    throw "No existe el directorio esperado de Wazuh: $wazuhDir"
}

if (-not (Test-Path -LiteralPath $composeFile)) {
    throw "No existe el compose principal esperado: $composeFile"
}

$downArgs = @(
    "--project-directory", $wazuhDir,
    "-f", $composeFile,
    "down"
)

if ($RemoveVolumes) {
    $downArgs += "--volumes"
}

Write-Host "Deteniendo stack local de Wazuh..." -ForegroundColor Cyan
Invoke-DockerCompose -Arguments $downArgs

if ($RemoveCerts) {
    if (-not (Test-Path -LiteralPath $certsDir)) {
        throw "No existe el directorio esperado de certificados: $certsDir"
    }

    Write-Host "Eliminando certificados locales de Wazuh..." -ForegroundColor Yellow
    Get-ChildItem -LiteralPath $certsDir -File | Where-Object { $_.Name -notin @("README.md", ".gitkeep") } | Remove-Item -Force
}

Write-Host "Reset operativo de Wazuh completado." -ForegroundColor Green
if ($RemoveVolumes) {
    Write-Host " - Volúmenes del compose eliminados." -ForegroundColor Green
}
if ($RemoveCerts) {
    Write-Host " - Certificados locales eliminados. Ejecutá scripts/bootstrap-wazuh-tls.ps1 para regenerarlos." -ForegroundColor Green
}
