# Manual do squad Video Export

> Carregado on-demand quando o editor roda `/video-export guide`. Não carrega em invocações normais.

Cobre exclusivamente o repositório `video-export-stark`. Outros squads/plugins (Cut IA, Stark AV, etc.) estão fora de escopo.

## 1. O que faz

1. Varre pasta-raiz local do editor.
2. Empareha vídeo (`.mp4`) + capa (`.png`) pelo nome-raiz.
3. Identifica cliente pelo nome da pasta-pai, data pela subpasta `DD-MM-YYYY` (fallback mtime).
4. Sobe pro Google Drive via **rclone** (sem cap de 10MB do MCP).
5. Comenta link da pasta na subtarefa do ClickUp + @-mention do responsável + status = `edição concluída`.

**Não faz:** edição, color grade, geração de capa, upload de arte estática, Figma.

## 2. Slash commands

### `/video-export` — modo varredura

| Forma | Quando usar |
|---|---|
| `/video-export` | Default pós-onboarding = `--hoje`. |
| `/video-export --hoje` | Sobe **união** de (a) vídeos com `mtime`=hoje no `videoRoot` + (b) subtarefas ClickUp com `due_date`=hoje atribuídas ao `editorEmail`. Não filtra pelo nome da pasta-local. |
| `/video-export --semana` | Seg-sex da semana corrente (mtime na janela). |
| `/video-export "<pasta>"` | Só essa pasta literal. |
| `/video-export --cliente "Dr. Felipe"` | Filtra pasta-pai. |
| `/video-export --force` | Sobrescreve no Drive. |
| `/video-export --dry-run` | Plano sem subir nem comentar. |
| `/video-export --reconfigure` | Reabre onboarding inteiro. |
| `/video-export --setup-rclone` | Só etapa 6 (rclone). |
| `/video-export guide` | Abre este manual. |

### `/video-export-task <task_id|URL|caminho>` — alvo único

| Forma | Quando usar |
|---|---|
| `/video-export-task 8gqkmtp` | Pelo ID curto. |
| `/video-export-task https://app.clickup.com/t/8gqkmtp` | URL — Eve faz parse. |
| `/video-export-task "<pasta>"` | Modo path (direto curto). |
| `/video-export-task 8gqkmtp --nome-raiz "reels-02"` | Múltiplos pares na pasta. |
| `/video-export-task 8gqkmtp --force` | Re-entrega. |
| `/video-export-task 8gqkmtp --dry-run` | Preview. |

**Não use** `/video-export-task` quando: quer subir tudo do dia/semana (`/video-export`); não tem o `task_id` em mãos (use `/video-export` e deixe Match resolver).

## 3. Pipeline

```
[Eve export-chief]  config + flags + escopo + pré-flight rclone
   │
[Scan scanner]      varre pasta-raiz → pares (vídeo, capa, cliente, data)
   │
   ├──► [Match matcher]   subtarefa ClickUp por cliente+data    ─┐ paralelo, lotes de 4
   ├──► [Up uploader]     rclone copyto vídeo+capa → Drive       ─┤
   └──► [Noti notifier]   comenta + @resp + status final         ─┘
   │
[Eve]               consolida relatório
```

| Agente | Persona | Responsabilidade | Tools |
|---|---|---|---|
| [export-chief](../agents/export-chief.md) | Eve | Orquestrador, config, flags, relatório | Filesystem |
| [scanner](../agents/scanner.md) | Scan | Varredura + emparelhamento | Glob, PowerShell |
| [matcher](../agents/matcher.md) | Match | Resolve subtarefa (read-only, com modo reverso) | ClickUp MCP |
| [uploader](../agents/uploader.md) | Up | Drive via rclone, idempotência | rclone, Drive MCP |
| [notifier](../agents/notifier.md) | Noti | Comenta + status (sequencial obrigatório) | ClickUp MCP |

## 4. Configuração

**Cache local:** `%USERPROFILE%\.stark-video-export\config.json` (v3)

```json
{
  "editorEmail": "...",
  "videoRoot": "D:\\Edicoes",
  "videoExt": ".mp4", "capaExt": ".png",
  "mentionResponsavel": true,
  "rcloneRemote": "gdrive",
  "rcloneTeamDriveId": "0ABl2cpta6dNRUk9PVA",
  "version": 3
}
```

Migrações silenciosas: v1 (sem `rcloneRemote`) → dispara etapa 6 do onboarding. v2 (sem `rcloneTeamDriveId`) → injeta o id sem perguntar.

**Overrides por cliente:** `squads/video-export/config/clientes.yaml`

| Campo | Uso |
|---|---|
| `drive_nome` | Pasta no Drive ≠ nome local. |
| `drive_pasta_reels_id` | Pasta-âncora alternativa (estrutura fora do padrão `clientes/<cli>/cronograma de conteúdo/`). |
| `drive_reels_subpath_template` | Template do subpath dentro da âncora (default: `{ano}/{mes_extenso}/{DD-MM-YYYY}`). |
| `clickup_alias` | Tarefa-mãe no ClickUp ≠ pasta local. |
| `drive_pasta_ano_id` *(legado)* | Era pra artes estáticas — Uploader ignora pra vídeos. |

**Convenção de pasta-raiz:**
```
<videoRoot>\<Cliente>\<DD-MM-YYYY>\reels-01.mp4 + reels-01.png + ...
```

**Hierarquia destino Drive (modo padrão — v1.4):**
```
clientes/<drive_nome OR cliente>/cronograma de conteúdo/<ano>/<mes_extenso>/<DD-MM-YYYY>/
```

Regra de criação seletiva:

| Nível                       | Cria?       |
|-----------------------------|-------------|
| `clientes/`                 | **NÃO** (preexistente — fuzzy match exato normalizado) |
| `<cliente_drive>/`          | **NÃO** (preexistente — fuzzy match, usa `drive_nome` se override) |
| `cronograma de conteúdo/`   | **NÃO** (preexistente — fuzzy match com "cronograma" + "conteudo") |
| `<ano>/`                    | **SIM** (sob demanda; ex.: `2026`) |
| `<mes_extenso>/`            | **SIM** (sob demanda; reusa `JUN`/`06`/`JUN26`/etc. se existir, senão cria `junho`) |
| `<DD-MM-YYYY>/`             | **SIM** (sempre; ex.: `19-06-2026`) |

**Modo override (`drive_pasta_reels_id`):**
```
<startFolderId>/<subpath renderizado a partir de drive_reels_subpath_template>/
```

Default do template: `{ano}/{mes_extenso}/{DD-MM-YYYY}`. No override todo o subpath é criável (a âncora é a fronteira). Tokens: `{ano}`, `{mes}`, `{mes_extenso}`, `{MMMAA}`, `{DD-MM}`, `{DD-MM-YYYY}`.

Wrappers ausentes (modo padrão) → pendência específica (`wrapper_clientes_ausente`, `cliente_sem_pasta_no_drive`, `cronograma_de_conteudo_ausente`), nunca cria.

## 5. Dependências

- **rclone ≥ 1.65** com remote `gdrive:`. Onboarding cuida da instalação por SO (winget/brew/install.sh) e config.
- **ClickUp MCP** (busca, comentário, status).
- **Google Drive MCP** (leitura — resolve `webViewLink` pós-upload).

## 6. Regras críticas (NÃO violar)

1. **FR31 — Sequencial no Noti.** `clickup_create_task_comment` + `clickup_update_task` nunca em paralelo na mesma subtarefa (ClickUp dropa o comentário silenciosamente). Ordem: comentário → await → confirma `comment_id` → status → await.
2. **`--drive-team-drive` em TODO comando rclone.** Sem ele cai no Meu Drive pessoal.
3. **Wrappers preexistentes (FR21).** Skill nunca cria `clientes/`, `<cliente_drive>/` nem `cronograma de conteúdo/`. Só cria `<ano>/`, `<mes_extenso>/` e `<DD-MM-YYYY>/`. No modo override, só a âncora `<startFolderId>` é preexistente.
4. **Normalização cliente (FR19a).** Remove `Dr.`/`Dra.`, lowercase, sem acento, trim — antes de qualquer comparação.
5. **Mismatch silencioso proibido (FR25a).** `drive_nome` no YAML + pasta inexistente → falha, NÃO cai pro `cliente`.
6. **Match read-only.** Sem subtarefa → pendência, nunca cria.
7. **Falha parcial não aborta o lote.**

## 7. Troubleshooting

| Sintoma | Causa | Ação |
|---|---|---|
| `rclone não detectado` | Fora do PATH | `/video-export --setup-rclone` |
| `remote não enxerga 'clientes/'` | Google errado | `rclone config reconnect gdrive:` |
| `subtarefa não encontrada` | Nome ≠ ClickUp | Adicionar `clickup_alias` no YAML |
| Comentário sumiu + status mudou | Violou FR31 | Bug — Noti deve ser sequencial |
| Upload trava em arquivo grande | Caiu no Drive MCP | Verificar `transport: "rclone"` |
| `wrapper_clientes_ausente` | Raiz do shared drive sem `clientes/` | Criar `clientes/` manualmente no shared drive |
| `cliente_sem_pasta_no_drive` | `clientes/<cliente>/` ausente | Criar pasta do cliente em `clientes/` (onboarding do cliente) |
| `cronograma_de_conteudo_ausente` | Pasta-âncora ausente dentro do cliente | Criar `cronograma de conteúdo/` no cliente OU usar override `drive_pasta_reels_id` |
| `output.fuzzy[]` populado | Match não-exato no gate | Ver no relatório qual wrapper caiu no fuzzy — pode indicar inconsistência de nomenclatura no Drive |
| `--hoje` lista `clickup_sem_arquivo` | Tarefa vence hoje, vídeo não foi editado/exportado | Checar `videoRoot\<Cliente>\<DD-MM-YYYY>` no PC |
| `--hoje` lista `fs_sem_subtask` | Vídeo editado hoje sem tarefa correspondente | Adicionar `clickup_alias` ou criar subtarefa |
| `--hoje` aborta `editorEmail ausente` | Config sem e-mail do editor | `/video-export --reconfigure` |

## 8. Referência interna

- [README do squad](../README.md)
- [PRD completo](../docs/PRD.md) — todos os FRs
- [squad.yaml](../squad.yaml)
- [Onboarding detalhado](../tasks/onboarding.md)
- Tasks: [scan-pasta](../tasks/scan-pasta.md), [upload-drive](../tasks/upload-drive.md), [notificar-clickup](../tasks/notificar-clickup.md)
