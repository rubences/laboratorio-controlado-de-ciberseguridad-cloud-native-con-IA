Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'runtime-smoke-helpers.ps1')

function Get-K8sSmokeManifestExpectations {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    return @(
        [pscustomobject]@{ Label = 'Kind config'; Path = Join-Path $RepoRoot 'infrastructure/k8s/kind-config.yaml' },
        [pscustomobject]@{ Label = 'Legacy vulnerable apps manifest'; Path = Join-Path $RepoRoot 'infrastructure/k8s/apps/vulnerable-apps.yaml' },
        [pscustomobject]@{ Label = 'Network policies manifest'; Path = Join-Path $RepoRoot 'infrastructure/k8s/security/network-policies.yaml' },
        [pscustomobject]@{ Label = 'Tetragon base manifest'; Path = Join-Path $RepoRoot 'infrastructure/k8s/security/tetragon-runtime-observability.yaml' },
        [pscustomobject]@{ Label = 'Kubescape values'; Path = Join-Path $RepoRoot 'infrastructure/k8s/security/kubescape-values.yaml' },
        [pscustomobject]@{ Label = 'Falco values'; Path = Join-Path $RepoRoot 'infrastructure/k8s/security/falco-values.yaml' },
        [pscustomobject]@{ Label = 'Tetragon values'; Path = Join-Path $RepoRoot 'infrastructure/k8s/security/tetragon-values.yaml' },
        [pscustomobject]@{ Label = 'Sandbox namespace manifest'; Path = Join-Path $RepoRoot 'k8s_platform/sandbox/namespace.yaml' },
        [pscustomobject]@{ Label = 'Sandbox MCP manifest'; Path = Join-Path $RepoRoot 'k8s_platform/sandbox/mcp-server.yaml' },
        [pscustomobject]@{ Label = 'Sandbox Burp manifest'; Path = Join-Path $RepoRoot 'k8s_platform/sandbox/burp-suite.yaml' },
        [pscustomobject]@{ Label = 'Sandbox NeuroSploit manifest'; Path = Join-Path $RepoRoot 'k8s_platform/sandbox/neurosploit.yaml' },
        [pscustomobject]@{ Label = 'Targets namespace manifest'; Path = Join-Path $RepoRoot 'k8s_platform/targets/namespace.yaml' },
        [pscustomobject]@{ Label = 'Targets Juice Shop manifest'; Path = Join-Path $RepoRoot 'k8s_platform/targets/juiceshop.yaml' },
        [pscustomobject]@{ Label = 'Targets DVWA manifest'; Path = Join-Path $RepoRoot 'k8s_platform/targets/dvwa.yaml' }
    )
}

function Invoke-NativeCommandSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandParts,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $CommandParts[0]
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $escapedArguments = @()
    foreach ($argument in $CommandParts[1..($CommandParts.Length - 1)]) {
        $safeArgument = $argument.Replace('"', '\"')
        if ($safeArgument -match '\s' -or $safeArgument -match '"') {
            $escapedArguments += '"' + $safeArgument + '"'
        } else {
            $escapedArguments += $safeArgument
        }
    }
    $startInfo.Arguments = $escapedArguments -join ' '

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        $lines += @($stdout -split "`r?`n" | Where-Object { $_ -ne '' })
    }

    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        $lines += @($stderr -split "`r?`n" | Where-Object { $_ -ne '' })
    }

    return [pscustomobject]@{
        ExitCode = [int]$process.ExitCode
        Output   = $lines
    }
}

function Invoke-KubectlCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    return Invoke-NativeCommandSafe -CommandParts (@('kubectl') + $Arguments) -WorkingDirectory $WorkingDirectory
}

function Invoke-HelmCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    return Invoke-NativeCommandSafe -CommandParts (@('helm') + $Arguments) -WorkingDirectory $WorkingDirectory
}

function ConvertFrom-CommandJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Output
    )

    $jsonText = ($Output -join [Environment]::NewLine).Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        return $null
    }

    return $jsonText | ConvertFrom-Json
}

function Get-OptionalIntProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [int]$DefaultValue = 0
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }

    return [int]$property.Value
}

function Test-K8sPrecheckArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    foreach ($expectation in (Get-K8sSmokeManifestExpectations -RepoRoot $RepoRoot)) {
        if (Test-Path -LiteralPath $expectation.Path) {
            Add-SmokeResult -State $State -Level 'OK' -Message "$($expectation.Label): presente en $($expectation.Path.Replace($RepoRoot + [System.IO.Path]::DirectorySeparatorChar, ''))"
        } else {
            Add-SmokeResult -State $State -Level 'FAIL' -Message "$($expectation.Label): falta $($expectation.Path)"
        }
    }

    $networkPoliciesPath = Join-Path $RepoRoot 'infrastructure/k8s/security/network-policies.yaml'
    if (Test-Path -LiteralPath $networkPoliciesPath) {
        $networkPoliciesContent = [System.IO.File]::ReadAllText($networkPoliciesPath)
        $expectedPolicyNames = @(
            'default-deny-all',
            'allow-web-ingress',
            'allow-dns-egress',
            'allow-sandbox-and-ingress-to-targets',
            'allow-sandbox-internal-ingress',
            'allow-egress-to-targets-and-dns'
        )

        foreach ($policyName in $expectedPolicyNames) {
            if ($networkPoliciesContent.Contains("name: $policyName")) {
                Add-SmokeResult -State $State -Level 'OK' -Message "Network policy declarada en manifest: $policyName"
            } else {
                Add-SmokeResult -State $State -Level 'FAIL' -Message "No aparece la network policy esperada en el manifest: $policyName"
            }
        }
    }

    $tetragonManifestPath = Join-Path $RepoRoot 'infrastructure/k8s/security/tetragon-runtime-observability.yaml'
    if (Test-Path -LiteralPath $tetragonManifestPath) {
        $tetragonManifestContent = [System.IO.File]::ReadAllText($tetragonManifestPath)
        if ($tetragonManifestContent.Contains('name: tetragon-lab-profile')) {
            Add-SmokeResult -State $State -Level 'OK' -Message 'El manifest base de Tetragon declara el ConfigMap tetragon-lab-profile'
        } else {
            Add-SmokeResult -State $State -Level 'FAIL' -Message 'El manifest base de Tetragon NO declara tetragon-lab-profile'
        }

        if ($tetragonManifestContent.Contains('observed_namespaces: "sandbox,targets,vulnerable-apps"')) {
            Add-SmokeResult -State $State -Level 'OK' -Message 'El ConfigMap base de Tetragon documenta sandbox, targets y vulnerable-apps'
        } else {
            Add-SmokeResult -State $State -Level 'WARN' -Message 'El ConfigMap base de Tetragon no documenta explícitamente los namespaces observados esperados'
        }
    }
}

function Get-K8sRuntimeContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedKindClusterName
    )

    $context = [ordered]@{
        KubectlAvailable = $false
        CurrentContext = ''
        CurrentContextOk = $false
        ClusterReachable = $false
        Detail = ''
        KindAvailable = $false
        KindClusterExists = $false
        KindClusterDetail = ''
    }

    if (-not (Get-Command 'kubectl' -ErrorAction SilentlyContinue)) {
        $context.Detail = 'kubectl no está instalado o no está en PATH'
        return [pscustomobject]$context
    }

    $context.KubectlAvailable = $true

    $currentContextResult = Invoke-KubectlCommand -Arguments @('config', 'current-context') -WorkingDirectory $RepoRoot
    if ($currentContextResult.ExitCode -eq 0) {
        $context.CurrentContext = ($currentContextResult.Output -join ' ').Trim()
        $context.CurrentContextOk = -not [string]::IsNullOrWhiteSpace($context.CurrentContext)
    } else {
        $context.Detail = Get-CommandFailureSummary -Output $currentContextResult.Output
    }

    if ($context.CurrentContextOk) {
        $reachabilityResult = Invoke-KubectlCommand -Arguments @('get', 'ns', '--request-timeout=5s', '-o', 'name') -WorkingDirectory $RepoRoot
        if ($reachabilityResult.ExitCode -eq 0) {
            $context.ClusterReachable = $true
        } else {
            $context.Detail = Get-CommandFailureSummary -Output $reachabilityResult.Output
        }
    }

    if (Get-Command 'kind' -ErrorAction SilentlyContinue) {
        $context.KindAvailable = $true
        $kindResult = Invoke-NativeCommandSafe -CommandParts @('kind', 'get', 'clusters') -WorkingDirectory $RepoRoot
        if ($kindResult.ExitCode -eq 0) {
            $clusters = @($kindResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $context.KindClusterExists = $clusters -contains $ExpectedKindClusterName
            $context.KindClusterDetail = if ($clusters.Count -gt 0) { $clusters -join ', ' } else { 'sin clusters Kind reportados' }
        } else {
            $context.KindClusterDetail = Get-CommandFailureSummary -Output $kindResult.Output
        }
    }

    return [pscustomobject]$context
}

function Test-K8sNamespaceExists {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )

    $result = Invoke-KubectlCommand -Arguments @('get', 'namespace', $Namespace, '--request-timeout=5s', '-o', 'name') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -eq 0) {
        Add-SmokeResult -State $State -Level 'OK' -Message "Namespace presente: $Namespace"
    } else {
        Add-SmokeResult -State $State -Level 'FAIL' -Message "Namespace ausente o inaccesible: $Namespace -> $(Get-CommandFailureSummary -Output $result.Output)"
    }
}

function Test-K8sDeploymentReadiness {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$Deployment,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [ValidateSet('FAIL', 'WARN')]
        [string]$FailureLevel = 'FAIL'
    )

    $result = Invoke-KubectlCommand -Arguments @('get', 'deployment', $Deployment, '-n', $Namespace, '-o', 'json', '--request-timeout=5s') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -ne 0) {
        Add-SmokeResult -State $State -Level $FailureLevel -Message "${Label}: deployment ausente o inaccesible -> $(Get-CommandFailureSummary -Output $result.Output)"
        return
    }

    try {
        $deploymentInfo = ConvertFrom-CommandJson -Output $result.Output
        $desired = Get-OptionalIntProperty -Object $deploymentInfo.spec -PropertyName 'replicas' -DefaultValue 1
        $ready = Get-OptionalIntProperty -Object $deploymentInfo.status -PropertyName 'readyReplicas' -DefaultValue 0
        $available = Get-OptionalIntProperty -Object $deploymentInfo.status -PropertyName 'availableReplicas' -DefaultValue 0

        if ($desired -gt 0 -and $ready -ge $desired -and $available -ge $desired) {
            Add-SmokeResult -State $State -Level 'OK' -Message "${Label}: deployment listo ($ready/$desired ready, $available/$desired available)"
        } else {
            Add-SmokeResult -State $State -Level $FailureLevel -Message "${Label}: deployment NO listo ($ready/$desired ready, $available/$desired available)"
        }
    } catch {
        Add-SmokeResult -State $State -Level $FailureLevel -Message "${Label}: no se pudo parsear el estado del deployment -> $($_.Exception.Message)"
    }
}

function Test-K8sConfigMapExists {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$ConfigMapName
    )

    $result = Invoke-KubectlCommand -Arguments @('get', 'configmap', $ConfigMapName, '-n', $Namespace, '--request-timeout=5s', '-o', 'name') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -eq 0) {
        Add-SmokeResult -State $State -Level 'OK' -Message "ConfigMap presente: ${Namespace}/${ConfigMapName}"
    } else {
        Add-SmokeResult -State $State -Level 'FAIL' -Message "ConfigMap ausente o inaccesible: ${Namespace}/${ConfigMapName} -> $(Get-CommandFailureSummary -Output $result.Output)"
    }
}

function Test-K8sNetworkPolicyExists {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )

    $result = Invoke-KubectlCommand -Arguments @('get', 'networkpolicy', $PolicyName, '-n', $Namespace, '--request-timeout=5s', '-o', 'name') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -eq 0) {
        Add-SmokeResult -State $State -Level 'OK' -Message "NetworkPolicy presente: ${Namespace}/${PolicyName}"
    } else {
        Add-SmokeResult -State $State -Level 'FAIL' -Message "NetworkPolicy ausente o inaccesible: ${Namespace}/${PolicyName} -> $(Get-CommandFailureSummary -Output $result.Output)"
    }
}

function Test-K8sHelmReleases {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    if (-not (Get-Command 'helm' -ErrorAction SilentlyContinue)) {
        Add-SmokeResult -State $State -Level 'WARN' -Message 'Helm no está instalado. Se omite chequeo de releases kubescape/falco/tetragon.'
        return
    }

    Add-SmokeResult -State $State -Level 'OK' -Message 'Helm está disponible para inspeccionar releases del laboratorio'

    $result = Invoke-HelmCommand -Arguments @('list', '-A', '-o', 'json') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -ne 0) {
        Add-SmokeResult -State $State -Level 'WARN' -Message "Helm list -A falló; no se pudo inspeccionar releases -> $(Get-CommandFailureSummary -Output $result.Output)"
        return
    }

    try {
        $parsedReleases = ConvertFrom-CommandJson -Output $result.Output
        $releases = if ($null -eq $parsedReleases) { @() } elseif ($parsedReleases -is [System.Array]) { $parsedReleases } else { @($parsedReleases) }
        $expectedReleases = @('kubescape', 'falco', 'tetragon')

        foreach ($releaseName in $expectedReleases) {
            $releaseMatches = @($releases | Where-Object { $_.name -eq $releaseName })
            $release = if ($releaseMatches.Count -gt 0) { $releaseMatches[0] } else { $null }
            if ($null -eq $release) {
                Add-SmokeResult -State $State -Level 'WARN' -Message "Release Helm no encontrada: $releaseName"
                continue
            }

            $status = if ($release.status) { $release.status } else { 'unknown' }
            if ($status -eq 'deployed') {
                Add-SmokeResult -State $State -Level 'OK' -Message "Release Helm OK: $releaseName (namespace=$($release.namespace), status=$status)"
            } else {
                Add-SmokeResult -State $State -Level 'WARN' -Message "Release Helm presente pero no desplegada estable: $releaseName (namespace=$($release.namespace), status=$status)"
            }
        }
    } catch {
        Add-SmokeResult -State $State -Level 'WARN' -Message "No se pudo parsear helm list -A -o json -> $($_.Exception.Message)"
    }
}

function Invoke-K8sRuntimeSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [ValidateSet('Precheck', 'Auto', 'Runtime')]
        [string]$Mode = 'Auto',

        [string]$ExpectedKindClusterName = 'argos-lab'
    )

    $state = New-SmokeState -Name 'Kubernetes runtime smoke' -Mode $Mode
    Write-SmokeBanner -Title 'Kubernetes runtime smoke'

    Add-SmokeResult -State $state -Level 'INFO' -Message 'Modo PRECHECK valida herramientas/manifests; AUTO agrega runtime si detecta contexto; RUNTIME exige cluster accesible.'

    Test-K8sPrecheckArtifacts -State $state -RepoRoot $RepoRoot

    if (-not (Get-Command 'kubectl' -ErrorAction SilentlyContinue)) {
        Add-SmokeResult -State $state -Level 'FAIL' -Message 'kubectl no está instalado. Sin kubectl no hay smoke checks de Kubernetes útiles.'
        Show-SmokeSummary -State $state
        return $state
    }

    Add-SmokeResult -State $state -Level 'OK' -Message 'kubectl está disponible en PATH'

    $runtimeContext = Get-K8sRuntimeContext -RepoRoot $RepoRoot -ExpectedKindClusterName $ExpectedKindClusterName

    if ($runtimeContext.CurrentContextOk) {
        Add-SmokeResult -State $state -Level 'OK' -Message "kubectl current-context: $($runtimeContext.CurrentContext)"
    } else {
        $level = if ($Mode -eq 'Runtime') { 'FAIL' } else { 'WARN' }
        Add-SmokeResult -State $state -Level $level -Message "kubectl current-context no disponible -> $($runtimeContext.Detail)"
    }

    if ($runtimeContext.KindAvailable) {
        if ($runtimeContext.KindClusterExists) {
            Add-SmokeResult -State $state -Level 'OK' -Message "Kind reporta el cluster esperado '$ExpectedKindClusterName'"
        } else {
            Add-SmokeResult -State $state -Level 'WARN' -Message "Kind no reporta '$ExpectedKindClusterName' (clusters: $($runtimeContext.KindClusterDetail))"
        }
    } else {
        Add-SmokeResult -State $state -Level 'WARN' -Message 'Kind no está instalado. No se puede verificar localmente la existencia de argos-lab vía kind get clusters.'
    }

    if ($runtimeContext.CurrentContextOk -and $runtimeContext.CurrentContext -eq "kind-$ExpectedKindClusterName") {
        Add-SmokeResult -State $state -Level 'OK' -Message "El contexto actual coincide con el cluster Kind esperado: kind-$ExpectedKindClusterName"
    } elseif ($runtimeContext.CurrentContextOk) {
        Add-SmokeResult -State $state -Level 'WARN' -Message "El contexto actual NO es kind-${ExpectedKindClusterName}: $($runtimeContext.CurrentContext)"
    }

    if ($Mode -eq 'Precheck') {
        if ($runtimeContext.ClusterReachable) {
            Add-SmokeResult -State $state -Level 'OK' -Message 'Cluster accesible durante PRECHECK; si querés profundidad usá -Mode Runtime o -Mode Auto.'
        } else {
            Add-SmokeResult -State $state -Level 'WARN' -Message 'Cluster no accesible en PRECHECK. Esto NO rompe el smoke mientras herramientas y manifests estén bien.'
        }

        Show-SmokeSummary -State $state
        return $state
    }

    if (-not $runtimeContext.ClusterReachable) {
        $message = "No se pudo acceder al cluster con kubectl -> $($runtimeContext.Detail)"
        if ($Mode -eq 'Auto') {
            Add-SmokeResult -State $state -Level 'WARN' -Message "$message. AUTO omite runtime checks."
            Show-SmokeSummary -State $state
            return $state
        }

        Add-SmokeResult -State $state -Level 'FAIL' -Message "$message. RUNTIME exige cluster accesible."
        Show-SmokeSummary -State $state
        return $state
    }

    Add-SmokeResult -State $state -Level 'OK' -Message 'Cluster accesible: se ejecutan runtime checks de namespaces, deployments, ConfigMap, Helm y network policies'

    foreach ($namespace in @('ingress-nginx', 'sandbox', 'targets', 'vulnerable-apps', 'tetragon')) {
        Test-K8sNamespaceExists -State $state -RepoRoot $RepoRoot -Namespace $namespace
    }

    $deploymentChecks = @(
        [pscustomobject]@{ Namespace = 'ingress-nginx'; Deployment = 'ingress-nginx-controller'; Label = 'Ingress NGINX controller' },
        [pscustomobject]@{ Namespace = 'sandbox'; Deployment = 'mcp-server'; Label = 'Sandbox MCP server' },
        [pscustomobject]@{ Namespace = 'sandbox'; Deployment = 'burp-suite'; Label = 'Sandbox Burp Suite mock' },
        [pscustomobject]@{ Namespace = 'sandbox'; Deployment = 'neurosploit'; Label = 'Sandbox NeuroSploit mock' },
        [pscustomobject]@{ Namespace = 'targets'; Deployment = 'juiceshop'; Label = 'Target moderno Juice Shop' },
        [pscustomobject]@{ Namespace = 'targets'; Deployment = 'dvwa'; Label = 'Target moderno DVWA' },
        [pscustomobject]@{ Namespace = 'vulnerable-apps'; Deployment = 'juice-shop'; Label = 'Target legacy Juice Shop'; FailureLevel = 'FAIL' },
        [pscustomobject]@{ Namespace = 'vulnerable-apps'; Deployment = 'webgoat'; Label = 'Target legacy WebGoat (best-effort)'; FailureLevel = 'WARN' },
        [pscustomobject]@{ Namespace = 'vulnerable-apps'; Deployment = 'dvwa'; Label = 'Target legacy DVWA' }
    )

    foreach ($deploymentCheck in $deploymentChecks) {
        $failureLevel = if ($deploymentCheck.PSObject.Properties['FailureLevel']) { $deploymentCheck.FailureLevel } else { 'FAIL' }
        Test-K8sDeploymentReadiness -State $state -RepoRoot $RepoRoot -Namespace $deploymentCheck.Namespace -Deployment $deploymentCheck.Deployment -Label $deploymentCheck.Label -FailureLevel $failureLevel
    }

    Test-K8sConfigMapExists -State $state -RepoRoot $RepoRoot -Namespace 'tetragon' -ConfigMapName 'tetragon-lab-profile'

    $expectedPoliciesByNamespace = @{
        'vulnerable-apps' = @('default-deny-all', 'allow-web-ingress', 'allow-dns-egress')
        'targets' = @('default-deny-all', 'allow-sandbox-and-ingress-to-targets', 'allow-dns-egress')
        'sandbox' = @('default-deny-all', 'allow-sandbox-internal-ingress', 'allow-egress-to-targets-and-dns')
    }

    foreach ($namespaceName in $expectedPoliciesByNamespace.Keys) {
        foreach ($policyName in $expectedPoliciesByNamespace[$namespaceName]) {
            Test-K8sNetworkPolicyExists -State $state -RepoRoot $RepoRoot -Namespace $namespaceName -PolicyName $policyName
        }
    }

    Test-K8sHelmReleases -State $state -RepoRoot $RepoRoot

    Show-SmokeSummary -State $state
    return $state
}
