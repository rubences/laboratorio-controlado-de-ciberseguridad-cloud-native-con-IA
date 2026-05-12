$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$kindConfig = Join-Path $repoRoot "infrastructure/k8s/kind-config.yaml"
$legacyAppsManifest = Join-Path $repoRoot "infrastructure/k8s/apps/vulnerable-apps.yaml"
$networkPoliciesManifest = Join-Path $repoRoot "infrastructure/k8s/security/network-policies.yaml"
$kubescapeValues = Join-Path $repoRoot "infrastructure/k8s/security/kubescape-values.yaml"
$falcoValues = Join-Path $repoRoot "infrastructure/k8s/security/falco-values.yaml"
$wazuhBridgeManifest = Join-Path $repoRoot "infrastructure/k8s/security/wazuh-syslog-bridge.yaml"
$tetragonValues = Join-Path $repoRoot "infrastructure/k8s/security/tetragon-values.yaml"
$tetragonBaseConfig = Join-Path $repoRoot "infrastructure/k8s/security/tetragon-runtime-observability.yaml"
$sandboxDir = Join-Path $repoRoot "k8s_platform/sandbox"
$targetsDir = Join-Path $repoRoot "k8s_platform/targets"
$defaultIngressManifest = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.5/deploy/static/provider/kind/deploy.yaml"
$ingressManifest = if ($env:ARGOS_INGRESS_NGINX_MANIFEST) { $env:ARGOS_INGRESS_NGINX_MANIFEST } else { $defaultIngressManifest }
$ingressWaitTimeout = if ($env:ARGOS_INGRESS_WAIT_TIMEOUT) { $env:ARGOS_INGRESS_WAIT_TIMEOUT } else { "90s" }

function Resolve-ManifestTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Manifest,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if ($Manifest -match '^(http|https)://') {
        return $Manifest
    }

    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Manifest)) {
        $Manifest
    } else {
        Join-Path $repoRoot $Manifest
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "No existe el manifest configurado para ${Description}: $resolvedPath"
    }

    return $resolvedPath
}

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

function Apply-OptionalManifestIfNamespaceExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "No existe el manifest esperado para ${Label}: $ManifestPath"
    }

    kubectl get namespace $Namespace *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Omitiendo ${Label}: namespace $Namespace todavía no existe." -ForegroundColor Yellow
        return
    }

    Write-Host "Aplicando ${Label}..." -ForegroundColor Cyan
    kubectl apply -f $ManifestPath
}

Write-Host "Iniciando despliegue del Laboratorio ARGOS..." -ForegroundColor Green

# 1. Comprobar dependencias
if (-not (Get-Command "kind" -ErrorAction SilentlyContinue)) {
    Write-Host "Kind no está instalado. Por favor instálalo antes de continuar." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command "kubectl" -ErrorAction SilentlyContinue)) {
    Write-Host "kubectl no está instalado. Por favor instálalo antes de continuar." -ForegroundColor Red
    exit 1
}

$helmInstalled = [bool](Get-Command "helm" -ErrorAction SilentlyContinue)

# 2. Crear el clúster
$clusterName = "argos-lab"
$existingClusters = kind get clusters
if ($existingClusters -contains $clusterName) {
    Write-Host "El clúster $clusterName ya existe. Omitiendo creación." -ForegroundColor Yellow
} else {
    Write-Host "Creando clúster $clusterName usando Kind..." -ForegroundColor Cyan
    kind create cluster --name $clusterName --config $kindConfig
}

# 3. Cambiar contexto
Write-Host "Configurando contexto de kubectl..." -ForegroundColor Cyan
kubectl cluster-info --context kind-$clusterName

# 4. Ingress
Write-Host "Desplegando NGINX Ingress Controller..." -ForegroundColor Cyan
$resolvedIngressManifest = Resolve-ManifestTarget -Manifest $ingressManifest -Description "NGINX Ingress"
Write-Host "Usando manifest de ingress: $resolvedIngressManifest" -ForegroundColor DarkCyan
kubectl apply -f $resolvedIngressManifest
Write-Host "Esperando a que el Ingress Controller esté listo..." -ForegroundColor Cyan
Start-Sleep -Seconds 10
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=$ingressWaitTimeout

# 5. Stack moderno del scaffold
Apply-YamlDirectory -DirectoryPath $sandboxDir -Label "sandbox moderno"
Apply-YamlDirectory -DirectoryPath $targetsDir -Label "targets modernos"

# 6. Capa legacy mantenida por compatibilidad del laboratorio
Write-Host "Desplegando aplicaciones vulnerables legacy (Juice Shop, WebGoat, DVWA)..." -ForegroundColor Cyan
kubectl apply -f $legacyAppsManifest

# 7. Hardening de red compartido entre capas
Write-Host "Aplicando network policies del laboratorio..." -ForegroundColor Cyan
kubectl apply -f $networkPoliciesManifest

# 8. Tetragon base config
Write-Host "Aplicando configuración base de Tetragon..." -ForegroundColor Cyan
kubectl apply -f $tetragonBaseConfig

# 9. Herramientas de Seguridad (Fase 2)
if ($helmInstalled) {
    Write-Host "Helm detectado. Desplegando herramientas de seguridad..." -ForegroundColor Cyan
    
    # Kubescape
    Write-Host "Instalando Kubescape Operator..." -ForegroundColor Cyan
    helm repo add kubescape https://kubescape.github.io/helm-charts/
    helm repo update
    helm upgrade --install kubescape kubescape/kubescape-operator -n kubescape --create-namespace -f $kubescapeValues
    
    # Falco
    Write-Host "Instalando Falco..." -ForegroundColor Cyan
    helm repo add falcosecurity https://falcosecurity.github.io/charts
    helm repo update
    helm upgrade --install falco falcosecurity/falco -n falco --create-namespace -f $falcoValues
    Apply-OptionalManifestIfNamespaceExists -ManifestPath $wazuhBridgeManifest -Namespace 'falco' -Label 'bridge DNS/syslog Falcosidekick -> Wazuh'

    # Tetragon
    Write-Host "Instalando Tetragon para visibilidad eBPF/runtime..." -ForegroundColor Cyan
    helm repo add cilium https://helm.cilium.io/
    helm repo update
    helm upgrade --install tetragon cilium/tetragon -n tetragon --create-namespace -f $tetragonValues
} else {
    Write-Host "Helm no está instalado. Omitiendo despliegue automático de Kubescape, Falco y Tetragon." -ForegroundColor Yellow
    Apply-OptionalManifestIfNamespaceExists -ManifestPath $wazuhBridgeManifest -Namespace 'falco' -Label 'bridge DNS/syslog Falcosidekick -> Wazuh'
}

Write-Host "Despliegue del laboratorio base completado." -ForegroundColor Green
Write-Host "Falcosidekick queda apuntando al Service wazuh-syslog-bridge (ExternalName -> host.docker.internal)." -ForegroundColor Green
Write-Host "OJO: eso resuelve el bridge/DNS del cluster, pero NO levanta Wazuh ni garantiza recepción si el stack no está corriendo." -ForegroundColor Yellow
Write-Host "Para Wazuh, ejecuta: docker compose -f infrastructure/wazuh/docker-compose.yml up -d" -ForegroundColor Green
