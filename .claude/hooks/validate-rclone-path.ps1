#Requires -Version 5.1
# PreToolUse hook - valida que comandos rclone copyto/mkdir batem o padrao
# canonico de path do Drive Compartilhado da Stark.
# Exit 0 = libera, exit 2 = bloqueia.

$ErrorActionPreference = 'Stop'

function Write-HookLog {
    param([string]$Message)
    try {
        $logDir = Join-Path $env:USERPROFILE '.stark-video-export\logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logFile = Join-Path $logDir ("hook-rclone-{0:yyyyMMdd}.log" -f (Get-Date))
        Add-Content -Path $logFile -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message) -Encoding utf8
    } catch { }
}

function Allow-Tool {
    param([string]$Reason)
    if ($Reason) { Write-HookLog "ALLOW: $Reason" }
    exit 0
}

function Block-Tool {
    param([string]$Reason)
    Write-HookLog "BLOCK: $Reason"
    [Console]::Error.WriteLine("[hook validate-rclone-path] BLOQUEADO: $Reason")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("Path canonico esperado (modo padrao v1.5):")
    [Console]::Error.WriteLine("  clientes/<cliente_drive>/Cronograma de Conteudo/<ano>/artes/<mes_extenso>/<DD-MM-YYYY>/")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("Modo override: comando precisa conter --drive-root-folder-id <id>.")
    [Console]::Error.WriteLine("Todo upload PRECISA conter --drive-team-drive 0ABl2cpta6dNRUk9PVA")
    exit 2
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow-Tool 'stdin vazio' }

    $payload = $raw | ConvertFrom-Json -ErrorAction Stop

    $cmd = $null
    if ($payload.tool_input -and $payload.tool_input.command) { $cmd = [string]$payload.tool_input.command }
    elseif ($payload.toolInput -and $payload.toolInput.command) { $cmd = [string]$payload.toolInput.command }

    if ([string]::IsNullOrWhiteSpace($cmd)) { Allow-Tool 'sem campo command' }

    if ($cmd -notmatch '(?i)\brclone\b') { Allow-Tool 'sem rclone no comando' }

    # rclone precisa estar em POSICAO DE COMANDO (inicio do comando, ou apos ; & | $( ),
    # nao no meio de uma string (ex.: mensagem de git commit que menciona "rclone copyto").
    $invocationRe = '(?im)(?:^|[;&|]\s*|\$\(\s*)(?:&\s*)?(?:"[^"]*[\\/])?rclone(?:\.exe)?"?\s+(copyto|copy|move|moveto|mkdir|sync|delete|purge)\b'
    $isMutating = ($cmd -match $invocationRe)
    if (-not $isMutating) { Allow-Tool 'sem invocacao rclone mutating em posicao de comando' }

    if ($cmd -notmatch '(?i)--drive-team-drive\s+\S+') {
        Block-Tool "rclone mutating sem --drive-team-drive - upload iria pro Meu Drive pessoal."
    }

    if ($cmd -match '(?i)--drive-root-folder-id\s+\S+') { Allow-Tool 'modo override com --drive-root-folder-id' }

    $quotedMatches = [System.Text.RegularExpressions.Regex]::Matches($cmd, '"([^"]+)"')
    $quoted = @()
    foreach ($m in $quotedMatches) { $quoted += $m.Groups[1].Value }

    $bareMatches = [System.Text.RegularExpressions.Regex]::Matches($cmd, '(?i)\b(?:gdrive|drive|stark)[\w-]*:\S*')
    $bare = @()
    foreach ($m in $bareMatches) { $bare += $m.Value }

    $candidates = @()
    foreach ($p in ($quoted + $bare)) {
        if ($p -match ':') { $candidates += $p }
    }

    if ($candidates.Count -eq 0) { Allow-Tool 'sem path remoto detectavel' }

    $canonicalRe = '(?i)clientes[\\/].+?[\\/]cronograma\s+de\s+conte[uú]do[\\/]\d{4}[\\/]artes[\\/]'
    $matched = $false
    foreach ($p in $candidates) {
        if ($p -match $canonicalRe) { $matched = $true; break }
    }

    if (-not $matched) {
        $shown = (($candidates | Select-Object -First 3) -join ' | ')
        Block-Tool "Path remoto nao bate padrao clientes/<cli>/Cronograma de Conteudo/<ano>/artes/... - paths: $shown"
    }

    Allow-Tool ("path canonico OK (" + $candidates[0] + ")")

} catch {
    Write-HookLog ("ERRO interno (fail-open): " + $_.Exception.Message)
    exit 0
}