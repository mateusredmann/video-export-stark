---
name: export-task
trigger: "/video-export-task <task_id_ou_url> [--force] [--dry-run] [--nome-raiz <root>]"
---

# Workflow: Export Task (alvo único pelo ID do ClickUp)

Entrega exatamente uma subtarefa do ClickUp. Inverte o fluxo do `/video-export`: começa pelo ClickUp e desce pro filesystem, em vez de varrer o filesystem por data.

## Pipeline

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

## Parsing do task_id

```python
def parse_task_id(arg: str) -> str:
    # aceita: "8gqkmtp", "abc123", "https://app.clickup.com/t/8gqkmtp", "https://app.clickup.com/t/8gqkmtp/8gq..."
    m = re.search(r"/t/([a-z0-9]+)", arg)
    if m: return m.group(1)
    if re.match(r"^[a-z0-9]+$", arg, re.I): return arg
    raise ValueError(f"task_id inválido: {arg}")
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

## Exemplo end-to-end

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
