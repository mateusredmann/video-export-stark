# video-export-stark — Agents

Pipeline de 5 agentes que entrega vídeos editados ao cliente via Drive + ClickUp.

## Cadeia de execução

```
[Eve export-chief]
   │  valida flags, carrega/cria config do editor
   │
[Scan scanner]
   │  varre pasta-raiz, descobre pares (video, capa, cliente, data)
   │
[Match matcher] ─── em paralelo (3-4 simultâneos por par)
   │  busca subtarefa ClickUp por cliente+data
   │
[Up uploader] ──── em paralelo (3-4 simultâneos por par)
   │  cria pasta no Drive, sobe vídeo + capa
   │
[Noti notifier]
      comenta link no ClickUp, @responsável, status = edição concluída
```

Falha em um par não aborta os demais — agrega no relatório final.

## Pontos não-óbvios

- **Cliente** vem **sempre** do nome da pasta-pai. Match normaliza removendo `Dr.`/`Dra.`, lowercase e acentos antes de comparar com ClickUp. Se ainda assim não acha, vai pra pendências.
- **Data** prefere o nome da subpasta no formato `DD-MM-YYYY`. Fallback: `mtime` do arquivo de vídeo.
- **Par vídeo+capa** = mesmo nome-raiz (`reels-01.mp4` + `reels-01.png`). Arquivos órfãos (vídeo sem capa ou capa sem vídeo) entram nas pendências.
- **Status final fixo:** `edição concluída`. Não é configurável via onboarding.
- **Cache do editor:** `%USERPROFILE%\.stark-video-export\config.json`. Para reconfigurar, usar `--reconfigure`.
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
