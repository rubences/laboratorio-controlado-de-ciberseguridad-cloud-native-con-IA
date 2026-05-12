$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " ARGOS QA: Ejecutando validación de código" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$targetDir = "ai-orchestrator"

if (-not (Test-Path $targetDir)) {
    Write-Host "Directorio $targetDir no encontrado." -ForegroundColor Red
    exit 1
}

Push-Location $targetDir

Write-Host "`n[1/3] Comprobando dependencias (ruff, bandit, mypy)..." -ForegroundColor Yellow
$missing = $false
foreach ($tool in @("ruff", "bandit", "mypy")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "Falta $tool. Instálalo con: pip install $tool" -ForegroundColor Red
        $missing = $true
    }
}

if ($missing) {
    Write-Host "`nPor favor, instala las herramientas de QA antes de ejecutar el análisis." -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "`n[2/3] Ejecutando análisis estático (Ruff Linter & Formatter)..." -ForegroundColor Yellow
try {
    ruff check .
    Write-Host "Linter Ruff: PASSED" -ForegroundColor Green
} catch {
    Write-Host "Linter Ruff: FAILED" -ForegroundColor Red
}

Write-Host "`n[3/3] Ejecutando análisis SAST de seguridad (Bandit)..." -ForegroundColor Yellow
try {
    python -m bandit -r ./app -c pyproject.toml --quiet
    Write-Host "SAST Bandit: PASSED" -ForegroundColor Green
} catch {
    Write-Host "SAST Bandit: FAILED. Revisa las vulnerabilidades de Python detectadas." -ForegroundColor Red
}

Write-Host "`n[4/5] Ejecutando chequeo de tipos estático (MyPy)..." -ForegroundColor Yellow
try {
    mypy . --ignore-missing-imports
    Write-Host "MyPy: PASSED" -ForegroundColor Green
} catch {
    Write-Host "MyPy: FAILED. Revisa los errores de tipado." -ForegroundColor Red
}

Pop-Location

Write-Host "`n[5/5] Ejecutando pruebas de seguridad dinámica (Promptfoo)..." -ForegroundColor Yellow
if (Get-Command npx -ErrorAction SilentlyContinue) {
    try {
        npx promptfoo test --config ai-security-testing/promptfoo.yaml
        Write-Host "Promptfoo: PASSED" -ForegroundColor Green
    } catch {
        Write-Host "Promptfoo: FAILED. Revisa las violaciones de política detectadas." -ForegroundColor Red
    }
} else {
    Write-Host "npx/node no encontrado. Saltando validación de Promptfoo." -ForegroundColor Gray
}

Pop-Location
Write-Host "`nValidación completada." -ForegroundColor Cyan
