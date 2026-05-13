param(
    [string]$TargetNamespace = 'targets',

    [string]$TargetAppName = 'dvwa',

    [string]$FalcoNamespace = 'falco',

    [string]$TetragonNamespace = 'tetragon',

    [string]$WazuhContainerName = 'wazuh.manager',

    [string]$EvidenceDirectory = 'evidence/runtime-detection',

    [switch]$SkipShadowRead
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$absoluteEvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDirectory))
$startedAtUtc = [DateTime]::UtcNow
$startedAtStamp = $startedAtUtc.ToString('yyyyMMddTHHmmssZ')
$startedAtRfc3339 = $startedAtUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$runDirectory = Join-Path $absoluteEvidenceRoot $startedAtStamp

function Write-Step {
    param([string]$Message)

    Write-Host "[runtime-detection] $Message" -ForegroundColor Cyan
}

function Invoke-KubectlRaw {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'kubectl'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $escapedArguments = @()
    foreach ($argument in $Arguments) {
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

    $exitCode = [int]$process.ExitCode

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "kubectl $($Arguments -join ' ') falló con exit code $exitCode -> $($lines -join ' | ')"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines    = $lines
        Text     = ($lines -join [Environment]::NewLine)
    }
}

function Invoke-KubectlJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $result = Invoke-KubectlRaw -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace($result.Text)) {
        throw "kubectl $($Arguments -join ' ') no devolvió JSON"
    }

    return $result.Text | ConvertFrom-Json
}

function Invoke-DockerRaw {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'docker'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $escapedArguments = @()
    foreach ($argument in $Arguments) {
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

    $exitCode = [int]$process.ExitCode
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "docker $($Arguments -join ' ') falló con exit code $exitCode -> $($lines -join ' | ')"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines    = $lines
        Text     = ($lines -join [Environment]::NewLine)
    }
}

function Get-SinglePodByLabel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$Selector,

        [string]$NodeName
    )

    $args = @('get', 'pods', '-n', $Namespace, '-l', $Selector, '-o', 'json')
    if (-not [string]::IsNullOrWhiteSpace($NodeName)) {
        $args += @('--field-selector', "spec.nodeName=$NodeName")
    }

    $pods = Invoke-KubectlJson -Arguments $args
    $items = @($pods.items)
    if ($items.Count -eq 0) {
        throw "No se encontraron pods en namespace '$Namespace' con selector '$Selector'"
    }

    return $items[0]
}

function Convert-ToUtcDateTime {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        return ([DateTimeOffset]::Parse($Value)).UtcDateTime
    } catch {
        return $null
    }
}

function Save-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowEmptyString()]
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

function Select-TetragonTargetLines {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [string]$TargetNamespace,

        [Parameter(Mandatory = $true)]
        [string]$TargetPodName
    )

    $selected = New-Object System.Collections.Generic.List[string]

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json
            $pod = $event.process_exec.process.pod
            if ($null -eq $pod) {
                continue
            }

            if ([string]$pod.namespace -eq $TargetNamespace -and [string]$pod.name -eq $TargetPodName) {
                $selected.Add($line)
            }
        } catch {
            continue
        }
    }

    return @($selected)
}

function Select-WazuhAlertLines {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [string]$TargetPodName,

        [Parameter(Mandatory = $true)]
        [datetime]$StartedAtUtc
    )

    $selected = New-Object System.Collections.Generic.List[string]
    $windowStartUtc = $StartedAtUtc.AddMinutes(-2)

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json
        } catch {
            continue
        }

        $rawLog = [string]$event.full_log
        $ruleId = if ($event.PSObject.Properties['rule']) { [string]$event.rule.id } else { '' }
        $falcoTimeValue = if ($event.PSObject.Properties['data']) { [string]$event.data.falco_time } else { '' }
        $ingestUtc = Convert-ToUtcDateTime -Value ([string]$event.timestamp)
        $falcoUtc = Convert-ToUtcDateTime -Value $falcoTimeValue
        $hasTargetPod = $rawLog -match [Regex]::Escape($TargetPodName)
        $hasFalcoSignal = $ruleId -in @('110000', '110001', '110003') -or $rawLog -match 'falcosidekick:'
        $isInWindow = ($null -ne $ingestUtc -and $ingestUtc -ge $windowStartUtc) -or ($null -ne $falcoUtc -and $falcoUtc -ge $windowStartUtc)

        if ($hasTargetPod -and $hasFalcoSignal -and $isInWindow) {
            $selected.Add($line)
        }
    }

    return @($selected)
}

function Get-WazuhCorrelation {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    foreach ($line in $Lines) {
        try {
            $event = $line | ConvertFrom-Json
        } catch {
            continue
        }

        $rule = if ($event.PSObject.Properties['rule']) { $event.rule } else { $null }
        $data = if ($event.PSObject.Properties['data']) { $event.data } else { $null }
        $decoder = if ($event.PSObject.Properties['decoder']) { $event.decoder } else { $null }
        $predecoder = if ($event.PSObject.Properties['predecoder']) { $event.predecoder } else { $null }

        return [ordered]@{
            rule_id = if ($null -ne $rule) { [string]$rule.id } else { '' }
            rule_description = if ($null -ne $rule) { [string]$rule.description } else { '' }
            rule_level = if ($null -ne $rule) { [int]$rule.level } else { 0 }
            ingest_timestamp_utc = [string]$event.timestamp
            falco_event_timestamp_utc = if ($null -ne $data) { [string]$data.falco_time } else { '' }
            decoder = if ($null -ne $decoder) { [string]$decoder.name } else { '' }
            program_name = if ($null -ne $predecoder) { [string]$predecoder.program_name } else { '' }
            location = [string]$event.location
        }
    }

    return $null
}

if (-not (Get-Command 'kubectl' -ErrorAction SilentlyContinue)) {
    throw 'kubectl no está instalado o no está en PATH.'
}

if (-not (Get-Command 'docker' -ErrorAction SilentlyContinue)) {
    throw 'docker no está instalado o no está en PATH.'
}

if (-not (Test-Path -LiteralPath $absoluteEvidenceRoot)) {
    New-Item -ItemType Directory -Path $absoluteEvidenceRoot -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $runDirectory)) {
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
}

Write-Step "Recolectando contexto del cluster"
$kubectlContext = (Invoke-KubectlRaw -Arguments @('config', 'current-context')).Text.Trim()
$targetPod = Get-SinglePodByLabel -Namespace $TargetNamespace -Selector "app.kubernetes.io/name=$TargetAppName"
$targetPodName = [string]$targetPod.metadata.name
$targetNodeName = [string]$targetPod.spec.nodeName
$falcoPod = Get-SinglePodByLabel -Namespace $FalcoNamespace -Selector 'app.kubernetes.io/name=falco' -NodeName $targetNodeName
$tetragonPod = Get-SinglePodByLabel -Namespace $TetragonNamespace -Selector 'app.kubernetes.io/name=tetragon' -NodeName $targetNodeName
$falcoPodName = [string]$falcoPod.metadata.name
$tetragonPodName = [string]$tetragonPod.metadata.name

$summary = [ordered]@{
    started_at_utc = $startedAtRfc3339
    kubectl_context = $kubectlContext
    target = [ordered]@{
        namespace = $TargetNamespace
        app = $TargetAppName
        pod = $targetPodName
        node = $targetNodeName
    }
    sensors = [ordered]@{
        falco_pod = $falcoPodName
        tetragon_pod = $tetragonPodName
    }
    actions = @()
    evidence = [ordered]@{}
    correlation = [ordered]@{
        rule_id = ''
        rule_description = ''
        rule_level = 0
        ingest_timestamp_utc = ''
        falco_event_timestamp_utc = ''
        decoder = ''
        program_name = ''
        location = ''
    }
    limitations = @()
}

Write-Step "Ejecutando comando benigno de proceso dentro de $targetPodName"
$processCommand = 'id && whoami && cat /etc/os-release | sed -n 1,2p'
$processResult = Invoke-KubectlRaw -Arguments @('exec', '-n', $TargetNamespace, $targetPodName, '--', 'sh', '-c', $processCommand)
$summary.actions += [ordered]@{
    name = 'process_exec_probe'
    command = $processCommand
    exit_code = $processResult.ExitCode
}
Save-TextFile -Path (Join-Path $runDirectory 'target-process-command.txt') -Content $processResult.Text

if (-not $SkipShadowRead.IsPresent) {
    Write-Step "Ejecutando lectura controlada de /etc/shadow sin exponer contenido"
    $shadowCommand = 'cat /etc/shadow > /dev/null'
    $shadowResult = Invoke-KubectlRaw -Arguments @('exec', '-n', $TargetNamespace, $targetPodName, '--', 'sh', '-c', $shadowCommand) -AllowFailure
    $summary.actions += [ordered]@{
        name = 'falco_sensitive_file_probe'
        command = $shadowCommand
        exit_code = $shadowResult.ExitCode
    }
    Save-TextFile -Path (Join-Path $runDirectory 'target-shadow-command.txt') -Content $shadowResult.Text

    if ($shadowResult.ExitCode -ne 0) {
        $summary.limitations += 'La lectura controlada de /etc/shadow falló; Falco puede no emitir alerta si el contenedor no permite ese acceso.'
    }
}

Start-Sleep -Seconds 8

Write-Step 'Recolectando evidencia de Falco'
$falcoLogs = Invoke-KubectlRaw -Arguments @('logs', '-n', $FalcoNamespace, $falcoPodName, '-c', 'falco', '--since-time', $startedAtRfc3339)
$falcoMatches = @($falcoLogs.Lines | Where-Object { $_ -match [Regex]::Escape($targetPodName) })
Save-TextFile -Path (Join-Path $runDirectory 'falco-alerts.jsonl') -Content ($falcoMatches -join [Environment]::NewLine)
$summary.evidence.falco_matches = $falcoMatches.Count

if ($falcoMatches.Count -eq 0) {
    $summary.limitations += 'Falco no emitió alertas asociadas al pod objetivo dentro de la ventana observada.'
}

Write-Step 'Recolectando evidencia de Tetragon'
$tetragonLogs = Invoke-KubectlRaw -Arguments @('logs', '-n', $TetragonNamespace, $tetragonPodName, '-c', 'export-stdout', '--since=10m') -AllowFailure
$tetragonMatches = @(Select-TetragonTargetLines -Lines $tetragonLogs.Lines -TargetNamespace $TargetNamespace -TargetPodName $targetPodName | Select-Object -Last 10)
Save-TextFile -Path (Join-Path $runDirectory 'tetragon-process-events.jsonl') -Content ($tetragonMatches -join [Environment]::NewLine)
$summary.evidence.tetragon_matches = $tetragonMatches.Count

if ($tetragonMatches.Count -eq 0) {
    $summary.limitations += 'Tetragon no devolvió eventos del pod objetivo desde el export file local del nodo.'
}

Write-Step 'Recolectando estado de Falcosidekick (best-effort)'
$falcosidekickLogs = Invoke-KubectlRaw -Arguments @('logs', '-n', $FalcoNamespace, 'deployment/falco-falcosidekick', '--tail=50') -AllowFailure
Save-TextFile -Path (Join-Path $runDirectory 'falcosidekick.log') -Content $falcosidekickLogs.Text
if ($falcosidekickLogs.Text -match 'Syslog - dial udp|i/o timeout|lookup wazuh\.local|lookup wazuh-syslog-bridge') {
    $summary.limitations += 'Falcosidekick muestra fallos de salida Syslog/Wazuh. Si el bridge DNS ya resuelve pero Wazuh no está levantado, la limitación real pasa a ser disponibilidad del destino y la evidencia confiable queda en logs locales de Falco.'
}

Write-Step 'Recolectando evidencia de Wazuh'
$wazuhAlerts = Invoke-DockerRaw -Arguments @('exec', $WazuhContainerName, 'sh', '-c', 'tail -n 500 /var/ossec/logs/alerts/alerts.json') -AllowFailure
$wazuhMatches = @(Select-WazuhAlertLines -Lines $wazuhAlerts.Lines -TargetPodName $targetPodName -StartedAtUtc $startedAtUtc)
Save-TextFile -Path (Join-Path $runDirectory 'wazuh-alerts.jsonl') -Content ($wazuhMatches -join [Environment]::NewLine)
$summary.evidence.wazuh_matches = $wazuhMatches.Count

if ($wazuhMatches.Count -eq 0) {
    $summary.limitations += 'Wazuh no generó alertas correlacionables con el pod objetivo dentro de la ventana observada.'
} else {
    $wazuhCorrelation = Get-WazuhCorrelation -Lines $wazuhMatches
    if ($null -ne $wazuhCorrelation) {
        $summary.correlation = $wazuhCorrelation
    }
}

$summary.evidence.end_to_end_demonstrated = ($falcoMatches.Count -gt 0 -and $wazuhMatches.Count -gt 0)

$summaryPath = Join-Path $runDirectory 'summary.json'
$summaryMarkdownPath = Join-Path $runDirectory 'summary.md'
$summaryJson = $summary | ConvertTo-Json -Depth 6
Save-TextFile -Path $summaryPath -Content $summaryJson

$limitationsSection = if ($summary.limitations.Count -gt 0) {
    ($summary.limitations | ForEach-Object { "- $_" }) -join [Environment]::NewLine
} else {
    '- Sin limitaciones detectadas en esta corrida.'
}

$actionsSection = ($summary.actions | ForEach-Object {
    "- $($_.name): `kubectl exec -n $TargetNamespace $targetPodName -- sh -c `"$($_.command)`"` (exit_code=$($_.exit_code))"
}) -join [Environment]::NewLine

$summaryMarkdown = @"
# Runtime detection validation

- Started at (UTC): $startedAtRfc3339
- Context: $kubectlContext
- Target pod: $targetPodName
- Target node: $targetNodeName
- Falco pod: $falcoPodName
- Tetragon pod: $tetragonPodName

## Actions executed
$actionsSection

## Evidence files
- falco-alerts.jsonl -> $($summary.evidence.falco_matches) match(es)
- tetragon-process-events.jsonl -> $($summary.evidence.tetragon_matches) match(es)
- wazuh-alerts.jsonl -> $($summary.evidence.wazuh_matches) match(es)
- target-process-command.txt
- target-shadow-command.txt
- falcosidekick.log

## End-to-end status
- Demonstrated automatically: $($summary.evidence.end_to_end_demonstrated)
- Wazuh rule: $($summary.correlation.rule_id)
- Wazuh description: $($summary.correlation.rule_description)
- Falco event time (from Wazuh payload): $($summary.correlation.falco_event_timestamp_utc)
- Wazuh ingest time: $($summary.correlation.ingest_timestamp_utc)
- Decoder/program: $($summary.correlation.decoder) / $($summary.correlation.program_name)

## Limitations
$limitationsSection
"@

Save-TextFile -Path $summaryMarkdownPath -Content $summaryMarkdown

Write-Step "Validación finalizada. Evidencia guardada en $runDirectory"
$summaryMarkdown
