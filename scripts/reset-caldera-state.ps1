param(
    [switch]$RemoveVolumes
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$calderaDir = Join-Path $repoRoot "offensive/caldera"
$composeFile = Join-Path $calderaDir "docker-compose.yml"

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

if (-not (Test-Path -LiteralPath $calderaDir)) {
    throw "No existe el directorio esperado de CALDERA: $calderaDir"
}

if (-not (Test-Path -LiteralPath $composeFile)) {
    throw "No existe el compose principal esperado: $composeFile"
}

$downArgs = @(
    "--project-directory", $calderaDir,
    "-f", $composeFile,
    "down",
    "--remove-orphans"
)

if ($RemoveVolumes) {
    $downArgs += "--volumes"
}

Write-Host "Deteniendo stack local de CALDERA..." -ForegroundColor Cyan
Invoke-DockerCompose -Arguments $downArgs

Write-Host "Reset operativo de CALDERA completado." -ForegroundColor Green
if ($RemoveVolumes) {
    Write-Host " - Se eliminaron los volúmenes del compose, incluyendo caldera_conf y caldera_data." -ForegroundColor Green
    Write-Host " - El próximo 'up' generará un conf/local.yml nuevo dentro del volumen limpio." -ForegroundColor Green
} else {
    Write-Host " - El estado persistente se conservó. Usá -RemoveVolumes si querés rotación limpia de caldera_conf." -ForegroundColor Green
}
