param(
    [string]$ApiKey = $env:ARGOS_API_KEY,
    [string]$ApiUrl = $(if ($env:ARGOS_API_URL) { $env:ARGOS_API_URL } else { "http://localhost:8000/api/v1/scans/start" }),
    [string]$Target = "juiceshop.targets.svc.cluster.local",
    [string]$TargetNamespace = "targets"
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " HEXSTRIKE AI: Ejecutando Escenario Demo" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if (-not $ApiKey) {
    Write-Host "`nFalta la API key. Pasala con -ApiKey o definí ARGOS_API_KEY en el entorno." -ForegroundColor Red
    exit 1
}

$payload = @{
    scan_name = "demo-scaffold-scan"
    target = $Target
    target_namespace = $TargetNamespace
    allowed_tools = @("burp", "neurosploit")
    require_approval = $true
    requestor = "demo-scenario.ps1"
} | ConvertTo-Json

Write-Host "`n[1/2] Enviando tarea al orquestador HexStrike..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $payload -Headers @{"X-ARGOS-API-KEY" = $apiKey} -ContentType "application/json"
    
    Write-Host "`n[2/2] Análisis completado con éxito." -ForegroundColor Green
    Write-Host "`n--- RESULTADOS ESTRUCTURADOS ---" -ForegroundColor Cyan
    $response | ConvertTo-Json -Depth 6
    
    Write-Host "`nLas evidencias han sido guardadas en la carpeta 'evidence/scaffold/scans/'." -ForegroundColor Green
} catch {
    Write-Host "`nError al conectar con la API. Asegúrate de levantar el scaffold con 'uvicorn ai_apps.api.main:app --reload'." -ForegroundColor Red
    Write-Error $_.Exception.Message
}

Write-Host "`n==========================================" -ForegroundColor Cyan
