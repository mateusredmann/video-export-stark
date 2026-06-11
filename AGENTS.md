# video-export-stark — Agents

Pipeline de 5 agentes que entrega vídeos editados ao cliente via Drive + ClickUp.

## Cadeia — modo varredura (`/video-export`)

```
[Eve]   valida flags, carrega/cria config do editor, pré-flight do rclone
[Scan]  varre pasta-raiz, descobre pares (video, capa, cliente, data)
[Match] ─┐
[Up]     ├─ paralelo, 3-4 simultâneos por par
[Noti]  ─┘   comenta link no ClickUp, @responsável, status="edição concluída"
```

## Cadeia — modo alvo único (`/video-export-task <id|url|caminho>`)

```
[Eve]   config + pré-flight rclone + parseia argumento
[Match reverso/path]  deriva cliente+data (do ClickUp ou do nome/path) + parent_assignees
[Scan dirigido]       acha pasta-data esperada (+ fallbacks) → 1 par filtrado
[Up rclone]           upload do par único
[Noti]                comenta + @ + status (sequencial FR31)
```

Falha em um par não aborta os demais.

## ⚠️ FR31 — Sequencial obrigatório no Noti

NUNCA `clickup_create_task_comment` + `clickup_update_task` em paralelo na mesma subtarefa. O ClickUp dropa o comentário silenciosamente. Ordem: comentário (await + confirma `comment_id`) → status.

## Pontos não-óbvios (que não estão no README/PRD)

- **Cache do editor:** `%USERPROFILE%\.stark-video-export\config.json` (schema v3). Migrações silenciosas v1→v2 (etapa 6 do onboarding) e v2→v3 (injeta `rcloneTeamDriveId` sem perguntar).
- **Estrutura local:** `<videoRoot>\<ano>\<ano> - <Mês>\<DD-MM> <Cliente>\<arquivos>`. Cliente+data são extraídos do **nome da pasta-alvo** (`^(\d{2})-(\d{2})\s+(.+)$`); ano vem da pasta-avó. Pasta que não bate o regex é silenciosamente pulada.
- **Variantes `-SEM.mp4`** (sem-legenda) são silenciosamente descartadas pelo Scanner.
- **Capa é opcional.** Vídeo sem `.png` correspondente sobe só o vídeo — não vira pendência.
- **Estrutura no Drive (default, v1.5):** `clientes/<cliente_drive>/Cronograma de Conteúdo/<ano>/artes/<mes_extenso>/<DD-MM-YYYY>/`. **4 wrappers preexistentes** (`clientes/`, `<cliente_drive>/`, `Cronograma de Conteúdo/`, `artes/`) — NUNCA criados pela skill. Só `<ano>`, `<mes_extenso>` e `<DD-MM-YYYY>` são criáveis sob demanda. Override por cliente via `drive_pasta_reels_id` + `drive_reels_subpath_template` no `clientes.yaml`.
- **Match reverso** (`/video-export-task <id>`): cliente vem por `folder.name` → `parent.name` → regex no `subtask.name`. Data: regex no `subtask.name` → `due_date` da subtarefa → da mãe.
- **Modo path** (`/video-export-task <caminho>`): cliente+data extraídos do filename → nome da pasta → path ascendente (`2026/2026 - Junho/16-06 Janete`). Falha → erro fatal pedindo rename.
- **Compactação:** após cada API call (ClickUp, Drive, rclone lsjson), agentes mantêm só o subset usado a jusante.
- **`clientes.yaml`** mapeia overrides (`drive_nome`, `drive_pasta_reels_id`, `drive_reels_subpath_template`, `clickup_alias`). Campo legado `drive_pasta_ano_id` (importado do `prep-agenda-stark`) é ignorado nesta skill — era pra artes estáticas.
