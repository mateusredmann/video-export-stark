#Requires -Version 5.1
# PreToolUse hook - bloqueia clickup_create_task_comment / clickup_update_task em
# task_ids que NAO foram aprovados pelo matcher da skill video-export-stark.
# Le <cacheDir>\video-export-task-lock.json (escrito pelo Matcher) — cacheDir =
# %USERPROFILE%\.stark-video-export (mesmo do .sh em ~/.stark-video-export/).
# Exit 0 = libera, exit 2 = bloqueia.

$ErrorActionPreference = 'Stop'
$LockPath = Join-Path $env:USERPROFILE '.stark-video-export\video-export-task-lock.json'

function Write-HookLog {
    param([string]$Message)
    try {
        $logDir = Join-Path $env:USERPROFILE '.stark-video-export\logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logFile = Join-Path $logDir ("hook-clickup-{0:yyyyMMdd}.log" -f (Get-Date))
        Add-Content -Path $logFile -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message) -Encoding utf8
    } catch { }
}

function Allow-Tool {
    param([string]$Reason)
    if ($Reason) { Write-HookLog "ALLOW: $Reason" }
    exit 0
}

function Block-Tool {
    param([string]$Reason, [string]$TaskId)
    Write-HookLog "BLOCK: $Reason"
    [Console]::Error.WriteLine("[hook validate-clickup-task] BLOQUEADO: $Reason")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("task_id da chamada: $TaskId")
    [Console]::Error.WriteLine("Lock file: $LockPath")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("Causa provavel:")
    [Console]::Error.WriteLine("  1. Matcher resolveu pra OUTRA subtask - re-rode com --dry-run pra ver evidencias.")
    [Console]::Error.WriteLine("  2. Score < 6 ou sanity_falhou - task vai pra pendencia, NAO comenta nessa subtask.")
    [Console]::Error.WriteLine("  3. Voce esta chamando ClickUp fora do fluxo da skill - apague o lock pra liberar.")
    exit 2
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow-Tool 'stdin vazio' }

    $payload = $raw | ConvertFrom-Json -ErrorAction Stop

    $toolName = $null
    if ($payload.tool_name) { $toolName = [string]$payload.tool_name }
    elseif ($payload.toolName) { $toolName = [string]$payload.toolName }

    if (-not $toolName) { Allow-Tool 'sem tool_name' }
    if ($toolName -notmatch '(?i)clickup_(create_task_comment|update_task)$') {
        Allow-Tool "tool $toolName fora do escopo deste hook"
    }

    $toolInput = $null
    if ($payload.tool_input) { $toolInput = $payload.tool_input }
    elseif ($payload.toolInput) { $toolInput = $payload.toolInput }

    $taskId = $null
    foreach ($key in @('taskId', 'task_id', 'id')) {
        if ($toolInput.PSObject.Properties.Name -contains $key -and $toolInput.$key) {
            $taskId = [string]$toolInput.$key
            break
        }
    }

    if (-not $taskId) { Allow-Tool 'sem taskId no input - nao consigo validar, libera' }

    if (-not (Test-Path $LockPath)) { Allow-Tool 'sem lock file - skill video-export-stark nao esta ativa' }

    $lockRaw = Get-Content -Path $LockPath -Raw -ErrorAction Stop
    $lock = $lockRaw | ConvertFrom-Json -ErrorAction Stop

    $approvedIds = @()
    if ($lock.entries) {
        foreach ($entry in $lock.entries) {
            if ($entry.subtask_id) { $approvedIds += [string]$entry.subtask_id }
            if ($entry.parent_task_id) { $approvedIds += [string]$entry.parent_task_id }
        }
    }

    $approvedIds = $approvedIds | Where-Object { $_ } | Select-Object -Unique

    if ($approvedIds -contains $taskId) {
        Allow-Tool "task_id $taskId aprovado no lock"
    }

    Block-Tool ("task_id '" + $taskId + "' NAO esta no lock - Matcher nao aprovou. Aprovadas: " + ($approvedIds -join ', ')) $taskId

} catch {
    Write-HookLog ("ERRO interno (fail-open): " + $_.Exception.Message)
    exit 0
}