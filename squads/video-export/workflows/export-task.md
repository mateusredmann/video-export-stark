---
name: export-task
trigger: "/video-export-task <task_id|url|caminho_pasta> [--force] [--dry-run] [--nome-raiz <root>]"
---

# Workflow: Export Task (alvo único)

Entrega UMA subtarefa do ClickUp. Dois modos de entrada:

- **Reverso** (`task_id` / URL) — ClickUp → filesystem.
- **Path** (caminho de pasta local) — filesystem → ClickUp, restrito a 1 pasta.

Detecção do tipo de argumento + algoritmos de parse documentados em [`.claude/commands/video-export-task.md`](../../../.claude/commands/video-export-task.md). Aqui ficam os detalhes do pipeline.

## Pipeline — modo reverso

```
1. Eve: config + migrações + pré-flight rclone + parseia <task_id> ou /t/<id>
2. Match reverso:
     a. clickup_get_task(task_id) → subtask (name, status, parent, list, folder, due_date)
     b. Extrai cliente — primeira que casar:
          • folder.name OU list.name contém cliente do clientes.yaml (substring normalizada case-insensitive)
          • clickup_get_task(parent.id).name contém cliente conhecido
          • regex no subtask.name
          • Falha → erro fatal com top-5 clientes mais próximos (levenshtein vs folder.name)
     c. Extrai data — primeira que casar:
          • regex no subtask.name: DD-MM-YYYY > DD-MM-AA (expande 26→2026) > DD-MM (assume ano corrente)
          • subtask.due_date (timestamp ms) → DD-MM-YYYY
          • parent.due_date
          • Falha → erro fatal pedindo correção da subtarefa
     d. clickup_get_task(parent).assignees → parent_assignees pra @-mention
3. Scan dirigido (candidatos em ordem):
     a. <videoRoot>\<ano>\<ano> - <Mês>\<DD-MM> <cliente>           (estrutura canônica)
     b. <videoRoot>\<ano>\<ano> - <Mês>\<DD-MM>  <cliente>          (dois espaços — variante observada)
     c. Variações pontuação: "Dr. " ↔ "Dr " ↔ "" no cliente
     d. Fallback: glob <videoRoot>\<ano>\<ano> - <Mês>\* e filtra por regex DD-MM + cliente normalizado
     Primeiro Test-Path positivo ganha. Nenhum + fallback vazio → erro listando candidatos.
4. Filtragem: --nome-raiz OU prompt interativo se >1 par.
5. Up (rclone copyto, com <TD>): vídeo + capa.
6. Drive MCP: webViewLink + IDs.
7. Noti: comenta na subtask_id + @parent_assignees + status (FR31 sequencial).
8. Eve: relatório (1 par).
```

## Pipeline — modo path

```
1. Eve: config + migrações + pré-flight rclone + normaliza path pra absoluto.
2. Scan local na pasta única:
     a. Get-ChildItem <pasta>\*<videoExt> e <pasta>\*<capaExt>
     b. Pareia por nome-raiz (basename sem extensão)
     c. 0 vídeos → erro "pasta vazia / sem .mp4"
     d. >1 par sem --nome-raiz → prompt interativo
3. Extração cliente+data (fontes em ordem):
     a. filename do vídeo escolhido (ex.: "16-06 Janete.mp4")
     b. nome da pasta (ex.: "16-06 Janete")
     c. caminho ascendente — mes/ano de pasta-mes ("2026 - Junho") e pasta-ano ("2026")
   Regex (em ordem): DD[-/.]MM[-/.](\d{4}) → DD-MM-YYYY | DD[-/.]MM[-/.](\d{2}) → DD-MM-AA (expande) | DD[-/.]MM → DD-MM (ano do path; fallback corrente).
   Cliente = fonte com token de data + extensão removidos, whitespace colapsado.
   Falha → erro fatal "renomeie como 'DD-MM Cliente.mp4' ou passe --task-id".
4. Match forward (igual ao /video-export):
     a. normalize(cliente) + aplica clickup_alias do clientes.yaml
     b. clickup_search "<cliente_norm> <DD-MM>" + ranking
     c. 0 matches → erro fatal sugerindo top-5 mais próximos
     d. >1 empate → prompt interativo (subtask_id + parent.name)
     e. clickup_get_task(parent).assignees → parent_assignees
5-8. Up → Drive MCP → Noti sequencial → relatório (igual ao reverso).
```

## Edge cases

- **task_id é tarefa-mãe** (modo reverso) → erro "esse é o ID da mãe. Subtarefas: …" + lista pro editor escolher.
- **Subtarefa já marcada `edição concluída`** → confirma antes de re-postar, a menos que `--force`.
- **Path não existe** → erro "caminho não encontrado: …" + 5 entradas mais próximas em `videoRoot`. NÃO degrada pra task_id silenciosamente.
- **Path é arquivo (não pasta)** → trata como pasta-pai do arquivo. Útil quando o editor arrasta o `.mp4` direto.
- **Cliente extraído ambíguo no ClickUp** (ex.: "Felipe" bate em 2 doutores) → prompt interativo lista candidatos (`subtask_id + parent.name`).
- **Ano ausente no path/nome** → assume `datetime.now().year` com `WARN: ano inferido = 2026`.
- **Cliente normalizado sem match no ClickUp** → erro fatal "cliente '<x>' não encontrado nas subtarefas com data <DD-MM>"; sugere top-5 levenshtein vs `parent.name` da semana.
- **Cliente está no `clientes.yaml` com `clickup_alias`** → usa o alias na busca ClickUp. Pasta local continua usando o nome extraído pelo Scanner (`<cliente>` literal).
- **Override `drive_pasta_reels_id`** → resolve caminho humano via `google_drive_get_file_metadata` ou usa `--drive-root-folder-id <id>` no rclone (sempre com `<TD>`). Subpath renderizado a partir de `drive_reels_subpath_template`.
- **Override `drive_pasta_ano_id` (legado)** → ignorado pelo Uploader nesta skill. Era pra artes estáticas no `prep-agenda-stark`.
