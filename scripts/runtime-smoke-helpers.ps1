Set-StrictMode -Version Latest

function Write-SmokeBanner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host "" 
    Write-Host ("=" * 72) -ForegroundColor DarkGray
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkGray
}

function New-SmokeState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    [pscustomobject]@{
        Name      = $Name
        Mode      = $Mode
        OkCount   = 0
        WarnCount = 0
        FailCount = 0
        Failed    = $false
    }
}

function Add-SmokeResult {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'OK', 'WARN', 'FAIL')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
    }

    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $color

    switch ($Level) {
        'OK' {
            $State.OkCount += 1
        }
        'WARN' {
            $State.WarnCount += 1
        }
        'FAIL' {
            $State.FailCount += 1
            $State.Failed = $true
        }
    }
}

function Show-SmokeSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State
    )

    $summaryColor = if ($State.FailCount -gt 0) { 'Red' } elseif ($State.WarnCount -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host "" 
    Write-Host ("Resumen {0} [{1}] -> OK={2} WARN={3} FAIL={4}" -f $State.Name, $State.Mode.ToUpperInvariant(), $State.OkCount, $State.WarnCount, $State.FailCount) -ForegroundColor $summaryColor
}

function Get-DockerComposeCommand {
    if (Get-Command 'docker' -ErrorAction SilentlyContinue) {
        return @('docker', 'compose')
    }

    if (Get-Command 'docker-compose' -ErrorAction SilentlyContinue) {
        return @('docker-compose')
    }

    throw 'No se encontró Docker Compose. Instalá Docker Desktop o docker-compose antes de continuar.'
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandParts,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $commandName = $CommandParts[0]
    $commandArgs = if ($CommandParts.Length -gt 1) { $CommandParts[1..($CommandParts.Length - 1)] } else { @() }
    $output = & $commandName @commandArgs 2>&1
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output | ForEach-Object { $_.ToString() })
    }
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ComposeFile,

        [Parameter(Mandatory = $true)]
        [string[]]$ComposeArguments
    )

    $composeCommand = Get-DockerComposeCommand
    $commandParts = $composeCommand + @('--project-directory', $ProjectDirectory, '-f', $ComposeFile) + $ComposeArguments
    Invoke-ExternalCommand -CommandParts $commandParts -WorkingDirectory $ProjectDirectory
}

function Get-EnvMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1).Trim()
        $map[$key] = $value
    }

    return $map
}

function Resolve-StackPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory,

        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $PathValue))
}

function Get-CommandFailureSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Output,

        [int]$MaxLines = 6
    )

    if ($Output.Count -eq 0) {
        return 'sin salida adicional'
    }

    return ($Output | Select-Object -First $MaxLines) -join ' | '
}

function Get-DockerRunningContainerNames {
    $result = Invoke-ExternalCommand -CommandParts @('docker', 'ps', '--format', '{{.Names}}') -WorkingDirectory $PWD.Path
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{
            Success = $false
            Names   = @()
            Detail  = Get-CommandFailureSummary -Output $result.Output
        }
    }

    return [pscustomobject]@{
        Success = $true
        Names   = @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Detail  = ''
    }
}

function Get-ComposeRunningServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ComposeFile
    )

    $result = Invoke-DockerCompose -ProjectDirectory $ProjectDirectory -ComposeFile $ComposeFile -ComposeArguments @('ps', '--services', '--status', 'running')
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{
            Success  = $false
            Services = @()
            Detail   = Get-CommandFailureSummary -Output $result.Output
        }
    }

    return [pscustomobject]@{
        Success  = $true
        Services = @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Detail   = ''
    }
}

function Test-TcpPortOpen {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port,

        [int]$TimeoutMs = 1000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }

        $client.EndConnect($asyncResult)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-UdpPortRegistered {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    if (-not (Get-Command 'Get-NetUDPEndpoint' -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        return @((Get-NetUDPEndpoint -LocalPort $Port -ErrorAction Stop)).Count -gt 0
    } catch {
        return $false
    }
}

function Test-HttpEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSec = 3
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
        return [pscustomobject]@{
            Reachable = $true
            Detail    = "HTTP $([int]$response.StatusCode)"
        }
    } catch {
        $webResponse = $_.Exception.Response
        if ($null -ne $webResponse) {
            return [pscustomobject]@{
                Reachable = $true
                Detail    = "HTTP $([int]$webResponse.StatusCode)"
            }
        }

        return [pscustomobject]@{
            Reachable = $false
            Detail    = $_.Exception.Message
        }
    }
}

function Test-ComposeConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$ProjectDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ComposeFile,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    try {
        $result = Invoke-DockerCompose -ProjectDirectory $ProjectDirectory -ComposeFile $ComposeFile -ComposeArguments @('config')
        if ($result.ExitCode -eq 0) {
            Add-SmokeResult -State $State -Level 'OK' -Message "${Label}: docker compose config renderiza correctamente"
            return $true
        }

        Add-SmokeResult -State $State -Level 'FAIL' -Message "${Label}: docker compose config falló -> $(Get-CommandFailureSummary -Output $result.Output)"
        return $false
    } catch {
        Add-SmokeResult -State $State -Level 'FAIL' -Message "${Label}: no se pudo invocar Docker Compose -> $($_.Exception.Message)"
        return $false
    }
}

function Invoke-WazuhRuntimeSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [ValidateSet('Precheck', 'Auto', 'Runtime')]
        [string]$Mode = 'Auto'
    )

    $state = New-SmokeState -Name 'Wazuh runtime smoke' -Mode $Mode
    Write-SmokeBanner -Title 'Wazuh runtime smoke'

    $stackDir = Join-Path $RepoRoot 'infrastructure/wazuh'
    $composeFile = Join-Path $stackDir 'docker-compose.yml'
    $envFile = Join-Path $stackDir '.env'
    $certsDir = Join-Path $stackDir 'config/wazuh_indexer_ssl_certs'

    Add-SmokeResult -State $state -Level 'INFO' -Message "Modo ${Mode}: PRECHECK siempre corre; RUNTIME depende del modo y del estado del stack"

    if (Test-Path -LiteralPath $composeFile) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Wazuh compose presente en infrastructure/wazuh/docker-compose.yml'
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message 'Falta infrastructure/wazuh/docker-compose.yml'
        Show-SmokeSummary -State $state
        return $state
    }

    if (Test-Path -LiteralPath $envFile) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Existe infrastructure/wazuh/.env'
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message 'Falta infrastructure/wazuh/.env (copiá .env.example y completá secretos)'
    }

    $envMap = Get-EnvMap -Path $envFile
    $requiredSecretKeys = @('INDEXER_PASSWORD', 'API_PASSWORD', 'DASHBOARD_PASSWORD')
    $blankSecretKeys = @($requiredSecretKeys | Where-Object { -not $envMap.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($envMap[$_]) })
    if ($blankSecretKeys.Count -eq 0) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Las variables críticas de Wazuh en .env tienen valor'
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message "Variables críticas vacías o ausentes en infrastructure/wazuh/.env: $($blankSecretKeys -join ', ')"
    }

    $dashboardConfigRelative = if ($envMap.ContainsKey('WAZUH_DASHBOARD_CONFIG_PATH') -and -not [string]::IsNullOrWhiteSpace($envMap['WAZUH_DASHBOARD_CONFIG_PATH'])) {
        $envMap['WAZUH_DASHBOARD_CONFIG_PATH']
    } else {
        './config/wazuh_dashboard/wazuh.local.yml'
    }
    $dashboardConfigPath = Resolve-StackPath -BaseDirectory $stackDir -PathValue $dashboardConfigRelative

    if (Test-Path -LiteralPath $dashboardConfigPath) {
        Add-SmokeResult -State $state -Level 'OK' -Message "Existe wazuh.local.yml efectivo: $dashboardConfigRelative"
        $dashboardConfigContent = [System.IO.File]::ReadAllText($dashboardConfigPath)
        if ($dashboardConfigContent.Contains('__SET_WAZUH_API_PASSWORD__')) {
            Add-SmokeResult -State $state -Level 'FAIL' -Message 'wazuh.local.yml sigue con el placeholder __SET_WAZUH_API_PASSWORD__'
        } else {
            Add-SmokeResult -State $state -Level 'OK' -Message 'wazuh.local.yml no contiene placeholders pendientes'
        }
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message "Falta el archivo local de dashboard esperado: $dashboardConfigRelative"
    }

    $requiredCertFiles = @(
        'root-ca.pem',
        'admin.pem',
        'admin-key.pem',
        'wazuh.indexer.pem',
        'wazuh.indexer-key.pem',
        'wazuh.manager.pem',
        'wazuh.manager-key.pem',
        'wazuh.dashboard.pem',
        'wazuh.dashboard-key.pem'
    )
    $missingCerts = @($requiredCertFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $certsDir $_)) })
    if ($missingCerts.Count -eq 0) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Todos los certificados requeridos de Wazuh están presentes'
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message "Faltan certificados requeridos de Wazuh: $($missingCerts -join ', ')"
    }

    Test-ComposeConfig -State $state -ProjectDirectory $stackDir -ComposeFile $composeFile -Label 'Wazuh' | Out-Null

    if ($Mode -eq 'Precheck') {
        Add-SmokeResult -State $state -Level 'INFO' -Message 'Modo Precheck: se omiten validaciones runtime aunque haya contenedores levantados'
        Show-SmokeSummary -State $state
        return $state
    }

    $runningServices = Get-ComposeRunningServices -ProjectDirectory $stackDir -ComposeFile $composeFile
    if (-not $runningServices.Success) {
        $level = if ($Mode -eq 'Runtime') { 'FAIL' } else { 'WARN' }
        Add-SmokeResult -State $state -Level $level -Message "No se pudo consultar el estado runtime de Wazuh: $($runningServices.Detail)"
        Show-SmokeSummary -State $state
        return $state
    }

    if ($runningServices.Services.Count -eq 0) {
        $level = if ($Mode -eq 'Runtime') { 'FAIL' } else { 'WARN' }
        Add-SmokeResult -State $state -Level $level -Message 'No se detectó el stack de Wazuh levantado; se omiten checks runtime'
        Show-SmokeSummary -State $state
        return $state
    }

    Add-SmokeResult -State $state -Level 'OK' -Message "Servicios Wazuh activos detectados: $($runningServices.Services -join ', ')"

    $expectedServices = @('wazuh.indexer', 'wazuh.manager', 'wazuh.dashboard')
    $missingServices = @($expectedServices | Where-Object { $_ -notin $runningServices.Services })
    if ($missingServices.Count -eq 0) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Todos los servicios esperados de Wazuh figuran como running'
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message "Servicios esperados no running en Wazuh: $($missingServices -join ', ')"
    }

    $runningContainers = Get-DockerRunningContainerNames
    if (-not $runningContainers.Success) {
        Add-SmokeResult -State $state -Level 'WARN' -Message "No se pudo listar docker ps para validar nombres de contenedor: $($runningContainers.Detail)"
    } else {
        $expectedContainers = @('wazuh.indexer', 'wazuh.manager', 'wazuh.dashboard')
        $missingContainers = @($expectedContainers | Where-Object { $_ -notin $runningContainers.Names })
        if ($missingContainers.Count -eq 0) {
            Add-SmokeResult -State $state -Level 'OK' -Message 'Los contenedores esperados de Wazuh existen con los nombres previstos'
        } else {
            Add-SmokeResult -State $state -Level 'FAIL' -Message "Contenedores Wazuh no detectados en docker ps: $($missingContainers -join ', ')"
        }
    }

    foreach ($requiredPort in @(8444, 55000)) {
        if (Test-TcpPortOpen -Port $requiredPort) {
            Add-SmokeResult -State $state -Level 'OK' -Message "Puerto local Wazuh $requiredPort responde en loopback"
        } else {
            Add-SmokeResult -State $state -Level 'FAIL' -Message "Puerto local Wazuh $requiredPort no responde en loopback"
        }
    }

    if (Test-TcpPortOpen -Port 9200) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Puerto opcional Wazuh 9200 responde en loopback'
    } else {
        Add-SmokeResult -State $state -Level 'WARN' -Message 'Puerto opcional Wazuh 9200 no respondió en loopback'
    }

    Show-SmokeSummary -State $state
    return $state
}

function Invoke-CalderaRuntimeSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [ValidateSet('Precheck', 'Auto', 'Runtime')]
        [string]$Mode = 'Auto'
    )

    $state = New-SmokeState -Name 'CALDERA runtime smoke' -Mode $Mode
    Write-SmokeBanner -Title 'CALDERA runtime smoke'

    $stackDir = Join-Path $RepoRoot 'offensive/caldera'
    $composeFile = Join-Path $stackDir 'docker-compose.yml'
    $envFile = Join-Path $stackDir '.env'

    Add-SmokeResult -State $state -Level 'INFO' -Message "Modo ${Mode}: PRECHECK valida archivos + compose; RUNTIME valida contenedor/puertos si corresponde"

    if (Test-Path -LiteralPath $composeFile) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'CALDERA compose presente en offensive/caldera/docker-compose.yml'
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message 'Falta offensive/caldera/docker-compose.yml'
        Show-SmokeSummary -State $state
        return $state
    }

    if (Test-Path -LiteralPath $envFile) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Existe offensive/caldera/.env para overrides locales'
    } else {
        Add-SmokeResult -State $state -Level 'WARN' -Message 'No existe offensive/caldera/.env; se usarán defaults del compose (esto es válido)'
    }

    Test-ComposeConfig -State $state -ProjectDirectory $stackDir -ComposeFile $composeFile -Label 'CALDERA' | Out-Null

    if ($Mode -eq 'Precheck') {
        Add-SmokeResult -State $state -Level 'INFO' -Message 'Modo Precheck: se omiten validaciones runtime aunque haya contenedores levantados'
        Show-SmokeSummary -State $state
        return $state
    }

    $runningServices = Get-ComposeRunningServices -ProjectDirectory $stackDir -ComposeFile $composeFile
    if (-not $runningServices.Success) {
        $level = if ($Mode -eq 'Runtime') { 'FAIL' } else { 'WARN' }
        Add-SmokeResult -State $state -Level $level -Message "No se pudo consultar el estado runtime de CALDERA: $($runningServices.Detail)"
        Show-SmokeSummary -State $state
        return $state
    }

    if ($runningServices.Services.Count -eq 0) {
        $level = if ($Mode -eq 'Runtime') { 'FAIL' } else { 'WARN' }
        Add-SmokeResult -State $state -Level $level -Message 'No se detectó el stack de CALDERA levantado; se omiten checks runtime'
        Show-SmokeSummary -State $state
        return $state
    }

    Add-SmokeResult -State $state -Level 'OK' -Message "Servicios CALDERA activos detectados: $($runningServices.Services -join ', ')"

    if ('caldera' -in $runningServices.Services) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'El servicio esperado de CALDERA figura como running'
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message 'El servicio esperado de CALDERA no figura como running'
    }

    $runningContainers = Get-DockerRunningContainerNames
    if (-not $runningContainers.Success) {
        Add-SmokeResult -State $state -Level 'WARN' -Message "No se pudo listar docker ps para validar el contenedor de CALDERA: $($runningContainers.Detail)"
    } else {
        if ('caldera_server' -in $runningContainers.Names) {
            Add-SmokeResult -State $state -Level 'OK' -Message 'El contenedor esperado de CALDERA existe: caldera_server'
        } else {
            Add-SmokeResult -State $state -Level 'FAIL' -Message 'No se detectó el contenedor esperado caldera_server en docker ps'
        }
    }

    if (Test-TcpPortOpen -Port 8889) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Puerto local CALDERA 8889 responde en loopback'
        $endpointResult = Test-HttpEndpoint -Url 'http://127.0.0.1:8889'
        if ($endpointResult.Reachable) {
            Add-SmokeResult -State $state -Level 'OK' -Message "Endpoint base de CALDERA en 8889 respondió: $($endpointResult.Detail)"
        } else {
            Add-SmokeResult -State $state -Level 'WARN' -Message "Puerto 8889 abre pero el endpoint HTTP no respondió como se esperaba: $($endpointResult.Detail)"
        }
    } else {
        Add-SmokeResult -State $state -Level 'FAIL' -Message 'Puerto local CALDERA 8889 no responde en loopback'
    }

    foreach ($optionalTcpPort in @(8443, 7010, 7012, 8853)) {
        if (Test-TcpPortOpen -Port $optionalTcpPort) {
            Add-SmokeResult -State $state -Level 'OK' -Message "Puerto opcional CALDERA $optionalTcpPort responde en loopback"
        } else {
            Add-SmokeResult -State $state -Level 'WARN' -Message "Puerto opcional CALDERA $optionalTcpPort no responde en loopback"
        }
    }

    $udp7011 = Test-UdpPortRegistered -Port 7011
    if ($null -eq $udp7011) {
        Add-SmokeResult -State $state -Level 'WARN' -Message 'No se pudo verificar UDP 7011 localmente porque Get-NetUDPEndpoint no está disponible'
    } elseif ($udp7011) {
        Add-SmokeResult -State $state -Level 'OK' -Message 'Puerto opcional CALDERA 7011/udp figura registrado localmente'
    } else {
        Add-SmokeResult -State $state -Level 'WARN' -Message 'Puerto opcional CALDERA 7011/udp no figura registrado localmente'
    }

    Show-SmokeSummary -State $state
    return $state
}
