---
description: "Entrega UMA subtarefa específica do ClickUp (por ID ou URL). Pula a varredura por data — você diz qual é a tarefa, a skill resolve o resto."
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - PowerShell
  - Bash
  - mcp__*__clickup_*
  - mcp__*__google_drive*
argument-hint: "<task_id_ou_url> [--force] [--dry-run] [--nome-raiz \"reels-01\"]"
---

# /video-export-task

Variante "alvo único" do `/video-export`. Em vez de varrer `videoRoot` por data e processar todos os pares, você passa o ID (ou URL) de uma subtarefa do ClickUp e a skill entrega só ela. Útil quando:

- Você quer refazer uma entrega que já saiu (com `--force`).
- O cliente liberou uma edição atrasada e a varredura por `--hoje`/`--semana` não pegaria.
- Você quer subir só um item específico, mesmo tendo várias coisas na pasta do dia.

## Args

`$ARGUMENTS` aceita:

- **`<task_id>`** posicional — obrigatório. Aceita formato `8gqkmtp` ou URL completa `https://app.clickup.com/t/8gqkmtp` (Eve faz parsing do segmento `/t/<id>`).
- `--nome-raiz "reels-01"` — opcional. Quando a pasta-data tem múltiplos pares, restringe ao nome-raiz indicado (sem extensão). Sem isso, Eve avisa se achar > 1 par.
- `--force` — sobrescreve no Drive se o arquivo já existir com tamanho diferente.
- `--dry-run` — mostra preview do comentário e do `rclone copyto` previsto, sem executar.

## Pipeline (diferente do `/video-export`)

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
     a. Constrói pasta esperada: <videoRoot>\<cliente>\<DD-MM-YYYY>\
     b. Se existe: lista pares (video + capa por nome-raiz)
     c. Se NÃO existe: tenta variações
        - <videoRoot>\<cliente>\<DD-MM-YYYY-curto>\  (sem ano)
        - busca por mtime do dia da data extraída em <videoRoot>\<cliente>\*\
        - varia pontuação: "Dr." vs "Dr" no nome do cliente
     d. Falhou tudo → erro com lista de candidatos próximos pro editor escolher
5. Filtragem por --nome-raiz (se passado) → 1 par único
     - Sem flag e > 1 par na pasta → Eve pergunta qual usar (lista nome-raiz)
6. Up (rclone copyto): vídeo + capa → pasta-destino no Drive (mesma hierarquia do /video-export)
7. Drive MCP: resolve webViewLink da pasta-destino + IDs
8. Noti: comenta na subtask_id (NÃO na parent!) + @mention parent_assignees + status="edição concluída"
9. Eve: relatório final (1 par só, mas mantém o mesmo formato pra log)
```

## Exemplos

```
/video-export-task 8gqkmtp
/video-export-task https://app.clickup.com/t/8gqkmtp
/video-export-task 8gqkmtp --nome-raiz "reels-02"
/video-export-task 8gqkmtp --force
/video-export-task 8gqkmtp --dry-run
```

## Diferenças críticas vs `/video-export`

| Aspecto                        | `/video-export`                          | `/video-export-task`                                |
|--------------------------------|------------------------------------------|------------------------------------------------------|
| Ponto de partida               | `videoRoot` (filesystem)                  | `task_id` (ClickUp)                                  |
| Match                          | cliente+data → busca subtarefa           | subtarefa → deriva cliente+data                      |
| Quantos pares                  | 1..N                                     | exatamente 1                                         |
| Cliente não encontrado         | par vai pra pendências                   | erro fatal — pede confirmação manual                 |
| Pasta-data não existe          | par vai pra pendências                   | tenta variações + lista candidatos pro editor escolher |
| Múltiplos pares na pasta-data  | processa todos                           | exige `--nome-raiz` OU pergunta interativamente      |

## Quando NÃO usar

- Quer subir tudo do dia → use `/video-export --hoje`.
- Quer subir tudo da semana → use `/video-export --semana`.
- Não tem o task_id em mãos → use `/video-export` normal.

## Regras

- **Comentário vai na subtask_id resolvida**, não na tarefa-mãe (mesmo que o `cliente` venha da mãe).
- **@-mention** continua sendo do `parent.assignees` (responsável "real" da entrega), não da subtarefa.
- **Sequencial obrigatório** (FR31): comentário → await → status. Igual ao `/video-export`.
- **Idempotência**: sem `--force`, se o vídeo já está no Drive com tamanho idêntico, vira `skipped` + posta o comentário do mesmo jeito (o link é o objetivo).

## Referência

- [Workflow detalhado](../../squads/video-export/workflows/export-task.md)
- [Agente Match](../../squads/video-export/agents/matcher.md) — modo "reverse lookup"
- [SKILL.md seção 2](../skills/video-export/SKILL.md) — lista canônica de comandos
