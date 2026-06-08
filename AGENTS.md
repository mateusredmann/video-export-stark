# video-export-stark — Agents

Pipeline de 5 agentes que entrega vídeos editados ao cliente via Drive + ClickUp.

## Cadeia de execução — modo varredura (`/video-export`)

```
[Eve export-chief]
   │  valida flags, carrega/cria config do editor, pré-flight do rclone
   │
[Scan scanner]
   │  varre pasta-raiz, descobre pares (video, capa, cliente, data)
   │
[Match matcher] ─── em paralelo (3-4 simultâneos por par)
   │  busca subtarefa ClickUp por cliente+data
   │
[Up uploader] ──── em paralelo (3-4 simultâneos por par)
   │  rclone copyto vídeo + capa → Drive (sem cap de 10MB)
   │
[Noti notifier]
      comenta link no ClickUp, @responsável, status = edição concluída
```

## Cadeia de execução — modo alvo único (`/video-export-task <id>`)

```
[Eve]   carrega config + pré-flight rclone + parseia task_id
   │
[Match em modo REVERSO]  clickup_get_task(id) → deriva cliente + data + parent_assignees
   │
[Scan dirigido]  procura pasta-data esperada (+ fallbacks) → 1 par filtrado
   │
[Up rclone]  upload do par único
   │
[Noti]  comenta na subtask + @ + status (sequencial FR31)
```

Falha em um par não aborta os demais — agrega no relatório final.

## Pontos não-óbvios

- **Cliente** vem **sempre** do nome da pasta-pai. Match normaliza removendo `Dr.`/`Dra.`, lowercase e acentos antes de comparar com ClickUp. Se ainda assim não acha, vai pra pendências.
- **Data** prefere o nome da subpasta no formato `DD-MM-YYYY`. Fallback: `mtime` do arquivo de vídeo.
- **Par vídeo+capa** = mesmo nome-raiz (`reels-01.mp4` + `reels-01.png`). Arquivos órfãos (vídeo sem capa ou capa sem vídeo) entram nas pendências.
- **Status final fixo:** `edição concluída`. Não é configurável via onboarding.
- **Cache do editor:** `%USERPROFILE%\.stark-video-export\config.json` (schema v3 inclui `rcloneRemote` + `rcloneTeamDriveId`). Para reconfigurar tudo, `--reconfigure`; só rclone, `--setup-rclone`. Configs v1→v2 e v2→v3 ganham migração silenciosa na próxima execução.
- **rclone obrigatório a partir da v1.2.** O MCP do Google Drive rejeita uploads > 10MB e vídeos editados quase sempre passam disso. Up usa `rclone copyto` — Drive MCP só é usado pós-upload pra resolver `webViewLink`/IDs.
- **Drive Compartilhado (v1.3).** Todo comando rclone roda com `--drive-team-drive 0ABl2cpta6dNRUk9PVA` (`config.rcloneTeamDriveId`) pra mirar o shared drive da Stark, não o "Meu Drive" pessoal. Só sobe pra cliente com pasta oficial lá; senão pendência, nunca cria a raiz.
- **Modo reverso do Match** (`/video-export-task <id>`): a partir do `task_id` da subtarefa, Match deriva cliente (folder/list → parent name → regex no subtask.name) e data (regex no nome → `due_date`). Falha → erro fatal com candidatos, nunca infere.
- **Overrides por cliente:** `squads/video-export/config/clientes.yaml` mapeia clientes que têm `drive_nome` ou `drive_pasta_ano_id` diferente do padrão. Importado do prep-agenda-stark — manter sincronizado.
- **Idempotência:** se a pasta no Drive já tem o arquivo, pula. Com `--force`, sobrescreve.

## ⚠️ Regra crítica — sequencial obrigatório no ClickUp

Noti NUNCA chama `clickup_create_task_comment` e `clickup_update_task` em paralelo. O ClickUp dropa o comentário silenciosamente quando os dois competem na mesma subtarefa. Ordem: comentário primeiro (await + confirma `comment_id`), depois status.

## Template de comentário (padrão Stark)

```
[@responsável] ✅ Edição concluída.
Ref: <cliente> — <DD-MM> <nome_raiz>
Entregue: vídeo (.mp4) + capa (.png)

🔗 Drive: <drive_folder_url>
```
