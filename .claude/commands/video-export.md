---
description: "Entrega vídeos editados → Drive (via rclone) + ClickUp. Use `/video-export guide` pra abrir o manual do repositório."
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - PowerShell
  - Bash
  - mcp__*__clickup_*
  - mcp__*__google_drive*
argument-hint: "[guide | --hoje | --semana | <pasta> | --cliente \"Nome\"] [--force] [--dry-run] [--reconfigure | --setup-rclone]"
---

# /video-export

Entry-point do squad Video Export. Lê config local, varre pasta-raiz, sobe vídeo+capa pro Drive e comenta na ClickUp.

## Despacho inicial — `guide`

**Se o primeiro token de `$ARGUMENTS` for `guide`** (com qualquer capitalização — `guide`, `Guide`, `GUIDE`), **NÃO execute a pipeline de entrega**. Em vez disso, **imprima literalmente todo o conteúdo da seção `# Manual do squad Video Export`** abaixo (a partir do título inclusivo, até o fim do arquivo), renderizado como Markdown pro editor. Não rode tools, não consulte config, não toque no ClickUp/Drive. Apenas exiba o manual e termine o turno.

Se o editor passar argumentos depois de `guide` (ex: `/video-export guide --reconfigure`), ignore-os — o manual não tem sub-modos.

Caso contrário, siga o fluxo de delivery abaixo.

## Args recebidos

`$ARGUMENTS` pode conter combinações de:

- `guide` — abre o [Manual do squad Video Export](#manual-do-squad-video-export) e sai
- `--hoje` — default após onboarding
- `--semana` — segunda a sexta da semana corrente
- `<pasta>` — caminho absoluto pra uma pasta específica
- `--cliente "Nome"` — filtra pelo nome da pasta-pai
- `--force` — sobrescreve no Drive
- `--dry-run` — preview sem efeitos colaterais
- `--reconfigure` — reabre o onboarding completo
- `--setup-rclone` — roda só a etapa 6 (rclone) do onboarding

## Comportamento por etapa

### 1. Carregar config

Lê `%USERPROFILE%\.stark-video-export\config.json`.

- Não existe OU `--reconfigure` passado → roda [onboarding completo](../../squads/video-export/tasks/onboarding.md) e continua.
- `--setup-rclone` passado → executa só a etapa 6 do onboarding (rclone), salva, continua.
- Config existe com `version: 1` (sem `rcloneRemote`) → migração silenciosa: roda só a etapa 6, sobe pra v2, continua.
- Config existe v2 → segue direto pro scan.

### 1b. Pré-flight do rclone (antes de qualquer upload)

- `Get-Command rclone` → existe?
- `rclone listremotes` contém `config.rcloneRemote`?
- `rclone config show <remote>` retorna `type = drive`?

Falhou qualquer um → aborta com mensagem pedindo `/video-export --setup-rclone`.

### 2. Resolver modo

Ordem de precedência:
1. `<pasta>` posicional → `modo=pasta`
2. `--semana` → `modo=semana`
3. `--hoje` ou nada → `modo=hoje`

### 3. Executar pipeline

Despacha pra Eve (export-chief) com o config + modo + flags. Eve cuida da cadeia:

```
Scan → (Match ∥ Up ∥ Noti) por par, lotes de 4 → Relatório
```

Detalhes em [squads/video-export/agents/export-chief.md](../../squads/video-export/agents/export-chief.md).

### 4. Mostrar relatório

Imprime o relatório final consolidado pelo Eve no terminal.

## Exemplos

```
/video-export
/video-export --semana
/video-export "D:\Edicoes\Dr. Rodolfo Soares\27-05-2026"
/video-export --cliente "Dr. Felipe" --hoje
/video-export --semana --dry-run
/video-export --reconfigure
```

## Referência

- [README do squad](../../squads/video-export/README.md)
- [PRD](../../squads/video-export/docs/PRD.md)
- [squad.yaml](../../squads/video-export/squad.yaml)

---

# Manual do squad Video Export

> Imprima esta seção inteira quando o editor rodar `/video-export guide`.

Este manual cobre **exclusivamente o repositório `video-export-stark`**. Outros squads/plugins (Cut IA, Stark AV, etc.) não fazem parte do escopo desta skill.

## 1. O que esta skill faz

Automatiza o **delivery** de vídeos editados pelos editores da Stark:

1. Varre a pasta-raiz local do editor.
2. Empareha vídeo (`.mp4`) + capa (`.png`) pelo nome-raiz.
3. Identifica o cliente pelo nome da pasta-pai.
4. Sobe pro Google Drive (via **rclone** — sem o cap de 10MB do MCP).
5. Comenta o link da pasta na subtarefa do ClickUp, @-menciona o responsável e move pra status `edição concluída`.

**Não faz:** edição de vídeo, color grade, geração de capa, upload de arte estática, fluxo Figma. Pra esses, use outras skills.

## 2. Slash commands do repositório

Apenas **dois** slashes vivem neste repo:

### `/video-export` — modo varredura

Varre `videoRoot` por filtro de data ou pasta literal e entrega TODOS os pares que encontrar.

| Forma | Quando usar |
|---|---|
| `/video-export` | Default pós-onboarding = `--hoje`. Sobe tudo que foi editado hoje. |
| `/video-export --hoje` | Idem, explícito. |
| `/video-export --semana` | Seg-sex da semana corrente. Bom pro fechamento de sexta. |
| `/video-export "<pasta>"` | Sobe só o que estiver naquela pasta literal. |
| `/video-export --cliente "Dr. Felipe"` | Filtra a varredura pelo nome da pasta-pai. |
| `/video-export --force` | Sobrescreve no Drive se o arquivo já existir com tamanho diferente. |
| `/video-export --dry-run` | Mostra payload e plano sem subir nem comentar. |
| `/video-export --reconfigure` | Reabre o onboarding inteiro. |
| `/video-export --setup-rclone` | Roda só a etapa 6 (rclone) — pra reconfigurar remote sem mexer no resto. |
| `/video-export guide` | Abre este manual. |

### `/video-export-task <task_id\|URL>` — modo alvo único

Inverte o fluxo: começa pelo ClickUp e desce pro filesystem. Útil quando você quer entregar UMA subtarefa específica.

| Forma | Quando usar |
|---|---|
| `/video-export-task 8gqkmtp` | Entrega a subtarefa pelo ID curto. |
| `/video-export-task https://app.clickup.com/t/8gqkmtp` | Cola a URL direto, Eve faz parse. |
| `/video-export-task 8gqkmtp --nome-raiz "reels-02"` | Pasta tem múltiplos pares — fixa qual processar. |
| `/video-export-task 8gqkmtp --force` | Re-entrega mesmo se já estava no Drive. |
| `/video-export-task 8gqkmtp --dry-run` | Preview do comentário e do `rclone copyto`. |

**Quando NÃO usar `/video-export-task`:** quer subir tudo do dia/semana → use `/video-export`. Não tem o `task_id` em mãos → use `/video-export` normal e deixe o Match achar.

## 3. Arquitetura — agentes e pipeline

```
[Eve export-chief]  carrega config, valida flags, define escopo, pré-flight do rclone
   │
[Scan scanner]   varre pasta-raiz → lista pares (vídeo, capa, cliente, data)
   │
   ├──► [Match matcher]   busca subtarefa ClickUp por cliente+data    ─┐ (paralelo, lotes de 4)
   ├──► [Up uploader]     rclone copyto vídeo+capa → Drive            ─┤
   └──► [Noti notifier]   comenta link + @resp + status "edição concluída"
```

| Agente | Persona | Responsabilidade | Tools/MCPs |
|---|---|---|---|
| [export-chief](squads/video-export/agents/export-chief.md) | Eve | Orquestrador. Onboarding, flags, cache, relatório. | Filesystem |
| [scanner](squads/video-export/agents/scanner.md) | Scan | Varredura, emparelhamento por nome-raiz, extração cliente+data. | Glob, PowerShell |
| [matcher](squads/video-export/agents/matcher.md) | Match | Resolve subtarefa ClickUp dinamicamente. Modo reverso pro `/video-export-task`. | ClickUp MCP |
| [uploader](squads/video-export/agents/uploader.md) | Up | Cria pasta no Drive e sobe vídeo+capa via rclone. Idempotência. | rclone, Drive MCP |
| [notifier](squads/video-export/agents/notifier.md) | Noti | Comenta + @-mention + muda status. **Sequencial obrigatório.** | ClickUp MCP |

## 4. Workflows (despachados pela Eve)

| Workflow | Trigger | Especificação |
|---|---|---|
| Export Hoje | `/video-export` ou `/video-export --hoje` | [export-hoje.md](squads/video-export/workflows/export-hoje.md) |
| Export Semana | `/video-export --semana` | [export-semana.md](squads/video-export/workflows/export-semana.md) |
| Export Pasta | `/video-export "<pasta>"` | [export-pasta.md](squads/video-export/workflows/export-pasta.md) |
| Export Task | `/video-export-task <id>` | [export-task.md](squads/video-export/workflows/export-task.md) |

## 5. Configuração

### 5.1 Config do editor (cache local)

Caminho: `%USERPROFILE%\.stark-video-export\config.json` (v2 a partir de 2026-06)

```json
{
  "editorEmail": "mateus.redmann@starkmkt.com",
  "videoRoot": "D:\\Edicoes",
  "videoExt": ".mp4",
  "capaExt": ".png",
  "mentionResponsavel": true,
  "rcloneRemote": "gdrive",
  "version": 2
}
```

- **Reconfigurar tudo:** `/video-export --reconfigure`
- **Reconfigurar só o rclone:** `/video-export --setup-rclone`
- **Migração v1 → v2:** se a config existe sem `rcloneRemote`, Eve dispara automaticamente só a etapa 6 do onboarding na próxima execução (sem repetir email/pasta/extensões).

Logs por execução: `%USERPROFILE%\.stark-video-export\logs\<timestamp>.log`.

### 5.2 Overrides por cliente (versionado no repo)

Arquivo: `squads/video-export/config/clientes.yaml`

```yaml
clientes:
  "Dr. Anderson Kuboniwa":
    drive_nome: "Dr. Anderson"             # pasta no Drive não bate com nome ClickUp
    drive_pasta_ano_id: "1938YPt9KZtC..."  # startFolderId p/ estrutura não-padrão

  "Dr. Gilberto Filho":
    drive_pasta_ano_id: "1PU7nohuXw-..."   # "Artes 2026 | Dr. Gilberto Filho"

  "Dr. Rodolfo Soares":
    # sem overrides → usa hierarquia padrão
```

| Campo | Quando usar |
|---|---|
| `drive_nome` | Pasta no Drive tem nome diferente do ClickUp. |
| `drive_pasta_ano_id` | Estrutura de pastas NÃO bate em `Clientes/<cli>/Cronograma/Artes/<ano>`. |
| `clickup_alias` | Tarefa-mãe no ClickUp tem nome diferente da pasta local. |

Clientes sem entrada usam a hierarquia padrão automaticamente.

### 5.3 Convenção de pasta-raiz (obrigatória)

```
<videoRoot>\
└── <Cliente>\
    └── <DD-MM-YYYY>\
        ├── reels-01.mp4
        ├── reels-01.png
        └── ...
```

- **Cliente** = pasta-pai (deve bater com nome no ClickUp/Drive — normalização cuida de acentos e abreviações).
- **Data** = subpasta `DD-MM-YYYY` (fallback: mtime do arquivo).
- **Par** = mesmo nome-raiz na mesma pasta.

### 5.4 Hierarquia destino no Drive

**Modo padrão:**
```
Clientes/<drive_nome OR cliente>/Cronograma de Conteudo/Artes/<ano>/<mes-extenso>/<DD-MM-YYYY>/
```

**Modo override (cliente com `drive_pasta_ano_id`):**
```
<startFolderId>/<MM. mes-extenso>/<DD-MM-YYYY>/
```

A pasta-âncora (`Clientes/<drive_nome>/` ou `<startFolderId>`) é assumida como **preexistente** — falha clara se não existir, não cria no raiz. Subpastas intermediárias (Cronograma, Artes, ano, mês, data) são criadas sob demanda via `rclone mkdir`.

## 6. Dependências externas

### 6.1 rclone (obrigatório a partir da v1.2)

**Por quê:** o MCP do Google Drive rejeita uploads > 10MB. Vídeos editados quase sempre passam disso. A skill usa `rclone copyto` pra ignorar o cap.

| SO | Como instalar |
|---|---|
| Windows | `winget install Rclone.Rclone` (ou Chocolatey, ou manual + PATH) |
| macOS | `brew install rclone` |
| Linux | `curl https://rclone.org/install.sh \| sudo bash` |

O onboarding (etapa 6 em [onboarding.md](squads/video-export/tasks/onboarding.md)) detecta, instala e configura o remote `gdrive:` interativamente. Credenciais do rclone ficam em `%APPDATA%\rclone\rclone.conf`.

**Pré-flight automático** antes de cada upload:
1. `Get-Command rclone` retorna caminho?
2. `rclone listremotes` contém o remote da config?
3. `rclone config show <remote>` tem `type = drive`?

Qualquer falha → aborta com mensagem pedindo `/video-export --setup-rclone`.

### 6.2 MCPs

| MCP | Pra quê | Quem usa |
|---|---|---|
| **ClickUp** | `clickup_get_task`, `clickup_search`, `clickup_filter_tasks`, `clickup_create_task_comment`, `clickup_update_task`, `clickup_resolve_assignees` | Match (read-only) + Noti (write) |
| **Google Drive** | `google_drive_list_files`, `google_drive_get_file_metadata` — só leitura, pra resolver `webViewLink` e IDs pós-upload | Uploader (após `rclone copyto`) |

Tokens OAuth dos MCPs ficam em `~/.claude/`. Se algum cair, basta pedir reauth na conversa.

## 7. Regras críticas (NÃO violar)

### 7.1 FR31 — Sequencial obrigatório no Noti

**NUNCA execute `clickup_create_task_comment` + `clickup_update_task` em paralelo na mesma subtarefa.** Quando os dois rodam em paralelo, o ClickUp **dropa o comentário silenciosamente** (200 OK na API, mas o comentário não aparece).

Ordem correta:
```
1. create_task_comment   → await → confirma comment_id
2. update_task (status)  → await → confirma status
```

### 7.2 Normalização de cliente (FR19a)

Antes de qualquer comparação Match faz:
1. Remove pontos de abreviação: `Dr.` → `Dr`, `Dra.` → `Dra`
2. Lowercase
3. Remove acentos: `Taíssa` → `taissa`
4. Colapsa whitespace e trim

Sem isso, `"Dr."` na pasta e `"Dr"` no ClickUp viram pares diferentes.

### 7.3 Mismatch silencioso proibido (FR25a)

Se `drive_nome` está no `clientes.yaml` mas a pasta correspondente não existe no Drive, **falha** — não tenta cair pro `cliente` original.

### 7.4 Pasta-âncora preexistente (FR21)

A skill **NÃO cria** `Clientes/<cliente>/` nem `<startFolderId>`. Assume existência. Se não existir, erro claro pro editor criar manualmente.

### 7.5 Match é read-only

Match nunca cria task no ClickUp. Sem subtarefa encontrada → vai pra pendências, não infere.

### 7.6 Falha parcial não aborta o lote

Erro em um par individual nunca aborta os outros. Vai pra `pendências` no relatório final.

## 8. Como o sistema acessa seu computador

| Recurso | Local | Quem mexe |
|---|---|---|
| Vídeos editados | `videoRoot` (default `D:\Edicoes`) | Scanner (read), Uploader (read) |
| Config local | `%USERPROFILE%\.stark-video-export\config.json` | Eve (read/write) |
| Logs de execução | `%USERPROFILE%\.stark-video-export\logs\` | Eve (write) |
| Credenciais rclone | `%APPDATA%\rclone\rclone.conf` | rclone (gerenciado pelo `rclone config`) |
| Tokens MCP | `~/.claude/` | Gerenciado pelo Claude Code |

**Permissões declaradas** no frontmatter desse slash:
- `Read`, `Write`, `Edit`, `Glob` — manipulação de arquivos.
- `PowerShell`, `Bash` — shell pra rclone, mtime, etc.
- `mcp__*__clickup_*` — todas as tools do ClickUp MCP.
- `mcp__*__google_drive*` — todas as tools do Drive MCP.

## 9. Troubleshooting rápido

| Sintoma | Provável causa | O que fazer |
|---|---|---|
| `rclone não detectado` | Binário fora do PATH | `/video-export --setup-rclone` |
| `remote 'gdrive:' não enxerga 'Clientes/'` | Logado com Google errado | `rclone config reconnect gdrive:` |
| `subtarefa não encontrada` | Nome da pasta diferente do ClickUp | Adicionar `clickup_alias` em `clientes.yaml` |
| Comentário sumiu mas status mudou | Violou FR31 (paralelo) | Bug — abrir issue, Noti deve sempre ser sequencial |
| Upload trava em arquivo grande | Sem usar rclone (cap de 10MB do MCP) | Verificar `transport: "rclone"` no output do Up |
| `pasta 'Clientes/<cliente>/' não existe` | Pasta-âncora não criada manualmente | Criar no Drive ou adicionar `drive_nome`/`drive_pasta_ano_id` no YAML |

## 10. Referência interna

- [README do squad](squads/video-export/README.md)
- [PRD completo](squads/video-export/docs/PRD.md) — todos os FRs
- [squad.yaml](squads/video-export/squad.yaml) — metadata, MCPs requeridos, ferramentas externas
- [Onboarding detalhado](squads/video-export/tasks/onboarding.md) — etapa 6 (rclone) inclusive
- Tasks: [scan-pasta](squads/video-export/tasks/scan-pasta.md), [upload-drive](squads/video-export/tasks/upload-drive.md), [notificar-clickup](squads/video-export/tasks/notificar-clickup.md)
