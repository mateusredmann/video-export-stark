#!/usr/bin/env bash
# PreToolUse hook (macOS/Linux) — valida que comandos rclone mutating batem o
# padrao canonico de path do Drive Compartilhado da Stark.
# Porte 1:1 do validate-rclone-path.ps1 (regex via python3, mesma semantica .NET).
# Exit 0 = libera, exit 2 = bloqueia. Fail-open em erro interno.
set -uo pipefail

# Repassa o payload (stdin) pro python via env var — o heredoc ocupa o stdin do python.
HOOK_PAYLOAD="$(cat 2>/dev/null || true)" python3 - <<'PYEOF'
import os, re, sys
from datetime import datetime

LOG_DIR = os.path.join(os.path.expanduser("~"), ".stark-video-export", "logs")

def hook_log(msg):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        fn = os.path.join(LOG_DIR, "hook-rclone-%s.log" % datetime.now().strftime("%Y%m%d"))
        with open(fn, "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (datetime.now().strftime("%H:%M:%S"), msg))
    except Exception:
        pass

def allow(reason=""):
    if reason:
        hook_log("ALLOW: " + reason)
    sys.exit(0)

def block(reason):
    hook_log("BLOCK: " + reason)
    e = sys.stderr
    print("[hook validate-rclone-path] BLOQUEADO: " + reason, file=e)
    print("", file=e)
    print("Path canonico esperado (modo padrao v1.5):", file=e)
    print("  clientes/<cliente_drive>/Cronograma de Conteudo/<ano>/artes/<mes_extenso>/<DD-MM-YYYY>/", file=e)
    print("", file=e)
    print("Modo override: comando precisa conter --drive-root-folder-id <id>.", file=e)
    print("Todo upload PRECISA conter --drive-team-drive 0ABl2cpta6dNRUk9PVA", file=e)
    sys.exit(2)

try:
    import json
    raw = os.environ.get("HOOK_PAYLOAD", "")
    if not raw or not raw.strip():
        allow("stdin vazio")

    try:
        payload = json.loads(raw)
    except Exception:
        allow("stdin nao-JSON (fail-open)")

    ti = payload.get("tool_input") or payload.get("toolInput") or {}
    cmd = ti.get("command") if isinstance(ti, dict) else None
    cmd = str(cmd) if cmd else ""

    if not cmd.strip():
        allow("sem campo command")

    if not re.search(r"\brclone\b", cmd, re.I):
        allow("sem rclone no comando")

    # rclone precisa estar em POSICAO DE COMANDO (inicio, ou apos ; & | $( ),
    # nao no meio de uma string (ex.: git commit mencionando "rclone copyto").
    invocation_re = r'(?im)(?:^|[;&|]\s*|\$\(\s*)(?:&\s*)?(?:"[^"]*[\\/])?rclone(?:\.exe)?"?\s+(copyto|copy|move|moveto|mkdir|sync|delete|purge)\b'
    if not re.search(invocation_re, cmd):
        allow("sem invocacao rclone mutating em posicao de comando")

    if not re.search(r"(?i)--drive-team-drive\s+\S+", cmd):
        block("rclone mutating sem --drive-team-drive - upload iria pro Meu Drive pessoal.")

    if re.search(r"(?i)--drive-root-folder-id\s+\S+", cmd):
        allow("modo override com --drive-root-folder-id")

    quoted = re.findall(r'"([^"]+)"', cmd)
    bare = re.findall(r"(?i)\b(?:gdrive|drive|stark)[\w-]*:\S*", cmd)
    candidates = [p for p in (quoted + bare) if ":" in p]

    if not candidates:
        allow("sem path remoto detectavel")

    canonical_re = r"(?i)clientes[\\/].+?[\\/]cronograma\s+de\s+conte[uú]do[\\/]\d{4}[\\/]artes[\\/]"
    if any(re.search(canonical_re, p) for p in candidates):
        allow("path canonico OK (" + candidates[0] + ")")

    shown = " | ".join(candidates[:3])
    block("Path remoto nao bate padrao clientes/<cli>/Cronograma de Conteudo/<ano>/artes/... - paths: " + shown)

except SystemExit:
    raise
except Exception as ex:
    hook_log("ERRO interno (fail-open): " + str(ex))
    sys.exit(0)
PYEOF
