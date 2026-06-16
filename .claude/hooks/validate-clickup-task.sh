#!/usr/bin/env bash
# PreToolUse hook (macOS/Linux) — bloqueia clickup_create_task_comment /
# clickup_update_task em task_ids que NAO foram aprovados pelo Matcher.
# Le ~/.stark-video-export/video-export-task-lock.json (escrito pelo Matcher).
# Porte 1:1 do validate-clickup-task.ps1.
# Exit 0 = libera, exit 2 = bloqueia. Fail-open em erro interno.
set -uo pipefail

HOOK_PAYLOAD="$(cat 2>/dev/null || true)" python3 - <<'PYEOF'
import os, re, sys
from datetime import datetime

CACHE_DIR = os.path.join(os.path.expanduser("~"), ".stark-video-export")
LOG_DIR = os.path.join(CACHE_DIR, "logs")
LOCK_PATH = os.path.join(CACHE_DIR, "video-export-task-lock.json")

def hook_log(msg):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        fn = os.path.join(LOG_DIR, "hook-clickup-%s.log" % datetime.now().strftime("%Y%m%d"))
        with open(fn, "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (datetime.now().strftime("%H:%M:%S"), msg))
    except Exception:
        pass

def allow(reason=""):
    if reason:
        hook_log("ALLOW: " + reason)
    sys.exit(0)

def block(reason, task_id):
    hook_log("BLOCK: " + reason)
    e = sys.stderr
    print("[hook validate-clickup-task] BLOQUEADO: " + reason, file=e)
    print("", file=e)
    print("task_id da chamada: " + str(task_id), file=e)
    print("Lock file: " + LOCK_PATH, file=e)
    print("", file=e)
    print("Causa provavel:", file=e)
    print("  1. Matcher resolveu pra OUTRA subtask - re-rode com --dry-run pra ver evidencias.", file=e)
    print("  2. Score < 6 ou sanity_falhou - task vai pra pendencia, NAO comenta nessa subtask.", file=e)
    print("  3. Voce esta chamando ClickUp fora do fluxo da skill - apague o lock pra liberar.", file=e)
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

    tool_name = payload.get("tool_name") or payload.get("toolName")
    if not tool_name:
        allow("sem tool_name")
    if not re.search(r"(?i)clickup_(create_task_comment|update_task)$", str(tool_name)):
        allow("tool %s fora do escopo deste hook" % tool_name)

    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}

    task_id = None
    for key in ("taskId", "task_id", "id"):
        if tool_input.get(key):
            task_id = str(tool_input[key])
            break

    if not task_id:
        allow("sem taskId no input - nao consigo validar, libera")

    if not os.path.isfile(LOCK_PATH):
        allow("sem lock file - skill video-export-stark nao esta ativa")

    with open(LOCK_PATH, "r", encoding="utf-8") as f:
        lock = json.load(f)

    approved = set()
    for entry in (lock.get("entries") or []):
        if entry.get("subtask_id"):
            approved.add(str(entry["subtask_id"]))
        if entry.get("parent_task_id"):
            approved.add(str(entry["parent_task_id"]))

    if task_id in approved:
        allow("task_id %s aprovado no lock" % task_id)

    block("task_id '%s' NAO esta no lock - Matcher nao aprovou. Aprovadas: %s"
          % (task_id, ", ".join(sorted(approved))), task_id)

except SystemExit:
    raise
except Exception as ex:
    hook_log("ERRO interno (fail-open): " + str(ex))
    sys.exit(0)
PYEOF
