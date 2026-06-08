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
version: 1.2.0
author: stark.marketing
license: UNLICENSED
tags:
  - video
  - delivery
  - clickup
  - google-drive
  - rclone
  - stark
mcps_required:
  - clickup
  - google-drive
external_tools_required:
  - rclone   # upload de vídeo > 10MB (Drive MCP não suporta)
platforms:
  - claude-code
  - cowork
  - portable-llm
---

# Video Export — Skill

Squad de 5 agentes (Eve, Scan, Match, Up, Noti) que automatiza o último passo da produção: depois que o editor terminou um lote, esta skill faz a entrega ao cliente. Lê pasta local → sobe pro Drive → comenta link na subtarefa do ClickUp → muda status.

> Esta SKILL.md é **autocontida**. Funciona idêntico em Claude Code, Cowork e em qualquer LLM que aceite system prompt longo (ChatGPT, Gemini, Grok). Ferramentas com prefixo `mcp__` são substituíveis por chamadas equivalentes da API do ClickUp e Google Drive quando o MCP não estiver disponível.

---

## 1. Quando acionar

Acione esta skill quando o usuário pedir qualquer variação de entrega final de vídeo editado:

- "sobe os vídeos editados de hoje"
- "manda os reels do Dr. X pro Drive"
- "fecha a semana de edição"
- "/video-export …"
- "entrega da [data] do [cliente]"
- "joga os vídeos editados no Drive e comenta no ClickUp"

**NÃO acionar para:**
- Edição/corte/efeitos do vídeo (use ferramenta de edição local)
- Geração ou ajuste de capa (use `stark-av-renderer` ou `entrega-reels-drive-clickup`)
- Upload de arte estática a partir do Figma (use `figma-export-para-drive`)

---

## 2. Comandos suportados

```
/video-export                             # 1ª vez: onboarding. Depois: --hoje
/video-export --hoje                      # vídeos com data = hoje
/video-export --semana                    # segunda-sexta da semana corrente
/video-export "D:\Edicoes\Dr. X\27-05"    # pasta específica
/video-export --cliente "Dr. Rodolfo"     # filtra por nome da pasta-pai
/video-export --force                     # sobrescreve no Drive
/video-export --reconfigure               # reabre o onboarding completo
/video-export --setup-rclone              # roda só a etapa 6 do onboarding
/video-export --dry-run                   # mostra o que faria, sem subir
/video-export-task <task_id_ou_url>       # entrega só essa subtarefa do ClickUp
```

Flags podem combinar: `/video-export --semana --cliente "Dr. Felipe" --dry-run`.

> 📌 **`/video-export-task`** é um slash command separado documentado em [`.claude/commands/video-export-task.md`](../../../.claude/commands/video-export-task.md). Pula a varredura por data e processa exatamente uma subtarefa específica — útil pra refazer um item ou subir uma entrega que ficou pra trás.

---

## 3. Onboarding (1ª execução)

Se `%USERPROFILE%\.stark-video-export\config.json` não existe (ou `--reconfigure` foi passado), perguntar uma por vez:

1. **Email no ClickUp** (precisa conter `@`; oferecer autocomplete via `clickup_get_workspace_members` se disponível)
2. **Pasta-raiz dos vídeos** (validar com `Test-Path`; aviso se vazia, não bloqueia)
3. **Extensão do vídeo** (default `.mp4`)
4. **Extensão da capa** (default `.png`)
5. **@-mention do responsável?** (default `sim`)
6. **rclone (obrigatório)** — checar instalação, guiar install por SO se faltar, configurar o remote `gdrive:` via `rclone config` se não existir (responder **N** em "Configure as Shared Drive?" — o shared drive é mirado por flag, não baked), validar com `rclone lsd gdrive:Clientes --drive-team-drive 0ABl2cpta6dNRUk9PVA --max-depth 1`. Detalhes completos em [`squads/video-export/tasks/onboarding.md`](../../squads/video-export/tasks/onboarding.md) (seção 6).

> ⚠️ **Por que rclone é obrigatório:** o MCP do Google Drive rejeita uploads > 10MB. Vídeos editados quase sempre passam disso. `rclone copyto` resolve isso transferindo direto pelo remote configurado pelo editor.
>
> 🚨 **Drive Compartilhado, não Meu Drive.** Todo comando rclone roda com `--drive-team-drive <rcloneTeamDriveId>` (`0ABl2cpta6dNRUk9PVA` — shared drive da Stark com as pastas oficiais dos clientes). Sem o flag o rclone cria pastas no "Meu Drive" pessoal de quem roda (bug das primeiras versões). A skill só sobe pra cliente que já tem pasta nesse shared drive.

Salvar `config.json`:

```json
{
  "editorEmail": "mateus.redmann@starkmkt.com",
  "videoRoot": "D:\\Edicoes",
  "videoExt": ".mp4",
  "capaExt": ".png",
  "mentionResponsavel": true,
  "rcloneRemote": "gdrive",
  "rcloneTeamDriveId": "0ABl2cpta6dNRUk9PVA",
  "rcloneCheckedAt": "<ISO timestamp>",
  "version": 3,
  "createdAt": "<ISO timestamp>"
}
```

Criar também `%USERPROFILE%\.stark-video-export\logs\`.

**Migração de config v1 → v2:** se Eve carregar uma config sem `rcloneRemote` ou com `version: 1`, executar apenas a etapa 6 do onboarding (mini-setup do rclone), preservar os demais campos, salvar com `version: 2`. Não repete perguntas 1-5.

**Migração de config v2 → v3:** se Eve carregar uma config sem `rcloneTeamDriveId` ou com `version: 2`, **sem perguntar nada** injetar `rcloneTeamDriveId` com o default do `squad.yaml` (`0ABl2cpta6dNRUk9PVA`), revalidar acesso com `rclone lsd gdrive:Clientes --drive-team-drive <id>` e salvar como `version: 3`. É o conserto que faz a skill mirar o shared drive em vez do Meu Drive.

`--setup-rclone` força só a etapa 6 mesmo quando a config já está em v3 (útil pra reconectar o Google).

Depois do onboarding, continua o pipeline com `--hoje` (a não ser que outra flag já tenha sido passada).

---

## 4. Pipeline

```
[Eve export-chief]   carrega config, resolve flags, define escopo
   │
[Scan scanner]       varre videoRoot → lista pares (video, capa, cliente, data)
   │
   └─► por par, em paralelo (lotes de 4):
        ├─ [Match matcher]    busca subtarefa ClickUp por cliente+data (read-only)
        ├─ [Up uploader]      cria pastas no Drive + upload vídeo+capa
        └─ [Noti notifier]    comenta link no ClickUp + @resp + status = edição concluída
   │
[Eve export-chief]   consolida relatório (sucessos + pendências)
```

Regras de orquestração:
- **Falha em um par não aborta os demais.** Agrega no relatório final.
- **Paralelismo:** 4 pares simultâneos (default).
- **Idempotência:** sem `--force`, arquivo já presente no Drive (mesmo nome + tamanho) → pula.
- **Log:** cada decisão em `%USERPROFILE%\.stark-video-export\logs\<timestamp>.log`.

---

## 5. Estrutura de pasta esperada

```
<videoRoot>\
└── <Cliente>\                ← nome da pasta-pai = cliente
    └── <DD-MM-YYYY>\         ← subpasta de data
        ├── reels-01.mp4      ┐
        ├── reels-01.png      │ par (mesmo nome-raiz)
        ├── reels-02.mp4      │
        └── reels-02.png      ┘
```

- **Cliente** = pasta-pai (1 nível acima da pasta da data)
- **Data** = nome da subpasta `DD-MM-YYYY`; fallback = `mtime` do vídeo
- **Par** = mesmo nome-raiz na mesma pasta

---

## 6. Agente Scan — Varredura

**Input:** `videoRoot`, `videoExt`, `capaExt`, escopo (`modo` + `pasta`/`cliente`).

**Algoritmo:**

```python
def scan(videoRoot, modo, pasta=None, cliente=None, videoExt=".mp4", capaExt=".png"):
    hoje = date.today()
    pastas_alvo = []

    if modo == "pasta":
        pastas_alvo = [pasta]
    elif modo == "hoje":
        data_hoje = hoje.strftime("%d-%m-%Y")
        pastas_alvo = glob(f"{videoRoot}/*/{data_hoje}")
        if not pastas_alvo:
            pastas_alvo = [p for p in glob(f"{videoRoot}/*/*")
                           if any_mtime_today(p, videoExt)]
    elif modo == "semana":
        for d in [hoje - timedelta(days=hoje.weekday()) + timedelta(days=i) for i in range(5)]:
            pastas_alvo += glob(f"{videoRoot}/*/{d.strftime('%d-%m-%Y')}")
    elif modo == "all":
        pastas_alvo = glob(f"{videoRoot}/*/*")

    if cliente:
        pastas_alvo = [p for p in pastas_alvo if normalize(parent_of(p)) == normalize(cliente)]

    pares, orfaos = [], []
    for pasta in pastas_alvo:
        videos = glob(f"{pasta}/*{videoExt}")
        capas  = glob(f"{pasta}/*{capaExt}")
        capa_by_root = {basename_no_ext(c): c for c in capas}
        for v in videos:
            root = basename_no_ext(v)
            c = capa_by_root.pop(root, None)
            if c:
                pares.append({"video": v, "capa": c,
                              "cliente": parent_of(pasta),
                              "data": data_from_pasta_or_mtime(pasta, v)})
            else:
                orfaos.append({"video": v, "motivo": "capa ausente"})
        for c in capa_by_root.values():
            orfaos.append({"capa": c, "motivo": "vídeo ausente"})
    return {"pares": pares, "orfaos": orfaos}
```

**Regras:**
- Extensões case-insensitive (`.MP4` casa com `.mp4`)
- Múltiplas capas pro mesmo vídeo → pega 1ª por ordem alfabética, warning
- Órfãos (vídeo sem capa ou capa sem vídeo) **não bloqueiam** os pares válidos
- Pastas vazias são silenciosamente puladas

**Ferramentas:** `Glob`, `PowerShell (Get-Item ... | Select LastWriteTime)` para mtime.

---

## 7. Agente Match — ClickUp (read-only)

**Input por par:** `cliente`, `data`.

**Algoritmo:**

### 7.1 Normalização obrigatória do nome do cliente

```
normalizar(nome):
  1. Remover pontos de abreviação: "Dr." → "Dr", "Dra." → "Dra"
  2. Lowercase
  3. Remover acentos: "Taíssa" → "taissa"
  4. Colapsar whitespace e trim
```

> ⚠️ **Anti-duplicação obrigatória:** sem essa etapa, "Dr." na pasta local e "Dr" no ClickUp viram pares diferentes e o match falha. Mantenha o nome original só pra exibição.

### 7.2 Consulta opcional a `clickup_alias` em `clientes.yaml`

Se o cliente tem entrada com `clickup_alias`, usar esse alias na busca.

### 7.3 Busca

`clickup_search` (ou `clickup_filter_tasks`) com:
- texto = `"<cliente_normalizado> <data-DD-MM>"`
- filtro: status ≠ `arquivado`, tipo = subtarefa quando possível

### 7.4 Ranking

Prefere candidatos que:
1. Têm cliente normalizado no path da lista/pasta
2. Têm data no nome (`DD-MM`, `DD/MM`, `DD-MM-YYYY`, `DD-MM-AA`)
3. Contêm "edição", "vídeo" ou "reels" no nome

Sem score mínimo → **pendência (`não encontrado`)**. Não inventa, não cria tarefa nova.

### 7.5 Output por par

```yaml
match: "ok" | "ambíguo" | "não encontrado"
subtask_id: "8gqkmtp"
subtask_name: "Edição de vídeo — 27/05 Reels Viral"
list_id: "901234567"
parent_task_id: "8gqkmtp9"
parent_assignees: [12345]      # IDs dos responsáveis da tarefa-mãe
alternativas: ["8gqkmpa", ...] # quando ambíguo
```

**Regras:**
- Cache de match por sessão: `(cliente, data)` já resolvido → reusa
- Match é **read-only**. Quem escreve no ClickUp é Noti
- Compactação: após `clickup_search`, manter só `id`, `name`, `status.status`, `parent` das candidatas

**Ferramentas:** `clickup_search`, `clickup_filter_tasks`, `clickup_get_task` (pra ler assignees da mãe).

---

## 8. Agente Up — Upload Google Drive

**Input por par:** `video`, `capa`, `cliente`, `data`, `force`.

> 🚨 **Tudo no Drive Compartilhado da Stark.** Cada comando rclone abaixo roda com
> `--drive-team-drive <config.rcloneTeamDriveId>` (default `0ABl2cpta6dNRUk9PVA`). Nos exemplos,
> `<TD>` = `--drive-team-drive 0ABl2cpta6dNRUk9PVA`. Sem o flag, o rclone usa o "Meu Drive"
> pessoal do editor e cria pastas órfãs lá. **Só sobe pra cliente que já tem pasta nesse shared drive.**

### 8.1 Lookup obrigatório em `clientes.yaml`

Antes de construir o caminho, consultar overrides do cliente (ver seção 11). Define se vai em **modo padrão** ou **modo override**.

### 8.1.5 Gate — cliente tem pasta oficial no shared drive?

Antes de qualquer `mkdir`/`copyto`:

```powershell
# modo padrão
rclone lsf "<remote>:Clientes/<drive_nome OR cliente>" <TD> --dirs-only --max-depth 1
```

- Pasta-raiz do cliente não existe → **par `failed`**, motivo `cliente sem pasta no Drive Compartilhado`. **Nunca** criar a raiz do cliente.
- Modo override: a pasta-âncora (`drive_pasta_ano_id`) precisa ser alcançável dentro do shared drive (validado ao resolvê-la na 8.5). Fora do shared drive / ID inválido → `failed`.

### 8.2 Hierarquia destino

**Modo padrão** (sem `drive_pasta_ano_id`):
```
Clientes/<drive_nome OR cliente>/Cronograma de Conteudo/Artes/<ano>/<mes-extenso>/<DD-MM-YYYY>/
```

**Modo override** (com `drive_pasta_ano_id`):
```
<startFolderId>/<MM. mes-extenso>/<DD-MM-YYYY>/
```

`startFolderId` = pasta-âncora pré-criada manualmente (ex: "Artes 2026 | Dr. Gilberto").

### 8.3 Conversão de mês

| Número | Padrão     | Com prefixo (override) |
|--------|------------|------------------------|
| 01     | janeiro    | `01. janeiro`          |
| 02     | fevereiro  | `02. fevereiro`        |
| 03     | março      | `03. março`            |
| 04     | abril      | `04. abril`            |
| 05     | maio       | `05. maio`             |
| 06     | junho      | `06. junho`            |
| 07     | julho      | `07. julho`            |
| 08     | agosto     | `08. agosto`           |
| 09     | setembro   | `09. setembro`         |
| 10     | outubro    | `10. outubro`          |
| 11     | novembro   | `11. novembro`         |
| 12     | dezembro   | `12. dezembro`         |

Tudo lowercase. `março` mantém cedilha.

### 8.4 Idempotência

Antes de cada upload, comparar local vs. remote via `rclone lsjson`:

```powershell
rclone lsjson "gdrive:Clientes/<cliente>/.../<DD-MM-YYYY>" <TD> --files-only
```

Pra cada arquivo local:
1. Existe na pasta remote + tamanho igual → `skipped`
2. Existe + tamanho diferente:
   - sem `--force` → pula com warning
   - com `--force` → `rclone copyto` por cima (sobrescreve)
3. Não existe → upload normal

> Se a pasta-destino ainda não existe, `rclone lsjson` retorna stderr "directory not found" e sai com código ≠ 0 — tratar como "nada subido ainda".

### 8.5 Upload via rclone (obrigatório)

> 🚨 **Por que rclone e não Drive MCP:** o MCP rejeita arquivos > 10MB. Vídeos editados rotineiramente passam de 200MB. `rclone copyto` resolve sem limite.

Sequência por par (vídeo + capa **na mesma pasta-destino**, em paralelo):

```powershell
# Garante pasta destino (no-op se já existe) — sob uma raiz de cliente já validada na 8.1.5
rclone mkdir "<remote>:<path_destino>" <TD>

# Upload do vídeo
rclone copyto `
  "D:\Edicoes\<cliente>\<DD-MM-YYYY>\reels-01.mp4" `
  "<remote>:<path_destino>/reels-01.mp4" <TD> `
  --progress --transfers 1 --drive-chunk-size 64M --retries 2

# Upload da capa (mesma chamada padrão; pequena, mas mantém o mesmo caminho de tooling)
rclone copyto `
  "D:\Edicoes\<cliente>\<DD-MM-YYYY>\reels-01.png" `
  "<remote>:<path_destino>/reels-01.png" <TD> `
  --retries 2
```

- `<remote>` = `config.rcloneRemote` (default `gdrive`)
- `<TD>` = `--drive-team-drive <config.rcloneTeamDriveId>` (default `0ABl2cpta6dNRUk9PVA`) — **obrigatório em todo comando rclone**
- `<path_destino>` no **modo padrão** = `Clientes/<drive_nome OR cliente>/Cronograma de Conteudo/Artes/<ano>/<mes-extenso>/<DD-MM-YYYY>`
- No **modo override** (`drive_pasta_ano_id` definido), rclone não navega por ID. Usar `--drive-root-folder-id` **junto com `<TD>`** (a âncora fica dentro do shared drive):
  ```powershell
  rclone copyto <arquivo> "<remote>:" <TD> --drive-root-folder-id <startFolderId> --drive-root-folder-id-resolve-prefix "<MM. mes-extenso>/<DD-MM-YYYY>/<arquivo>"
  ```
  ou, mais simples, pré-resolver o caminho humano dessa pasta-âncora via Drive MCP `get_file_metadata` (nome + parents) e construir o path absoluto pra rclone (sempre com `<TD>`).

**Exit codes do rclone:**
- `0` → ok
- `1` (sintaxe), `3` (dir não existe), `7` (limite), etc. → falha clara, registra em pendência
- `5` (rate-limit transitório) → 1 retry com backoff 5s, depois falha

### 8.6 Obter URL da pasta + IDs dos arquivos

`rclone copyto` retorna apenas exit code. Pra montar o comentário do ClickUp precisa do **link `webViewLink` da pasta** e dos **IDs dos arquivos**. Após o upload, chamar o Drive MCP (não tem o problema de tamanho, é só leitura):

1. `google_drive_list_files` na pasta-destino → captura `folder.id`, `folder.webViewLink`, e por arquivo seu `id`/`webViewLink`
2. Cache do `folder.id` por `(cliente, data)` na sessão (evita re-listar)

Se o Drive MCP não estiver disponível, fallback: usar `rclone link <remote>:<path> <TD>` (gera URL pública compartilhada — só usar se a política da Stark permitir; default = preferir Drive MCP).

### 8.7 Validação pós-upload

Re-listar a pasta-destino via `rclone lsjson` ou Drive MCP. Confirmar presença de vídeo+capa com nome esperado **e tamanho igual ao local**. Se faltou um → `partial`. Se faltaram os dois → `failed`.

### 8.8 Output por par

```yaml
status: "ok" | "skipped" | "partial" | "failed"
drive_folder_url: "https://drive.google.com/drive/folders/abc123"
drive_folder_id: "abc123"
uploaded:
  - { name: "reels-01.mp4", url: "...", id: "..." }
  - { name: "reels-01.png", url: "...", id: "..." }
falhas: []
modo: "padrão" | "override-startfolder"
transport: "rclone"   # sempre rclone na v1.2+
```

### 8.9 Regras

- **rclone obrigatório.** Se `rclone` não está no PATH, abortar com mensagem pedindo `/video-export --setup-rclone`
- **`--drive-team-drive` em TODO comando.** Sem ele o rclone opera no Meu Drive pessoal e cria pastas órfãs. Se `config.rcloneTeamDriveId` faltar, usar o default do `squad.yaml` (`0ABl2cpta6dNRUk9PVA`)
- **Pasta `Clientes/<drive_nome>/`** precisa preexistir no shared drive (gate 8.1.5). Não existe → **`failed`/pendência**, NÃO cria a raiz do cliente em lugar nenhum
- **`<startFolderId>`** assumida preexistente **dentro do shared drive** no modo override. ID inválido / fora do shared drive → falha clara
- **Subpastas** (`Cronograma de Conteudo`, `Artes`, ano, mês, data) criadas sob demanda via `rclone mkdir`, sempre sob uma raiz já validada
- **Mismatch silencioso proibido:** se `drive_nome` está no YAML mas a pasta não existe no Drive, **falha** — NÃO tenta cair pra `cliente`
- Compactação: após `list folder`, manter só `id`/`name`/`size`. Após `upload`, só `id`/`webViewLink`

**Ferramentas:** `rclone copyto`/`rclone mkdir`/`rclone lsjson`/`rclone listremotes` (transporte), `google_drive_list_files` (resolução de URL+ID pós-upload), `PowerShell Get-Item` (tamanho local).

---

## 9. Agente Noti — Notificação ClickUp

**Input por par:** `subtask_id`, `parent_task_id`, `parent_assignees`, `drive_folder_url`, `cliente`, `data`, `nome_raiz`, `arquivos_entregues`, `mentionResponsavel`, `statusFinal`, `dry_run`.

### 9.1 Template de comentário (padrão Stark)

```
✅ Edição concluída.
Ref: <cliente> — <DD-MM> <nome_raiz>
Entregue: vídeo (.mp4) + capa (.png)

🔗 Drive: <drive_folder_url>
```

Com `mentionResponsavel=true`, prefixar a 1ª linha com `@<nome-responsável>` (espaço entre múltiplos).

**Exemplos concretos:**

Sem mention:
```
✅ Edição concluída.
Ref: Dr. Rodolfo Soares — 27-05 reels-01
Entregue: vídeo (.mp4) + capa (.png)

🔗 Drive: https://drive.google.com/drive/folders/abc123
```

Com mention single:
```
@Mateus ✅ Edição concluída.
Ref: Dr. Rodolfo Soares — 27-05 reels-01
Entregue: vídeo (.mp4) + capa (.png)

🔗 Drive: https://drive.google.com/drive/folders/abc123
```

Com múltiplos responsáveis (assignees da tarefa-mãe):
```
@Maria @João ✅ Edição concluída.
Ref: Dra. Anne Groth — 27-05 reels-02
Entregue: vídeo (.mp4) + capa (.png)

🔗 Drive: https://drive.google.com/drive/folders/xyz789
```

### 9.2 ⚠️ Regra CRÍTICA — sequencial obrigatório

**NUNCA executar `clickup_create_task_comment` e `clickup_update_task` em paralelo na mesma subtarefa.**

O ClickUp dropa o comentário silenciosamente quando os dois competem (a API responde 200 OK, mas o comentário não aparece). O update de status ganha a corrida.

Ordem correta:

```
Passo 1:  clickup_create_task_comment(subtask_id, comment_text, notify_all=true)
          → AWAIT → confirmar comment_id

Passo 2:  clickup_update_task(subtask_id, status="edição concluída")
          → AWAIT → confirmar new status
```

Se passo 2 falhar, registrar `comment_ok_status_fail` — **não fazer rollback do comentário**.

### 9.3 Resolução de mention

1. Ler `assignees` da `parent_task_id` (tarefa-mãe da subtarefa) via `clickup_get_task`
2. Pra cada assignee, pegar `username` e converter pra `@nome`
3. Sem assignee na mãe → `mentioned_users: []`, posta sem `@` no início

### 9.4 Status final

Sempre `edição concluída`. Não é configurável no v1.

Se a lista da subtarefa não tem esse status:
- Registrar `comment_ok_status_fail`
- Manter status atual
- Incluir no relatório final

### 9.5 Dry-run

`--dry-run`: monta comentário + payload de update, devolve preview, **não chama API**.

```yaml
dry_run: true
comment_preview: |
  @Mateus ✅ Edição concluída.
  Ref: Dr. Rodolfo Soares — 27-05 reels-01
  Entregue: vídeo (.mp4) + capa (.png)

  🔗 Drive: https://drive.google.com/drive/folders/abc123
status_payload: { task_id: "abc", status: "edição concluída" }
```

### 9.6 Output por par

```yaml
status: "ok" | "comment_ok_status_fail" | "failed"
comment_id: "comment-xyz"
mentioned_users: ["Mateus Redmann"]
status_atualizado_para: "edição concluída"
erro: null
```

### 9.7 Regras

- **Drive URL vazio/nulo → pula tudo + pendência.** Não comenta com link quebrado
- Idempotência: NÃO relê comentários antigos pra evitar duplicar. Sempre posta novo (re-rodar = 2 comentários, melhor que dedup complexa)
- Compactação: após `clickup_get_task` da mãe, manter só `assignees[].username`

**Ferramentas:** `clickup_create_task_comment`, `clickup_update_task`, `clickup_get_task`, `clickup_resolve_assignees`.

---

## 10. Agente Eve — Relatório final

Consolida resultado de todos os pares e mostra ao editor:

```
✅ Video Export — concluído em <tempo>

Sucesso: N pares
  • [Dr. Rodolfo Soares] 27-05-2026 — reels-01 (vídeo + capa) → Drive ✓ ClickUp ✓
  • [Dr. Rodolfo Soares] 27-05-2026 — reels-02 (vídeo + capa) → Drive ✓ ClickUp ✓
  • ...

Pendências: M pares
  • [Dra. Y] 27-05-2026 — reels-03: par órfão (capa ausente)
  • [Dr. Z] 27-05-2026 — subtarefa não encontrada no ClickUp
  • [Dr. W] 27-05-2026 — reels-01: drive_nome "Dr. W" não existe no Drive
```

Modo `--semana` adiciona sub-totais por dia útil:

```
✅ Video Export — semana 25/05 a 29/05/2026

Segunda 25/05 — 3 pares
Terça   26/05 — 5 pares
Quarta  27/05 — 4 pares
Quinta  28/05 — 0 pares
Sexta   29/05 — 6 pares

Total: 18  |  Sucesso: 17  |  Pendências: 1
```

---

## 11. Overrides por cliente (`clientes.yaml`)

Embed do `squads/video-export/config/clientes.yaml`. **Mantenha sincronizado com o upstream `prep-agenda-stark`.**

```yaml
clientes:

  "Dr. Anderson Kuboniwa":
    drive_nome: "Dr. Anderson"
    drive_pasta_ano_id: "1938YPt9KZtCIWMd16K4Q2NNtQeEuCFHl"
    # CRIATIVOS INSTAGRAM | DR. ANDERSON

  "Dr. Gilberto Filho":
    drive_pasta_ano_id: "1PU7nohuXw-buXweXiKzDvPV-omlx_fDg"
    # Artes 2026 | Dr. Gilberto Filho

  "Dr. Luciano Esteves":
    drive_pasta_ano_id: "1Jo-Us_7hgKetMB4JYRV2NA90F-oAuSMh"
    # 03. Cronograma de Conteúdo | Dr Luciano Esteves

  "Dra. Ana Paula Polato":
    drive_pasta_ano_id: "17YJgcAYC0GM47ur9HUMKVWhCHZMJVf2w"

  "Dra. Anne Groth":
    drive_pasta_ano_id: "1MWjxwRcrRsewp2lHajOXwg-YnLPt5LFp"

  "Dr. Cadu Gazzinelli":
    drive_pasta_ano_id: "1URChbjVFimvt5lQzrvxPezKqFo0ItTEo"

  "Dr. Marcelo Azevedo":
    drive_pasta_ano_id: "15Wgzhp7jntlG7vqbiZVR0fMIfgnc036L"

  "Dr. Felipe Máximo":
    drive_pasta_ano_id: "1g-y4GZXlxr4J3eSuET-bfiQKY0I7BaP1"

  "Empoderatti":
    drive_pasta_ano_id: "1X_fxEdinSg3BmF0t4r_eExFT07xIFDZ5"

# Clientes sem entrada usam o modo padrão automaticamente:
#   Dra. Graciela Machado, Dra. Amandia Marchetti, Dr. Matheus Ocampo,
#   Dra. Nicolle Andrade, Dra. Taíssa Recalde, Dr. Ricardo Martins,
#   Dr. Rodolfo Soares, Dr. Daniel Valente, Dra. Leslye Sartori,
#   Destra Desenvolvimento Mineral.
```

**Campos disponíveis:**

| Campo                | Quando usar                                                              |
|----------------------|---------------------------------------------------------------------------|
| `drive_nome`         | Pasta no Drive tem nome diferente do nome local (ex: "Dr. Anderson")     |
| `drive_pasta_ano_id` | Estrutura não bate em `Clientes/<cli>/Cronograma/Artes/<ano>` (override) |
| `clickup_alias`      | Nome no ClickUp difere da pasta local                                    |

---

## 12. Tratamento de erros

| Erro                                                  | Ação                                                    |
|-------------------------------------------------------|---------------------------------------------------------|
| Pasta `Clientes/<drive_nome>/` não existe no shared drive | Falha do par, pendência `cliente sem pasta no Drive Compartilhado` — NÃO cria raiz |
| `drive_pasta_ano_id` inválido / fora do shared drive  | Falha do par, mensagem pedindo update do clientes.yaml  |
| `--drive-team-drive` ausente / id errado              | Pastas iam pro Meu Drive — sempre passar `<rcloneTeamDriveId>` (config/squad.yaml = `0ABl2cpta6dNRUk9PVA`) |
| Quota do Drive estourada                              | Falha do par, registra pra retry manual                 |
| Timeout no upload                                     | 1 retry com backoff 5s, depois falha do par             |
| MCP do Drive offline                                  | Não aborta — só perde a resolução de URL pós-upload. Fallback: `rclone link` |
| `rclone` não instalado / fora do PATH                 | Aborta squad com mensagem explícita pedindo `/video-export --setup-rclone` |
| `rclone listremotes` não tem o remote configurado     | Aborta com mensagem pedindo `/video-export --setup-rclone` |
| `rclone copyto` retorna exit code ≠ 0                 | Falha do par, registra stderr no log                    |
| Subtarefa ClickUp não encontrada                      | Pendência. NÃO cria tarefa nova                         |
| Status `edição concluída` não existe na lista         | Mantém status atual, marca `comment_ok_status_fail`     |
| `drive_nome` no YAML mas pasta não existe no Drive    | Falha — NÃO cai pra `cliente`                           |

---

## 13. MCPs necessários

**Obrigatórios:**
- `clickup` (MCP) — busca de subtarefa, comentário, status, resolução de assignees
- `google-drive` (MCP) — listar pasta, ler metadados/webViewLink (apenas leitura — upload é via rclone)
- `rclone` (CLI externa, instalada na máquina do editor) — upload e transferência de arquivos > 10MB

**Ferramentas usadas (lista canônica):**

ClickUp:
- `clickup_search` — busca textual de tarefa/subtarefa
- `clickup_filter_tasks` — filtro estrito quando precisar
- `clickup_get_task` — ler subtarefa específica (modo `--task`) e assignees da tarefa-mãe
- `clickup_create_task_comment` — postar comentário (notify_all=true)
- `clickup_update_task` — mudar status
- `clickup_resolve_assignees` — resolver nomes → IDs em mentions
- `clickup_get_workspace_members` — autocomplete no onboarding

Google Drive (apenas leitura/resolução — upload sai por rclone):
- listar arquivos por pasta-pai (resolver `folder.id` e `webViewLink`)
- ler metadados de pasta-âncora (`drive_pasta_ano_id`)

rclone (CLI):
- `rclone listremotes` — checar se o remote configurado existe
- `rclone config show <remote>` — validar tipo `drive`
- `rclone lsd` / `rclone lsjson` / `rclone lsf` — listar pastas/arquivos remoto, gate de pasta do cliente, comparar tamanho local vs remoto
- `rclone mkdir` — criar hierarquia de pastas no Drive (subpastas, nunca a raiz do cliente)
- **todos com `--drive-team-drive <rcloneTeamDriveId>`** — mira o shared drive da Stark, não o Meu Drive
- `rclone copyto` — upload arquivo-a-arquivo (`copyto` preserva o nome de destino exato)
- `rclone link` — fallback pra URL quando Drive MCP indisponível
- `rclone config reconnect` — re-autenticar Google se o token expirou

Filesystem/Shell:
- `Glob` — listar arquivos por pattern
- `PowerShell` — `Test-Path`, `Get-Item ... | Select LastWriteTime`, `Get-Item ... | Select Length`, `Get-Command rclone`
- `Read` / `Write` — config.json
- `Edit` — atualizar config no `--reconfigure`

---

## 14. Portabilidade para outros LLMs

Esta skill foi escrita pra ser executada em:

1. **Claude Code / Cowork** — invocação via `/video-export` ou trigger natural. Tudo automatizado.
2. **ChatGPT / Gemini / Grok com tool use** — cole esta SKILL.md como system prompt. Os nomes de MCP tools (`mcp__*__clickup_*`, `mcp__*__google_drive*`) viram nomes das suas próprias function definitions. O fluxo lógico é idêntico.
3. **LLM sem tool use** — modo consultivo: o LLM imprime os comandos PowerShell / curl que o operador roda na mão. Útil pra dry-run mental antes de automatizar.

**Adaptação por plataforma:**

| Plataforma         | `videoRoot` cache              | Ferramentas de FS         |
|--------------------|--------------------------------|---------------------------|
| Windows (default)  | `%USERPROFILE%\.stark-video-export\` | PowerShell, Glob       |
| macOS              | `~/.stark-video-export/`            | `bash`, `find`, `stat`  |
| Linux              | `~/.stark-video-export/`            | `bash`, `find`, `stat`  |

Substitua `Test-Path X` por `[ -e X ]`, `Get-Item ... | Select LastWriteTime` por `stat -c %Y X`, etc. A lógica de matching, hierarquia Drive, template ClickUp e regra do sequencial NÃO mudam.

---

## 15. Critérios de aceite (checklist)

- [ ] `/video-export` na 1ª vez roda onboarding em ≤ 2 min e cria `config.json` v3 (com `rcloneRemote` + `rcloneTeamDriveId`)
- [ ] Onboarding detecta rclone instalado e pula a instalação; quando ausente, mostra comando por SO e revalida em loop
- [ ] Onboarding cria/escolhe o remote `gdrive:` e valida com `rclone lsd gdrive:Clientes --drive-team-drive 0ABl2cpta6dNRUk9PVA --max-depth 1`
- [ ] Config v1 (sem `rcloneRemote`) dispara só a etapa 6 ao ser carregada, salva como v2
- [ ] Config v2 (sem `rcloneTeamDriveId`) injeta o id do shared drive sem perguntar nada e salva como v3
- [ ] `/video-export --setup-rclone` roda só a etapa 6 mesmo com config v3
- [ ] `/video-export` sem flag após onboarding equivale a `--hoje`
- [ ] `/video-export <pasta>` processa só essa pasta, mesmo se mtime ≠ hoje
- [ ] `/video-export-task <task_id>` processa só a subtarefa indicada, sem varredura por data
- [ ] **Todo comando rclone usa `--drive-team-drive` — nenhuma pasta criada no "Meu Drive"**
- [ ] **Cliente sem pasta no shared drive → pendência, sem criar a raiz**
- [ ] Par vídeo+capa sobe pra hierarquia Drive correta (padrão ou override) **via `rclone copyto`**
- [ ] Vídeo > 10MB sobe sem cair no limite do Drive MCP
- [ ] Comentário ClickUp postado e status muda pra `edição concluída`
- [ ] @-mention do responsável da tarefa-mãe aparece quando `mentionResponsavel=true`
- [ ] Re-rodar sem `--force` pula arquivos já presentes no Drive (via `rclone lsjson` size match)
- [ ] `--force` sobrescreve no Drive
- [ ] Falha em 1 par não aborta os outros
- [ ] Órfãos (vídeo sem capa) entram em pendências, não bloqueiam pares válidos
- [ ] `--dry-run` lista o que faria sem subir nem comentar
- [ ] `--reconfigure` reabre onboarding com defaults da config atual
- [ ] Comentário e status NÃO disparam em paralelo na mesma subtarefa (regra crítica FR31)

---

## 16. Fora do escopo (v1)

- Múltiplos editores no mesmo cache (1 config por usuário do SO)
- Conversão automática de formato (HEIC→PNG, MOV→MP4)
- Geração de capa a partir do vídeo
- Validação de conteúdo (nudez, marca, etc.)
- Notificação Slack/WhatsApp
- Criação automática de subtarefa quando Match não encontra
- Multi-tenant / múltiplas workspaces ClickUp
- Status final configurável por tipo de post

---

## 17. Histórico

| Data       | Versão | Mudança                                                                         |
|------------|--------|---------------------------------------------------------------------------------|
| 2026-06-01 | 1.0    | PRD inicial                                                                     |
| 2026-06-01 | 1.1    | Template Stark + FR31 (sequencial comentário→status) + overrides clientes.yaml + normalização cliente |
| 2026-06-01 | 1.1.0  | SKILL.md autocontido para portabilidade Claude Code / Cowork / outros LLMs       |
| 2026-06-01 | 1.2.0  | rclone obrigatório no onboarding + uploader via `rclone copyto` (resolve cap 10MB do Drive MCP). Novo slash command `/video-export-task <id>` pra entregar uma subtarefa específica. Config migra v1 → v2 sem repetir perguntas. |
| 2026-06-08 | 1.3.0  | **Conserta upload indo pro "Meu Drive" pessoal.** Todo comando rclone passa `--drive-team-drive 0ABl2cpta6dNRUk9PVA` (Drive Compartilhado da Stark). Gate novo: só sobe pra cliente com pasta oficial no shared drive — senão pendência, nunca cria a raiz. Config migra v2 → v3 injetando `rcloneTeamDriveId` sem perguntar. |
