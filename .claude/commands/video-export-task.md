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

Variante "alvo único" do `/video-export`. Em vez de varrer `videoRoot` por data e processar todos os pares, você aponta pra uma entrega específica de três formas possíveis:

1. **task_id** (`8gqkmtp`) — pipeline reverso: ClickUp → filesystem.
2. **URL do ClickUp** (`https://app.clickup.com/t/8gqkmtp`) — idem.
3. **Caminho local da pasta** (`D:\Stark MKT\02 - Videos\2026\2026 - Junho\16-06 Janete`) — pipeline direto curto: filesystem → ClickUp, mas só pra essa pasta (sem varrer `videoRoot`).

Útil quando:

- Você quer refazer uma entrega que já saiu (com `--force`).
- O cliente liberou uma edição atrasada e a varredura por `--hoje`/`--semana` não pegaria.
- Você quer subir só um item específico, mesmo tendo várias coisas na pasta do dia.
- Você já está com a pasta do entregável aberta e prefere arrastar o caminho pro chat em vez de caçar o task_id.

## Args

`$ARGUMENTS` aceita:

- **`<alvo>`** posicional — obrigatório. Pode ser:
  - `task_id` (ex.: `8gqkmtp`) — Eve detecta por regex `^[a-z0-9]+$`.
  - URL `https://app.clickup.com/t/<task_id>` — Eve extrai o segmento `/t/<id>`.
  - Caminho de pasta local (ex.: `D:\Stark MKT\02 - Videos\2026\2026 - Junho\16-06 Janete` ou `"/d/Stark MKT/..."`) — Eve detecta por `Test-Path` + presença de separadores `\` ou `/` no início (drive letter, UNC ou raiz POSIX).
- `--nome-raiz "reels-01"` — opcional. Quando a pasta tem múltiplos pares, restringe ao nome-raiz indicado (sem extensão). Sem isso, Eve avisa se achar > 1 par.
- `--force` — sobrescreve no Drive se o arquivo já existir com tamanho diferente.
- `--dry-run` — mostra preview do comentário e do `rclone copyto` previsto, sem executar.

## Pipeline — modo `task_id` / URL (reverso)

```
1. Eve carrega config.json (dispara onboarding completo se ausente; etapa 6 se v1)
1b. Pré-flight rclone (Get-Command + listremotes + tipo drive)
2. Eve parseia <task_id> ou URL → task_id limpo
3. Match (read-only):
     a. clickup_get_task(task_id) → name, status, parent, list_id
     b. Extrai cliente:
        - 1ª tentativa: nome do path da lista/folder (lista pai do parent)
        - 2ª tentativa: clickup_get_task(parent) → name, e procura cliente em config/clientes.yaml por substring
        - 3ª tentativa: regex no nome da subtarefa por nome conhecido
     c. Extrai data da subtarefa: regex DD-MM, DD/MM, DD-MM-YYYY, DD-MM-AA
        - Sem data no nome → pega due_date da subtarefa → formata DD-MM-YYYY
        - Sem data nem due_date → erro, pede confirmação manual
     d. clickup_get_task(parent_task_id) → parent_assignees pra @-mention
4. Scan dirigido:
     a. Constrói pasta esperada via folderPattern do config.json
     b. Se existe: lista pares (video + capa por nome-raiz)
     c. Se NÃO existe: tenta variações
        - sem ano, busca por mtime do dia, varia pontuação ("Dr." vs "Dr")
     d. Falhou tudo → erro com lista de candidatos próximos pro editor escolher
5. Filtragem por --nome-raiz (se passado) → 1 par único
     - Sem flag e > 1 par na pasta → Eve pergunta qual usar (lista nome-raiz)
6. Up (rclone copyto): vídeo + capa → pasta-destino no Drive (mesma hierarquia do /video-export)
7. Drive MCP: resolve webViewLink da pasta-destino + IDs
8. Noti: comenta na subtask_id (NÃO na parent!) + @mention parent_assignees + status="edição concluída"
9. Eve: relatório final (1 par só, mas mantém o mesmo formato pra log)
```

## Pipeline — modo `caminho_pasta` (direto curto)

```
1. Eve carrega config.json (idem reverso)
1b. Pré-flight rclone (idem)
2. Eve detecta que o argumento é PATH (Test-Path + heurística de separador) e normaliza pra absoluto
3. Scan local — UMA pasta só:
     a. Lista <pasta>/*<videoExt> e <pasta>/*<capaExt>
     b. Pareia por nome-raiz (igual ao /video-export, mas escopo = pasta única)
     c. Sem nenhum vídeo → erro fatal ("pasta vazia / sem .mp4")
     d. > 1 par e sem --nome-raiz → pergunta interativamente qual usar
4. Extração de cliente+data — primeira evidência que casar:
     a. Nome do arquivo de vídeo (ex.: "16-06 Janete.mp4")
     b. Nome da pasta (ex.: "16-06 Janete")
     c. Caminho ascendente — pasta-mes ("2026 - Junho") + pasta-ano ("2026") preenchem MM/YYYY quando o nome só traz DD
     Regex aceitas pra data: DD[-/.]MM[-/.](YYYY|YY) | DD[-/.]MM (assume YYYY do path ou ano corrente)
     Cliente = string restante depois de remover token de data + extensão (trim e collapse de espaços)
     Falha → erro fatal "não consegui extrair cliente/data — renomeie o arquivo no padrão 'DD-MM Cliente.mp4' ou passe --task-id"
5. Match direto (forward) — IGUAL ao /video-export normal:
     a. Normaliza cliente (remove "Dr."/"Dra.", lowercase, sem acento)
     b. Aplica clickup_alias do config/clientes.yaml se existir
     c. clickup_search "<cliente_normalizado> <DD-MM>" + ranking
     d. 0 matches → erro fatal pedindo confirmação manual
     e. > 1 match empatado → pergunta qual usar (lista subtask_id + name)
     f. clickup_get_task(parent.id) → parent_assignees pra @-mention
6. Up (rclone copyto): vídeo + capa → pasta-destino no Drive
7. Drive MCP: resolve webViewLink + IDs
8. Noti: comenta na subtask_id + @mention parent_assignees + status="edição concluída"
9. Eve: relatório final
```

## Detecção de tipo do argumento

Ordem (primeira que casar ganha):

1. Começa com `/t/` ou contém `clickup.com/t/` → URL → extrai task_id pelo regex `/t/([a-z0-9]+)`
2. Começa com letra-de-drive (`^[A-Za-z]:[\\/]`), UNC (`^\\\\`), POSIX absoluto (`^/[a-z]/` no Git Bash) OU contém separador `\` ou `/` E `Test-Path` retorna `True` em pasta → **modo path**
3. Casa `^[a-zA-Z0-9]+$` (alfanumérico curto, sem barras) → task_id literal
4. Nenhum dos anteriores → erro: "não entendi `<alvo>` — esperado task_id, URL `/t/<id>` ou caminho de pasta existente"

> ⚠️ Se a pessoa colar um caminho que **não existe**, Eve NÃO degrada pra task_id silenciosamente — devolve "caminho não encontrado: …" e lista as 5 entradas mais próximas em `videoRoot`.

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
/video-export-task "D:\Stark MKT\02 - Videos\2026\2026 - Junho\16-06 Janete" --force
/video-export-task "D:\Stark MKT\02 - Videos\2026\2026 - Junho\16-06 Janete" --nome-raiz "reels-02"
```

## Diferenças críticas vs `/video-export`

| Aspecto                        | `/video-export`                          | `/video-export-task` (reverso)                      | `/video-export-task` (path)                          |
|--------------------------------|------------------------------------------|------------------------------------------------------|------------------------------------------------------|
| Ponto de partida               | `videoRoot` (filesystem)                 | `task_id` (ClickUp)                                  | pasta local específica (filesystem)                  |
| Match                          | cliente+data → busca subtarefa           | subtarefa → deriva cliente+data                      | cliente+data extraídos do nome do arquivo → busca    |
| Quantos pares                  | 1..N                                     | exatamente 1                                         | exatamente 1 (ou prompt se > 1)                      |
| Cliente não extraído           | par vai pra pendências                   | erro fatal — pede confirmação manual                 | erro fatal — pede rename ou `--task-id`              |
| Pasta-data não existe          | par vai pra pendências                   | tenta variações + lista candidatos                   | n/a — a pasta JÁ é o input                           |
| Múltiplos pares na pasta-data  | processa todos                           | exige `--nome-raiz` OU pergunta interativamente      | exige `--nome-raiz` OU pergunta interativamente      |

## Quando NÃO usar

- Quer subir tudo do dia → use `/video-export --hoje`.
- Quer subir tudo da semana → use `/video-export --semana`.
- Não tem o task_id E não tem o caminho da pasta → use `/video-export` normal (varre tudo).

## Regras

- **Comentário vai na subtask_id resolvida**, não na tarefa-mãe (mesmo que o `cliente` venha da mãe).
- **@-mention** continua sendo do `parent.assignees` (responsável "real" da entrega), não da subtarefa.
- **Sequencial obrigatório** (FR31): comentário → await → status. Igual ao `/video-export`.
- **Idempotência**: sem `--force`, se o vídeo já está no Drive com tamanho idêntico, vira `skipped` + posta o comentário do mesmo jeito (o link é o objetivo).

## Referência

- [Workflow detalhado](../../squads/video-export/workflows/export-task.md)
- [Agente Match](../../squads/video-export/agents/matcher.md) — modo "reverse lookup"
- [SKILL.md seção 2](../skills/video-export/SKILL.md) — lista canônica de comandos
