$ErrorActionPreference = "Stop"

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
    kind create cluster --name $clusterName --config infrastructure/k8s/kind-config.yaml
}

# 3. Cambiar contexto
Write-Host "Configurando contexto de kubectl..." -ForegroundColor Cyan
kubectl cluster-info --context kind-$clusterName

# 4. Ingress
Write-Host "Desplegando NGINX Ingress Controller..." -ForegroundColor Cyan
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
Write-Host "Esperando a que el Ingress Controller esté listo..." -ForegroundColor Cyan
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

# 5. Apps Vulnerables
Write-Host "Desplegando aplicaciones vulnerables (Juice Shop, WebGoat)..." -ForegroundColor Cyan
kubectl apply -f infrastructure/k8s/apps/vulnerable-apps.yaml

# 6. Herramientas de Seguridad (Fase 2)
if ($helmInstalled) {
    Write-Host "Helm detectado. Desplegando herramientas de seguridad..." -ForegroundColor Cyan
    
    # Kubescape
    Write-Host "Instalando Kubescape Operator..." -ForegroundColor Cyan
    helm repo add kubescape https://kubescape.github.io/helm-charts/
    helm repo update
    helm upgrade --install kubescape kubescape/kubescape-operator -n kubescape --create-namespace -f infrastructure/k8s/security/kubescape-values.yaml
    
    # Falco
    Write-Host "Instalando Falco..." -ForegroundColor Cyan
    helm repo add falcosecurity https://falcosecurity.github.io/charts
    helm repo update
    helm upgrade --install falco falcosecurity/falco -n falco --create-namespace -f infrastructure/k8s/security/falco-values.yaml
} else {
    Write-Host "Helm no está instalado. Omitiendo despliegue automático de Kubescape y Falco." -ForegroundColor Yellow
}

Write-Host "Despliegue del laboratorio base completado." -ForegroundColor Green
Write-Host "Para Wazuh, ejecuta: cd infrastructure/wazuh && docker-compose up -d" -ForegroundColor Green
