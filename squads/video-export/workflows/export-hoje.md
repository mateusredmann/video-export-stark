---
name: export-hoje
trigger: "/video-export --hoje  (ou /video-export sozinho após onboarding)"
---

# Workflow: Export Hoje

Default pós-onboarding. Sobe o que precisa sair hoje: tudo que o editor fechou hoje no PC **e** tudo que vence hoje no ClickUp — independente do nome da pasta.

> ⚠️ **Não filtra pela data da pasta-local.** Pasta `13-06-2026` editada hoje (10-06) entra. Pasta `10-06-2026` parada há 3 dias **não** entra. O nome da pasta só serve pra descobrir cliente+data do par; o gatilho do lote é mtime / due_date.

## Fontes do lote

Eve monta o lote unindo duas fontes — qualquer par que aparecer em pelo menos uma entra:

1. **PC do editor (mtime=hoje):** Scan modo `hoje` varre `<videoRoot>` inteiro filtrando arquivos com `LastWriteTime` entre `hoje 00:00` e `hoje 23:59` (timezone local, sem timezone gymnastics). Cliente+data = extraídos do nome da pasta-alvo (`<DD-MM> <Cliente>`). Ano vem da pasta-avó (`<ano> - <Mês>`). Variantes `-SEM.mp4` são silenciosamente descartadas. Capa é opcional.

2. **ClickUp (due_date=hoje, assignee=editorEmail):** Match modo reverso lista subtarefas com `due_date` no dia local de hoje atribuídas ao `editorEmail` do `config.json`. Pra cada uma deriva `cliente_derivado` + `data_derivada` (regras em [matcher.md](../agents/matcher.md) §"Modo reverso").

**Dedup** por `(cliente_normalizado, data, nome_raiz)` quando o par cai nas duas fontes. Origem registrada no relatório (`fs`, `clickup`, `ambos`).

## Pipeline

```
1. Eve carrega config.json + pré-flight rclone
2. Em paralelo:
   ├─ Scan modo "hoje" (mtime=hoje no <videoRoot>)
   └─ Match modo reverso em batch:
       clickup_filter_tasks { due_date_gt: hoje 00:00, due_date_lt: hoje 23:59, assignees:[editor] }
       → pra cada subtask → deriva cliente+data
3. Eve une os dois conjuntos, deduplica por (cliente, data, nome_raiz)
4. Pra cada par:
   - veio do FS sem subtask casada → Match forward normal
   - veio do ClickUp → confirma arquivo no PC (mesmo cliente+data, qualquer mtime)
   - sem arquivo no PC → pendência "tarefa vence hoje, sem vídeo editado"
   - sem subtask no ClickUp → pendência "vídeo editado hoje, sem subtarefa"
5. Up + Noti em lotes de 4 (data Drive = data da pasta-local do par, NÃO due_date nem hoje)
6. Eve consolida relatório com origem por par
```

## Regras

- **Data no Drive = data extraída da pasta-local.** Vídeo editado hoje numa pasta `13-06 Diego Gonzalez` (sob `2026 - Junho`) sobe em `…/13-06-2026/` no Drive. Se a tarefa do ClickUp vence dia 13 mas o arquivo está em `10-06 Diego Gonzalez`, sobe em `10-06-2026`.
- **Pasta-avó sem ano (`<ano> - <Mês>`):** fallback ano do `mtime` do vídeo.
- **Tarefa ClickUp vence hoje mas sem arquivo:** pendência `clickup_sem_arquivo` — Eve mostra o `task_id` + cliente derivado pra editor checar.
- **Arquivo editado hoje mas sem subtarefa:** pendência `fs_sem_subtask` — passa pelo Match forward normal antes de virar pendência (pode encontrar uma com `clickup_search`).
- **`editorEmail` ausente no config:** aborta pedindo `/video-export --reconfigure`.

## Fora do escopo deste workflow

- Editor que virou a noite e quer subir vídeos de ontem → `/video-export --semana` ou `/video-export "<pasta>"`.
- Subir vídeo de uma tarefa específica sem depender de data → `/video-export-task <task_id|URL|caminho>`.
