param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$WaitTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

$sandboxDir = Join-Path $RepoRoot 'k8s_platform/sandbox'
$targetsDir = Join-Path $RepoRoot 'k8s_platform/targets'
$legacyAppsManifest = Join-Path $RepoRoot 'infrastructure/k8s/apps/vulnerable-apps.yaml'
$networkPoliciesManifest = Join-Path $RepoRoot 'infrastructure/k8s/security/network-policies.yaml'
$tetragonBaseConfig = Join-Path $RepoRoot 'infrastructure/k8s/security/tetragon-runtime-observability.yaml'
$waitTimeout = "${WaitTimeoutSeconds}s"

function Apply-YamlDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        throw "No existe el directorio esperado: $DirectoryPath"
    }

    Write-Host "Aplicando manifests de $Label..." -ForegroundColor Cyan
    Get-ChildItem -LiteralPath $DirectoryPath -Filter *.yaml | Sort-Object Name | ForEach-Object {
        kubectl apply -f $_.FullName
    }
}

function Wait-Deployment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$Optional
    )

    Write-Host "Esperando rollout de ${Namespace}/${Name}..." -ForegroundColor Cyan
    kubectl rollout status "deployment/$Name" -n $Namespace --timeout=$waitTimeout
    if ($LASTEXITCODE -eq 0) {
        return
    }

    if ($Optional) {
        Write-Warning "${Namespace}/${Name} sigue sin quedar listo. Se mantiene como best-effort."
        return
    }

    throw "El deployment ${Namespace}/${Name} no quedó listo dentro de $waitTimeout"
}

Write-Host 'Reconciliando manifests Kubernetes del laboratorio...' -ForegroundColor Green

Apply-YamlDirectory -DirectoryPath $sandboxDir -Label 'sandbox moderno'
Apply-YamlDirectory -DirectoryPath $targetsDir -Label 'targets modernos'

Write-Host 'Aplicando capa legacy del laboratorio...' -ForegroundColor Cyan
kubectl apply -f $legacyAppsManifest

Write-Host 'Aplicando network policies compartidas...' -ForegroundColor Cyan
kubectl apply -f $networkPoliciesManifest

Write-Host 'Aplicando ConfigMap base de Tetragon...' -ForegroundColor Cyan
kubectl apply -f $tetragonBaseConfig

$requiredDeployments = @(
    @{ Namespace = 'sandbox'; Name = 'mcp-server' },
    @{ Namespace = 'sandbox'; Name = 'burp-suite' },
    @{ Namespace = 'sandbox'; Name = 'neurosploit' },
    @{ Namespace = 'targets'; Name = 'juiceshop' },
    @{ Namespace = 'targets'; Name = 'dvwa' },
    @{ Namespace = 'vulnerable-apps'; Name = 'juice-shop' },
    @{ Namespace = 'vulnerable-apps'; Name = 'dvwa' }
)

foreach ($deployment in $requiredDeployments) {
    Wait-Deployment -Namespace $deployment.Namespace -Name $deployment.Name
}

Wait-Deployment -Namespace 'vulnerable-apps' -Name 'webgoat' -Optional

Write-Host 'Reconciliación base completada.' -ForegroundColor Green
