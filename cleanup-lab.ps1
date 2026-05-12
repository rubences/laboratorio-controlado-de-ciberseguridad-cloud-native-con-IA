$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " ARGOS: Desmantelando el laboratorio" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Eliminar clúster de Kubernetes
if (Get-Command kind -ErrorAction SilentlyContinue) {
    Write-Host "`n[1/3] Eliminando clúster Kind..." -ForegroundColor Yellow
    kind delete cluster --name argos-lab
}

# 2. Detener servicios de infraestructura (Wazuh)
$wazuhDir = "infrastructure/wazuh"
if (Test-Path $wazuhDir) {
    Write-Host "`n[2/3] Deteniendo infraestructura Wazuh y limpiando volúmenes..." -ForegroundColor Yellow
    Push-Location $wazuhDir
    docker compose down -v
    Pop-Location
}

# 3. Detener servicios ofensivos (Caldera)
$calderaDir = "offensive/caldera"
if (Test-Path $calderaDir) {
    Write-Host "`n[3/3] Deteniendo Caldera y limpiando volúmenes..." -ForegroundColor Yellow
    Push-Location $calderaDir
    docker compose down -v
    Pop-Location
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host " Laboratorio desmantelado correctamente." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
