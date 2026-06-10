---
name: video-export
description: |
  Entrega vídeos editados da Stark Marketing — varre pasta-raiz local do editor,
  empareha vídeo+capa pelo nome-raiz, sobe pro Google Drive na hierarquia padrão
  (com overrides por cliente), comenta o link da pasta na subtarefa do ClickUp
  com @-mention do responsável e move pra "edição concluída". Sem Figma — só delivery.
  Acionar SEMPRE que o usuário pedir: "sobe os vídeos editados", "entrega de vídeo",
  "exporta os reels da semana", "joga os vídeos do [cliente] pro Drive", "fecha as
  edições do dia", "/video-export", ou qualquer variação de delivery final pós-edição.
  NÃO usar para: edição de vídeo em si (corte, color grade), geração de capa,
  upload de arte estática (use entrega-reels-drive-clickup ou figma-export-para-drive
  pra esses casos).
version: 1.4.0
author: stark.marketing
license: UNLICENSED
tags: [video, delivery, clickup, google-drive, rclone, stark]
mcps_required: [clickup, google-drive]
external_tools_required: [rclone]
platforms: [claude-code, cowork, portable-llm]
---

# Video Export — Skill

Squad de 5 agentes (Eve, Scan, Match, Up, Noti) que entrega vídeos editados ao cliente. Lê pasta local → sobe pro Drive Compartilhado da Stark (rclone, sem cap de 10MB) → comenta link na subtarefa do ClickUp → muda status. Especificações detalhadas em [`squads/video-export/agents/*.md`](../../../squads/video-export/agents/) — esta SKILL.md é o resumo operacional.

## 1. Quando acionar

- "sobe os vídeos editados de hoje"
- "manda os reels do Dr. X pro Drive"
- "fecha a semana de edição"
- `/video-export …` ou `/video-export-task …`

**NÃO usar para:** edição/corte/efeitos, geração de capa (`stark-av-renderer`/`entrega-reels-drive-clickup`), Figma (`figma-export-para-drive`).

## 2. Comandos

```
/video-export                             # 1ª vez: onboarding. Depois: --hoje
/video-export --hoje | --semana
/video-export "<pasta>"                   # pasta específica
/video-export --cliente "Diego Gonzalez"  # filtra cliente extraído
/video-export --force | --dry-run
/video-export --reconfigure | --setup-rclone
/video-export-task <task_id | URL | caminho>  # alvo único — modo reverso ou path
/video-export guide                       # abre o manual
```

Flags combinam. `/video-export-task` documentado em [`.claude/commands/video-export-task.md`](../../../.claude/commands/video-export-task.md).

## 3. Onboarding

Config em `%USERPROFILE%\.stark-video-export\config.json` (v3). Se ausente ou `--reconfigure`, pergunta uma por vez:

1. Email ClickUp (autocomplete via `clickup_get_workspace_members`)
2. Pasta-raiz (`Test-Path`)
3. Extensão vídeo (default `.mp4`)
4. Extensão capa (default `.png`)
5. @-mention responsável? (default `sim`)
6. **rclone** — checa CLI, guia install (winget/brew/install.sh), configura remote `gdrive:` via `rclone config` (responder **N** em "Configure as Shared Drive"), valida com `rclone lsd gdrive: --drive-team-drive 0ABl2cpta6dNRUk9PVA --max-depth 1` (raiz do shared drive contém os clientes diretamente — sem wrapper `Clientes/`). Detalhes em [`tasks/onboarding.md`](../../../squads/video-export/tasks/onboarding.md) §6.

Config:
```json
{ "editorEmail": "...", "videoRoot": "D:\\Stark MKT\\02 - Videos",
  "videoExt": ".mp4", "capaExt": ".png", "mentionResponsavel": true,
  "rcloneRemote": "gdrive", "rcloneTeamDriveId": "0ABl2cpta6dNRUk9PVA",
  "version": 3 }
```

**Migrações silenciosas:** v1 (sem `rcloneRemote`) → roda só etapa 6, salva v2. v2 (sem `rcloneTeamDriveId`) → injeta o id default sem perguntar, revalida, salva v3. `--setup-rclone` força só etapa 6.

> 🚨 **Drive Compartilhado, não Meu Drive.** Todo `rclone` roda com `--drive-team-drive <rcloneTeamDriveId>` (default `0ABl2cpta6dNRUk9PVA`). Sem o flag, upload cai no Meu Drive pessoal. Só sobe pra cliente que já tem pasta nesse shared drive — senão pendência, nunca cria a raiz.
>
> 🚨 **rclone obrigatório:** Drive MCP rejeita uploads > 10MB. Vídeos editados quase sempre passam disso.
>
> 📌 **Sem wrapper `Clientes/`.** Clientes ficam direto na raiz do shared drive. A spec antiga apontava pra `Clientes/<cli>/Cronograma de Conteudo/Artes/<ano>/<mes>/<DD-MM-YYYY>/` (estrutura de artes do `prep-agenda-stark`) — não se aplica a vídeos.

## 4. Pipeline

```
[Eve]   config + flags + escopo + pré-flight rclone
   │
[Scan]  varre videoRoot → pares (vídeo, capa-opcional, cliente, data)
   │  por par, lotes de 4 em paralelo:
   ├──► [Match]  subtarefa ClickUp por cliente+data (read-only)
   ├──► [Up]     rclone copyto vídeo (+ capa se existir) → Drive
   └──► [Noti]   comenta + @resp + status="edição concluída"  ← SEQUENCIAL FR31
   │
[Eve]   relatório consolidado
```

- Falha em 1 par não aborta os demais (vai pra pendências).
- Idempotência: arquivo já no Drive (mesmo `Size`) → `skipped`. `--force` sobrescreve.
- Log: `%USERPROFILE%\.stark-video-export\logs\<timestamp>.log`.

## 5. Estrutura esperada (local)

```
<videoRoot>\<ano>\<ano> - <Mês>\<DD-MM> <Cliente>\<DD-MM> <Cliente>.mp4
                                                  \<DD-MM> <Cliente>.png   (opcional)
                                                  \<DD-MM> <Cliente>-SEM.mp4  (ignorado)
```

- **Cliente + data**: extraídos do nome da pasta-alvo via regex `^(?<dia>\d{2})-(?<mes>\d{2})\s+(?<cliente>.+)$`. Ano vem da pasta-avó (`<ano> - <Mês>`), fallback mtime.
- **Par** = vídeo + (opcional) capa com mesmo nome-raiz. Sem capa, sobe só vídeo. Capa órfã (`.png` sem `.mp4`) vira pendência.
- **Variante ignorada**: `.mp4` cujo `BaseName` termina em `-SEM` (case-insensitive) — versão sem-legenda, não entrega.
- Pasta que não bate o regex (ex.: `Inbox/`) → silenciosamente pulada.

## 6. Estrutura no Drive

**Default (zero-config):**
```
<drive_nome OR cliente>/01. Cronograma de Reels | <drive_nome OR cliente>/<DD-MM-YYYY>/
```
Ex.: `gdrive:Dr Diego Gonzalez/01. Cronograma de Reels | Dr Diego Gonzalez/19-06-2026/19-06 Diego Gonzalez.mp4`.

**Override por cliente** (`clientes.yaml`):
```yaml
"Diego Gonzalez":
  drive_nome: "Dr Diego Gonzalez"          # pasta no Drive ≠ nome extraído pelo Scanner

"Dr. Foo":
  drive_pasta_reels_id: "<folderId>"       # pasta-âncora alternativa
  drive_reels_subpath_template: "{ano}/{MMMAA}/{DD-MM-YYYY}"   # default: "{DD-MM-YYYY}"
```

Tokens do template: `{ano}`, `{mes}` (2 dígitos), `{mes_extenso}` (`junho`), `{MMMAA}` (`JUN26`), `{DD-MM}`, `{DD-MM-YYYY}`. Template vazio = arquivos sobem direto na âncora.

## 7. Agentes — resumo

Especificações completas em [`squads/video-export/agents/`](../../../squads/video-export/agents/). Cada agente carrega seu `.md` quando invocado. Sumário:

### Scan ([scanner.md](../../../squads/video-export/agents/scanner.md))
Input: `videoRoot`, `videoExt`, `capaExt`, `escopo={modo, pasta?, cliente?}`. Modos: `pasta` (literal) | `hoje` (varre `videoRoot` inteiro filtrando arquivos com `LastWriteTime`=hoje — **não** filtra pelo nome da pasta) | `semana` (mtime na janela seg-sex) | `all`. Filtra `-SEM.mp4` na entrada. Pra cada pasta-alvo que bate `<DD-MM> <Cliente>`: glob por extensão, capa é opcional (par tem `capa: null` se ausente). Ano vem da pasta-avó. **Data nunca é "hoje" — sempre vem da pasta-local.** Output: `pares[]` + `orfaos[]` (capa sem vídeo).

### Match ([matcher.md](../../../squads/video-export/agents/matcher.md))
**Read-only**. Modo forward (input `cliente`+`data`): normaliza (remove `Dr.`/`Dra.`, lowercase, sem acento, trim) → aplica `clickup_alias` do `clientes.yaml` → `clickup_search "<cliente_norm> <DD-MM>"` → ranking (cliente bate no path da lista; data no nome `DD-MM|DD/MM|DD-MM-YYYY|DD-MM-AA`; bônus por "edição/vídeo/reels"). 0 match → pendência. Lê `parent.assignees` pra @-mention. Modo reverso (input `task_id`) e modo path documentados em [`workflows/export-task.md`](../../../squads/video-export/workflows/export-task.md).

### Up ([uploader.md](../../../squads/video-export/agents/uploader.md))
Consulta `clientes.yaml`. **Gate (antes de mkdir/copyto):** `rclone lsf "<remote>:<drive_nome OR cliente>" <TD> --dirs-only --max-depth 1` — pasta-raiz ausente no shared drive → `failed`, **NUNCA** cria a raiz. Modo override: validar `drive_pasta_reels_id` resolve dentro do shared drive.

**Hierarquia destino:**
- Padrão: `<drive_nome OR cliente>/01. Cronograma de Reels | <drive_nome OR cliente>/<DD-MM-YYYY>/`
- Override (`drive_pasta_reels_id`): `<startFolderId>/<subpath via drive_reels_subpath_template>/`

**Idempotência:** `rclone lsjson "<remote>:<path>" <TD> --files-only` → compara `Name`+`Size`. Match exato → `skipped`. Diferente sem `--force` → pula com warning. Com `--force` → sobrescreve.

**Upload:**
```powershell
rclone mkdir "<remote>:<path_destino>" <TD>
rclone copyto "<video>" "<remote>:<path_destino>/<basename>" <TD> --progress --transfers 1 --drive-chunk-size 64M --retries 2
if ($capa) { rclone copyto "<capa>" "<remote>:<path_destino>/<basename>" <TD> --retries 2 }
```

`<TD>` = `--drive-team-drive <config.rcloneTeamDriveId>` — **obrigatório em todo comando**. Modo override: usar `--drive-root-folder-id <startFolderId>` junto com `<TD>`, OU pré-resolver via `google_drive_get_file_metadata`.

**Exit codes:** `0` ok | `5` rate-limit → 1 retry com backoff 5s | demais → falha clara.

**Pós-upload:** `google_drive_list_files` na pasta → captura `folder.webViewLink/id` + arquivos `id/webViewLink`. Cache `folder.id` por `(cliente, data)`. Fallback se Drive MCP off: `rclone link <remote>:<path> <TD>`.

**Validação:** re-`lsjson`. Capa null + vídeo ok → `ok`. Capa esperada mas faltou → `partial`. Vídeo faltou → `failed`.

### Noti ([notifier.md](../../../squads/video-export/agents/notifier.md))

**Template:**
```
@<responsável> ✅ Edição concluída.
Ref: <cliente> — <DD-MM> <nome_raiz>
Entregue: <linha-entrega>

🔗 Drive: <drive_folder_url>
```
`<linha-entrega>` é renderizada a partir de `arquivos_entregues`: `vídeo (.mp4) + capa (.png)` quando ambos, `vídeo (.mp4)` quando só vídeo. Sem `mentionResponsavel` ou sem assignees: omite o prefixo `@…`. Múltiplos assignees: `@A @B` separados por espaço.

> ⚠️ **FR31 — SEQUENCIAL OBRIGATÓRIO.** NUNCA `clickup_create_task_comment` + `clickup_update_task` em paralelo na mesma subtarefa. ClickUp dropa o comentário silenciosamente (200 OK, mas some). Ordem: comentário → AWAIT → confirma `comment_id` → status → AWAIT. Falha no status com comentário ok → registra `comment_ok_status_fail`, sem rollback.

Status final fixo = `edição concluída`. Lista não tem esse status → mantém atual + flag `comment_ok_status_fail`. `drive_folder_url` vazio → não comenta, vai pra pendência. Sem dedup — re-rodar = 2 comentários (preferível a complexidade).

### Eve ([export-chief.md](../../../squads/video-export/agents/export-chief.md))
Orquestrador: config, flags, escopo, distribui pares em lotes de `parallelism` (default 4), consolida relatório. **No modo `--hoje`** monta o lote unindo duas fontes — Scan mtime=hoje no `videoRoot` ∪ subtarefas ClickUp com `due_date=hoje` e `assignee=editorEmail` (modo reverso do matcher) — deduplica por `(cliente, data, nome_raiz)`. Origem registrada por par (`fs`/`clickup`/`ambos`). Data no Drive = pasta-local sempre (nunca `due_date`, nunca "hoje"). Modo `--semana` adiciona sub-totais por dia útil.

## 8. Overrides por cliente

Em [`config/clientes.yaml`](../../../squads/video-export/config/clientes.yaml). Campos:

| Campo                          | Quando usar                                                                   |
|--------------------------------|-------------------------------------------------------------------------------|
| `drive_nome`                   | Pasta no Drive ≠ nome extraído pelo Scanner (ex.: "Diego Gonzalez" → "Dr Diego Gonzalez"). |
| `drive_pasta_reels_id`         | Pasta-âncora de reels não é o default `01. Cronograma de Reels | <cli>`.       |
| `drive_reels_subpath_template` | Customiza subpath dentro da âncora. Default: `{DD-MM-YYYY}`.                  |
| `clickup_alias`                | Subtarefa no ClickUp usa nome diferente do extraído (ex.: "Jussara" → "Jussara Lazarini"). |

Campo `drive_pasta_ano_id` é **legado** (era pra artes estáticas do `prep-agenda-stark`) e ignorado pelos vídeos.

Clientes sem entrada usam modo padrão automaticamente.

## 9. Erros & troubleshooting

| Sintoma | Ação |
|---|---|
| Pasta `<drive_nome>/` não existe no shared drive | `failed`, pendência. NUNCA cria a raiz. |
| Pasta-âncora `01. Cronograma de Reels \| <cli>` ausente | `failed`. Pasta deve ser criada no onboarding do cliente, fora desta skill. |
| `drive_pasta_reels_id` inválido / fora do shared drive | `failed`, pede update do YAML. |
| `--drive-team-drive` ausente | Bug — sempre passar. Default `0ABl2cpta6dNRUk9PVA`. |
| Pasta-local sem capa `.png` | Sobe só vídeo. Status `ok`. NÃO é pendência. |
| Pasta-local com vídeo `-SEM.mp4` | Silenciosamente descartado pelo Scanner. |
| Pasta-local não bate `<DD-MM> <Cliente>` | Silenciosamente pulada (não erro). |
| Quota Drive estourada / timeout | 1 retry backoff 5s, depois `failed`. |
| MCP Drive offline | Não aborta — fallback `rclone link` pra URL. |
| `rclone` ausente / sem remote | Aborta squad pedindo `/video-export --setup-rclone`. |
| `rclone copyto` exit ≠ 0 | `failed`, registra stderr no log. |
| Subtarefa ClickUp não encontrada | Pendência. NÃO cria task nova. |
| `--hoje`: tarefa vence hoje sem arquivo no PC | Pendência `clickup_sem_arquivo`. Não tenta subir. Editor checa o filesystem. |
| `--hoje`: vídeo editado hoje sem subtarefa após Match forward | Pendência `fs_sem_subtask`. Adicionar `clickup_alias` no YAML ou criar a subtarefa. |
| `editorEmail` ausente no config (necessário pro filtro de ClickUp no `--hoje`) | Aborta pedindo `/video-export --reconfigure`. |
| Status `edição concluída` não existe na lista | Mantém status + `comment_ok_status_fail`. |
| `drive_nome` no YAML mas pasta inexistente | `failed`. NÃO cai pro nome extraído. |
| Comentário sumiu + status mudou | Violou FR31 — Noti deve ser sequencial. |

## 10. Ferramentas

**ClickUp MCP:** `clickup_search` | `clickup_filter_tasks` | `clickup_get_task` | `clickup_create_task_comment` | `clickup_update_task` | `clickup_resolve_assignees` | `clickup_get_workspace_members` (onboarding).

**Google Drive MCP** (apenas leitura): `google_drive_list_files`, `google_drive_get_file_metadata`. Upload sai por rclone.

**rclone CLI** (todos com `--drive-team-drive <rcloneTeamDriveId>`): `listremotes` | `config show` | `lsd`/`lsjson`/`lsf` | `mkdir` | `copyto` | `link` (fallback) | `config reconnect`.

**Filesystem/Shell:** `Glob`, `PowerShell` (`Test-Path`, `Get-Item|Select LastWriteTime/Length`, `Get-Command rclone`), `Read`/`Write`/`Edit`.

## 11. Portabilidade

Funciona em Claude Code / Cowork / outros LLMs com tool use (ChatGPT/Gemini/Grok). Em LLM sem tool use, vira modo consultivo (imprime os comandos pro operador rodar). Substitua `Test-Path X` → `[ -e X ]`, `Get-Item .. | Select LastWriteTime` → `stat -c %Y X`. Cache: Windows `%USERPROFILE%\.stark-video-export\`, mac/linux `~/.stark-video-export/`. A lógica de matching, hierarquia Drive, template e regra FR31 NÃO mudam.

## 12. Fora do escopo (v1)

Múltiplos editores no mesmo cache; conversão de formato (HEIC/MOV); geração de capa; validação de conteúdo; Slack/WhatsApp; criação automática de subtarefa; multi-workspace ClickUp; status configurável por tipo de post; varredura de variantes além de `-SEM` (`-LEG`, `-SUB` ficam pra futuro).
