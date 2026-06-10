---
description: "Entrega UMA subtarefa específica do ClickUp — passe o task_id, URL, ou só o caminho da pasta local (a skill extrai cliente+data do nome e acha a subtarefa sozinha)."
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - PowerShell
  - Bash
  - mcp__*__clickup_*
  - mcp__*__google_drive*
argument-hint: "<task_id | url | caminho_pasta> [--force] [--dry-run] [--nome-raiz \"reels-01\"]"
---

# /video-export-task

Variante alvo-único do `/video-export`. Aponta pra UMA entrega de 3 formas:

1. **task_id** (`8gqkmtp`) — pipeline reverso (ClickUp → filesystem).
2. **URL ClickUp** (`https://app.clickup.com/t/8gqkmtp`) — idem.
3. **Caminho local** (`"D:\...\16-06 Janete"`) — modo path (filesystem → ClickUp, sem varrer `videoRoot`).

Útil pra: refazer entrega (`--force`); subir item atrasado que `--hoje`/`--semana` não pegaria; mandar só 1 item da pasta do dia; arrastar a pasta aberta direto pro chat.

## Args

- `<alvo>` posicional **obrigatório** — task_id, URL ou pasta absoluta (ver detecção abaixo).
- `--nome-raiz "reels-01"` — restringe ao nome-raiz quando a pasta tem múltiplos pares (sem isso, Eve pergunta).
- `--force` — sobrescreve no Drive se tamanho diferente.
- `--dry-run` — preview do comentário + `rclone copyto` previsto.

## Detecção do tipo de argumento

Ordem (primeira que casar ganha):

1. Contém `clickup.com/t/` ou começa com `/t/` → **URL** → extrai task_id via `/t/([a-z0-9]+)`.
2. Drive letter (`^[A-Za-z]:[\\/]`), UNC (`^\\\\`), POSIX absoluto (`^/[a-z]/`) **ou** contém separador `\`/`/` E `Test-Path` em pasta → **modo path**.
3. `^[a-zA-Z0-9]+$` (alfanumérico sem barras) → **task_id literal**.
4. Nada bateu → erro contextual.

> ⚠️ Path que **não existe** NÃO degrada pra task_id silenciosamente — devolve "caminho não encontrado" e lista 5 entradas mais próximas em `videoRoot`.

## Pipeline

Os passos 0-1b (config + pré-flight rclone) e 6-9 (Up + Drive MCP + Noti sequencial + relatório) são **idênticos** ao `/video-export`. A diferença está nos passos 2-5:

| Modo | Match | Scan |
|---|---|---|
| **reverso** (task_id/URL) | `clickup_get_task` → deriva cliente (folder/list → parent.name → regex no subtask.name) e data (regex no subtask.name → `due_date`) | Scan dirigido: constrói pasta-alvo, tenta variações de pontuação/sem-ano, fallback mtime |
| **path** (caminho) | Extrai cliente+data do filename/pasta/path ascendente (regex `DD[-/.]MM[-/.](YYYY|YY)` ou `DD-MM` + ano herdado do path); depois rota forward normal (`clickup_search "<cliente_norm> <DD-MM>"` + ranking) | n/a — pasta É o input |

Detalhes completos da extração e do scan dirigido em [`workflows/export-task.md`](../../squads/video-export/workflows/export-task.md).

## Exemplos

```
# Modo task_id / URL (reverso)
/video-export-task 8gqkmtp
/video-export-task https://app.clickup.com/t/8gqkmtp
/video-export-task 8gqkmtp --nome-raiz "reels-02"
/video-export-task 8gqkmtp --force
/video-export-task 8gqkmtp --dry-run

# Modo path (direto curto)
/video-export-task "D:\Stark MKT\02 - Videos\2026\2026 - Junho\16-06 Janete"
/video-export-task "D:\..." --nome-raiz "reels-02"
```

## Regras específicas

- **Comentário vai na `subtask_id` resolvida**, NUNCA na tarefa-mãe (mesmo que o cliente venha dela).
- **@-mention** = `parent.assignees` (responsável real da entrega), não da subtarefa.
- **Sequencial FR31** (comentário → await → status): igual ao `/video-export`.
- **Idempotência:** sem `--force`, arquivo idêntico → `skipped`, mas comenta o link mesmo assim.
- **Modo path — falha na extração** → erro fatal pedindo rename pra `DD-MM Cliente.ext` ou passar `--task-id`.
- **Modo reverso — task_id é tarefa-mãe** → Eve avisa e lista subtarefas.

## Não use quando

- Quer tudo do dia → `/video-export --hoje`.
- Quer tudo da semana → `/video-export --semana`.
- Sem task_id e sem caminho → `/video-export` (varre tudo).

## Referência

- [Workflow detalhado](../../squads/video-export/workflows/export-task.md) — extração cliente+data, scan dirigido, edge cases
- [Agente Match](../../squads/video-export/agents/matcher.md) — modos reverso e path
