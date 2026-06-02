---
name: export-task
trigger: "/video-export-task <task_id|url|caminho_pasta> [--force] [--dry-run] [--nome-raiz <root>]"
---

# Workflow: Export Task (alvo único)

Entrega exatamente uma subtarefa do ClickUp. Tem dois modos de entrada:

- **Reverso (task_id / URL)** — começa pelo ClickUp e desce pro filesystem.
- **Path (caminho de pasta local)** — começa pelo filesystem (numa pasta específica) e procura a subtarefa no ClickUp pelo cliente+data extraídos do nome do arquivo. É o `/video-export` reduzido a uma pasta só.

## Detecção do tipo de argumento

```python
def detect_arg_type(arg: str) -> str:
    # 1) URL ClickUp
    if re.search(r"clickup\.com/t/", arg) or arg.startswith("/t/"):
        return "url"
    # 2) Path — drive letter, UNC, POSIX absoluto, ou contém separador + existe
    looks_like_path = bool(
        re.match(r"^[A-Za-z]:[\\/]", arg) or       # D:\... ou C:/...
        arg.startswith("\\\\") or                  # \\server\share
        re.match(r"^/[a-zA-Z]/", arg) or           # /d/Stark... (Git Bash)
        ("\\" in arg or "/" in arg)
    )
    if looks_like_path and os.path.isdir(arg):
        return "path"
    # 3) task_id literal alfanumérico
    if re.match(r"^[a-zA-Z0-9]+$", arg):
        return "task_id"
    # 4) parece path mas não existe → erro contextual
    if looks_like_path:
        raise ValueError(f"caminho não encontrado: {arg}")
    raise ValueError(f"argumento inválido: {arg!r} — esperado task_id, URL ou pasta")
```

## Pipeline — modo reverso (task_id / URL)

```
1. Eve carrega config.json (+ migração v1→v2 / onboarding se ausente)
1b. Pré-flight rclone (binário + remote + tipo drive)
2. Eve parseia <task_id> (literal ou de URL clickup.com/t/<id>)
3. Match reverso:
     a. clickup_get_task(task_id)
     b. Extrai cliente: lista/folder pai → ou pelo parent task name → ou regex
     c. Extrai data: nome da subtarefa → ou due_date
     d. clickup_get_task(parent) → parent_assignees
4. Scan dirigido (1 pasta esperada, com fallbacks)
5. Filtragem por --nome-raiz ou prompt interativo se múltiplos pares
6. Up (rclone copyto): vídeo + capa
7. Drive MCP: webViewLink + IDs pós-upload
8. Noti: comenta + mention + status (sequencial FR31)
9. Eve: relatório (1 par)
```

## Pipeline — modo path

```
1. Eve carrega config.json (idem)
1b. Pré-flight rclone (idem)
2. Eve detecta tipo → "path", normaliza pra absoluto
3. Scan local na pasta única:
     a. Get-ChildItem <pasta>\*<videoExt>  e  <pasta>\*<capaExt>
     b. Pareia por nome-raiz (basename sem extensão)
     c. 0 vídeos → erro "pasta vazia"
     d. > 1 par sem --nome-raiz → prompt interativo
4. Extração de cliente+data (Match direto — sem ClickUp ainda):
     a. Fontes (primeira que casar):
        i.   filename do vídeo do par escolhido (ex.: "16-06 Janete.mp4")
        ii.  nome da pasta (ex.: "16-06 Janete")
        iii. caminho ascendente — mes/ano vêm de pasta-mes ("2026 - Junho") e pasta-ano ("2026")
     b. Regex de data (em ordem):
        - \b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b       → DD-MM-YYYY
        - \b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2})\b       → DD-MM-AA → expande
        - \b(\d{1,2})[-/.](\d{1,2})\b                   → DD-MM (assume ano do path; fallback ano corrente)
     c. Cliente = strip(filename_sem_ext - token_data - extensão); collapse de whitespace
     d. Falha → erro fatal "renomeie como 'DD-MM Cliente.mp4' ou passe --task-id"
5. Match forward (igual ao /video-export):
     a. normalize(cliente) → procura clickup_alias em config/clientes.yaml
     b. clickup_search "<cliente_norm> <DD-MM>"
     c. ranking (cliente bate no path da subtarefa; data bate no name)
     d. 0 → erro fatal; 1 → segue; >1 empatado → prompt
     e. clickup_get_task(parent) → parent_assignees
6. Up (rclone copyto): vídeo + capa
7. Drive MCP: webViewLink + IDs
8. Noti: comenta + mention + status (sequencial FR31)
9. Eve: relatório (1 par)
```

## Parsing do task_id (modo reverso)

```python
def parse_task_id(arg: str) -> str:
    # aceita: "8gqkmtp", "abc123", "https://app.clickup.com/t/8gqkmtp", "https://app.clickup.com/t/8gqkmtp/8gq..."
    m = re.search(r"/t/([a-z0-9]+)", arg)
    if m: return m.group(1)
    if re.match(r"^[a-z0-9]+$", arg, re.I): return arg
    raise ValueError(f"task_id inválido: {arg}")
```

## Extração cliente+data do path (modo path)

```python
DATE_PATTERNS = [
    (r"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b", "DD-MM-YYYY"),
    (r"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2})\b", "DD-MM-AA"),
    (r"\b(\d{1,2})[-/.](\d{1,2})\b",             "DD-MM"),
]

def extract_cliente_data(pasta: str, video_path: str) -> dict:
    # ordem de fontes — primeira que dá DD+MM ganha
    fontes = [
        os.path.splitext(os.path.basename(video_path))[0],   # "16-06 Janete"
        os.path.basename(pasta),                             # "16-06 Janete"
    ]
    ancestors = pasta.split(os.sep)                          # ["D:", "Stark MKT", ..., "2026", "2026 - Junho", "16-06 Janete"]
    # ano default vem do path se houver "20XX" como componente
    ano_path = next((c for c in reversed(ancestors) if re.match(r"^20\d{2}$", c)), None)

    for fonte in fontes:
        for pat, fmt in DATE_PATTERNS:
            m = re.search(pat, fonte)
            if not m: continue
            dia, mes = int(m.group(1)), int(m.group(2))
            if fmt == "DD-MM-YYYY": ano = int(m.group(3))
            elif fmt == "DD-MM-AA": ano = 2000 + int(m.group(3))
            else:                    ano = int(ano_path) if ano_path else datetime.now().year
            # cliente = fonte SEM o token de data e SEM extensão, trim
            cliente = re.sub(pat, "", fonte).strip(" -_.")
            cliente = re.sub(r"\s+", " ", cliente)
            if not cliente:
                continue
            return {
                "cliente_raw": cliente,
                "data": f"{dia:02d}-{mes:02d}-{ano}",
                "data_curta": f"{dia:02d}-{mes:02d}",
                "fonte": fonte,
            }
    raise ValueError(f"não consegui extrair cliente+data de '{pasta}' / '{video_path}'")
```

## Match reverso (extrair cliente + data)

### Cliente

Ordem de tentativas, primeira que casar ganha:

1. **Hierarquia da lista** — `clickup_get_task` retorna `folder.name`/`list.name`. Se `folder.name` contém um cliente do `clientes.yaml` (substring case-insensitive normalizada), usa.
2. **Tarefa-mãe** — `clickup_get_task(parent_task_id).name`. Procura por nome de cliente conhecido.
3. **Subtarefa** — nome da própria subtarefa às vezes inclui o cliente (`"27-05 Dr. Felipe Reels Pre-treino"`).
4. **Falha** → erro fatal com lista dos 5 clientes mais próximos por levenshtein contra o `folder.name` pro editor confirmar manualmente.

### Data

Ordem:

1. **Regex no nome da subtarefa** — patterns:
   - `\b(\d{2})[-/](\d{2})[-/](\d{4})\b` → DD-MM-YYYY
   - `\b(\d{2})[-/](\d{2})[-/](\d{2})\b` → DD-MM-AA → expande "26" → "2026"
   - `\b(\d{2})[-/](\d{2})\b` → DD-MM → assume ano corrente
2. **`due_date` da subtarefa** (timestamp ms) → `DateTimeOffset.FromUnixTimeMilliseconds` → formata DD-MM-YYYY
3. **`due_date` da tarefa-mãe** se a subtarefa não tem
4. **Falha** → erro fatal, pede ao editor passar `--data DD-MM-YYYY` (a ser adicionado em v1.3 se virar problema recorrente)

## Scan dirigido

Constrói candidatos de pasta-alvo em ordem:

```python
candidatos = [
    f"{videoRoot}\\{cliente}\\{DD-MM-YYYY}",
    f"{videoRoot}\\{cliente}\\{DD-MM}",          # sem ano
    f"{videoRoot}\\{cliente.replace('Dr.', 'Dr')}\\{DD-MM-YYYY}",  # variação pontuação
    f"{videoRoot}\\{cliente.replace('Dr', 'Dr.')}\\{DD-MM-YYYY}",
    # fallback: lista todas as subpastas de {videoRoot}\{cliente}\* e filtra por mtime do dia
]
```

Primeiro `Test-Path` positivo ganha. Se nenhum existir + fallback mtime vazio:

```
❌ Não achei a pasta da entrega.

Cliente extraído: "Dr. Felipe Máximo"
Data extraída:    "27-05-2026"
Procurei em:
  - D:\Edicoes\Dr. Felipe Máximo\27-05-2026     (não existe)
  - D:\Edicoes\Dr. Felipe Máximo\27-05          (não existe)
  - D:\Edicoes\Dr Felipe Máximo\27-05-2026      (não existe)

Pastas disponíveis em D:\Edicoes\:
  - Dr. Felipe Máximo\
      ↳ 26-05-2026\   (mtime 2026-05-26)
      ↳ 28-05-2026\   (mtime 2026-05-28)
  - ...

Confirme a pasta correta ou ajuste a data da subtarefa no ClickUp.
```

## Múltiplos pares na pasta

Quando a pasta-data contém mais de um par e o editor não passou `--nome-raiz`:

```
A pasta D:\Edicoes\Dr. Felipe Máximo\27-05-2026\ tem 3 pares:
  [1] reels-01.mp4 + reels-01.png  (vídeo 145MB)
  [2] reels-02.mp4 + reels-02.png  (vídeo 230MB)
  [3] story-01.mp4 + story-01.png  (vídeo  78MB)

Qual é o que vai pra essa subtarefa? [1-3]
> 2
```

(Ou re-invoque com `--nome-raiz "reels-02"`.)

## Exemplo end-to-end (modo path)

```
$ /video-export-task "D:\Stark MKT\02 - Videos\2026\2026 - Junho\16-06 Janete"

→ Eve: config v2 carregada (rcloneRemote=gdrive)
→ Pré-flight rclone: ✓
→ Tipo de argumento: path
→ Scan local: D:\Stark MKT\02 - Videos\2026\2026 - Junho\16-06 Janete\
    Pares: 1
      [1] "16-06 Janete.mp4" + "16-06 Janete.png"
→ Match direto:
    fonte: "16-06 Janete"
    data extraída: "16-06-2026"  (ano herdado de "2026" no path)
    cliente_raw: "Janete"
    normalize: "janete"
    config/clientes.yaml: sem override → procura "janete" no workspace
    clickup_search "janete 16-06" → 1 subtask:
      8h3a2b1 — "Edição de vídeo — 16/06 Reels Janete"
        parent: 8h3a2b0 — "Dra. Janete Almeida — 16/06 Reels Tema X"
    parent_assignees: ["Mateus Redmann"]
→ Up (rclone):
    rclone copyto "16-06 Janete.mp4" → gdrive:Clientes/Dra. Janete Almeida/.../16-06-2026/
    rclone copyto "16-06 Janete.png" → idem
→ Drive MCP: webViewLink resolvido
→ Noti: comentário postado em 8h3a2b1 + status "edição concluída"

✅ Entrega concluída — Dra. Janete Almeida 16-06-2026 (1 par)
   Drive: https://drive.google.com/drive/folders/abc123
```

## Exemplo end-to-end (modo reverso)

```
$ /video-export-task 8gqkmtp --nome-raiz "reels-02"

→ Eve: config v2 carregada (rcloneRemote=gdrive)
→ Pré-flight rclone: ✓
→ Match reverso:
    task_id: 8gqkmtp
    subtask: "Edição de vídeo — 27-05 Reels Pré-treino"
    cliente extraído (via parent.name "Dr. Felipe Máximo — 27/05 Reels Pré-treino"): "Dr. Felipe Máximo"
    data extraída: "27-05-2026"
    parent_assignees: ["Mateus Redmann"]
→ Scan dirigido: D:\Edicoes\Dr. Felipe Máximo\27-05-2026\ → 1 par filtrado por reels-02
→ Up (rclone): 
    rclone copyto reels-02.mp4 → gdrive:Clientes/Dr. Felipe Máximo/Cronograma de Conteudo/Artes/2026/maio/27-05-2026/
    rclone copyto reels-02.png → idem
    [drive_pasta_ano_id presente: usa modo override → 04. abril/27-05-2026/]
→ Drive MCP: webViewLink resolvido
→ Noti: comentário postado em 8gqkmtp + status "edição concluída"

✅ Entrega concluída — Dr. Felipe Máximo 27-05-2026 reels-02
   Drive: https://drive.google.com/drive/folders/abc123
```

## Edge cases

- **Subtarefa já tem status `edição concluída`** → confirma com o editor antes de re-postar (a menos que `--force` foi passado).
- **Task ID inválido / não encontrada** → erro do `clickup_get_task` → mensagem clara.
- **Task ID aponta pra tarefa-mãe e não subtarefa** → Eve avisa: "esse é o ID da mãe, não da subtarefa. As subtarefas dela são: …" e lista pro editor escolher.
- **Cliente está no `clientes.yaml` com `clickup_alias`** → o alias é usado pra normalização, mas a pasta local continua usando o nome canônico (`drive_nome OR cliente`).

### Edge cases do modo path

- **Path passado não existe** → erro fatal: "caminho não encontrado: …" + sugestão das 5 entradas mais próximas em `videoRoot` (NÃO degrada pra task_id silenciosamente — alfanumérico só vira task_id se o argumento não tem separador `\` nem `/`).
- **Path é um arquivo (não pasta)** → trata como pasta-pai do arquivo e continua. Útil quando o editor arrasta o `.mp4` direto.
- **Arquivo não bate o padrão `DD-MM Cliente.ext`** → tenta extrair do nome da pasta; se falhar nas duas, erro fatal pede rename ou `--task-id`.
- **Cliente extraído tem ambiguidade no ClickUp** (ex.: "Felipe" bate em 2 doutores diferentes) → prompt interativo lista os candidatos com `subtask_id + parent.name` e pede escolha.
- **Ano não está no path nem no nome** → assume ano corrente (`datetime.now().year`). Logado como `WARN: ano inferido = 2026`.
- **Nome do cliente normalizado não bate nenhum match no ClickUp** → erro fatal "cliente '<x>' não encontrado nas subtarefas com data <DD-MM>"; sugere top-5 mais próximos por levenshtein contra os `parent.name` da semana.
