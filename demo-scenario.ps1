$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " HEXSTRIKE AI: Ejecutando Escenario Demo" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$apiKey = "ArgosSecure#2026!" # API Key por defecto configurada en el orquestador
$apiUrl = "http://localhost:8000/api/v1/analyze"

$payload = @{
    task_description = "Review the Juice Shop application in the lab-web pod and identify basic HTTP routes."
    target_namespace = "vulnerable-apps"
    allowed_tools = @("burp", "neurosploit")
    require_approval = $true
} | ConvertTo-Json

Write-Host "`n[1/2] Enviando tarea al orquestador HexStrike..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $payload -Headers @{"X-ARGOS-API-KEY" = $apiKey} -ContentType "application/json"
    
    Write-Host "`n[2/2] Análisis completado con éxito." -ForegroundColor Green
    Write-Host "`n--- RESULTADOS ESTRUCTURADOS ---" -ForegroundColor Cyan
    $response.results | ConvertTo-Json -Depth 5
    
    Write-Host "`nLas evidencias han sido guardadas en la carpeta 'evidence/analyses/'." -ForegroundColor Green
} catch {
    Write-Host "`nError al conectar con la API. Asegúrate de ejecutar ./scripts/run_api.sh primero." -ForegroundColor Red
    Write-Error $_.Exception.Message
}

Write-Host "`n==========================================" -ForegroundColor Cyan
