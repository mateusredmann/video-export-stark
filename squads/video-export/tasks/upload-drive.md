---
name: upload-drive
owner: uploader
---

# Task: Upload pro Google Drive

Implementado pelo agente Up. Algoritmo completo em [agents/uploader.md](../agents/uploader.md).

## Alvo: Drive Compartilhado da Stark (não o "Meu Drive")

Todo comando rclone roda com `--drive-team-drive <config.rcloneTeamDriveId>` (default `squad.yaml` = `0ABl2cpta6dNRUk9PVA`). Sem esse flag o rclone cria pastas no Meu Drive pessoal do editor — bug conhecido, corrigido na v1.3. Nos exemplos abaixo, `<TD>` = `--drive-team-drive 0ABl2cpta6dNRUk9PVA`.

## Hierarquia destino — modo padrão (v1.4)

```
Drive Compartilhado (raiz)
└── clientes/                                ← preexistente, fuzzy match exato normalizado
    └── <cliente_drive>/                     ← preexistente, fuzzy match (drive_nome | cliente)
        └── cronograma de conteúdo/          ← preexistente, fuzzy match
            └── <ano>/                       ← CRIA se ausente (ex.: 2026)
                └── <mes_extenso>/           ← CRIA se ausente (ex.: junho)
                    └── <DD-MM-YYYY>/        ← CRIA se ausente (ex.: 19-06-2026)
                        ├── <nome_raiz>.mp4
                        └── <nome_raiz>.png  (opcional)
```

Ex.: `gdrive:clientes/Dr Diego Gonzalez/cronograma de conteúdo/2026/junho/19-06-2026/19-06 Diego Gonzalez.mp4`.

## Regra de criação seletiva

| Nível                       | Criar?           | Comportamento se ausente                                            |
|-----------------------------|------------------|---------------------------------------------------------------------|
| `clientes/`                 | **NÃO**          | `failed` (`wrapper_clientes_ausente`) — manual no shared drive      |
| `<cliente_drive>/`          | **NÃO**          | `failed` (`cliente_sem_pasta_no_drive`) — criada no onboarding      |
| `cronograma de conteúdo/`   | **NÃO**          | `failed` (`cronograma_de_conteudo_ausente`) — criada no onboarding  |
| `<ano>/`                    | **SIM** (sob demanda) | `rclone mkdir <ano>` (ex.: `2026`)                            |
| `<mes_extenso>/`            | **SIM** (sob demanda) | `rclone mkdir <mes_extenso>` (ex.: `junho`)                   |
| `<DD-MM-YYYY>/`             | **SIM** (sempre) | `rclone mkdir <DD-MM-YYYY>` (idempotente — reusa se existir)        |

## Lookup obrigatório

Antes do gate, consultar `squads/video-export/config/clientes.yaml` pelo nome do cliente. Decide se vai no **modo padrão** ou **modo override** (`drive_pasta_reels_id`).

## Gate fuzzy (preexistentes, em cascata)

Pra cada wrapper preexistente, em ordem (`clientes/` → `<cliente_drive>/` → `cronograma de conteúdo/`):

1. `rclone lsf "<remote>:<path_atual>" <TD> --dirs-only --max-depth 1` lista irmãos.
2. **Match exato normalizado** primeiro: `normalize(nome) == normalize(alvo)`. Encontrou → usa o nome real (preserva case/acento do Drive). Continua pro próximo nível.
3. **Fallback fuzzy** se nenhum exato:
   - `clientes`: nenhum fuzzy — exige `normalize(nome) == "clientes"`. Ausente → `failed`.
   - `<cliente_drive>`: substring do cliente normalizado no nome da pasta. Empate → melhor ranking por levenshtein. Registra warning em `fuzzy[]`.
   - `cronograma de conteúdo`: pasta cujo nome normalizado contém `"cronograma"` + `"conteudo"`. Aceita variantes do legado (ex.: `"Cronograma de Conteudo"`, `"Cronograma de Conteúdo"`, `"01. Cronograma de Conteúdo"`). Registra warning em `fuzzy[]`.
4. Nenhum match (exato nem fuzzy) → `failed` com motivo específico, sem criar nada.

`normalize(s)` = lowercase → strip diacríticos (NFD), preservando `ç`→`c` → remove pontuação trivial → collapse whitespace → trim.

## Modo override (`drive_pasta_reels_id` no YAML)

Pula o gate dos 3 wrappers. Usa o folder-id como pasta-âncora. Validar que o id resolve dentro do shared drive (`rclone lsf "<remote>:" --drive-root-folder-id <id> <TD> --max-depth 1`). Inválido → `failed` pedindo update do YAML.

Hierarquia destino:
```
<startFolderId — pasta-âncora preexistente>/
└── <subpath renderizado a partir de drive_reels_subpath_template>/
    ├── <nome_raiz>.mp4
    └── <nome_raiz>.png    (opcional)
```

Default do template (se omitido no YAML): `{ano}/{mes_extenso}/{DD-MM-YYYY}` (alinhado com a hierarquia padrão). Template vazio (`""`) → sobe direto na âncora.

No modo override **todo o subpath é criável** (a âncora é a fronteira).

Tokens suportados:

| Token            | Exemplo            |
|------------------|--------------------|
| `{ano}`          | `2026`             |
| `{mes}`          | `06`               |
| `{mes_extenso}`  | `junho`            |
| `{MMMAA}`        | `JUN26`            |
| `{DD-MM}`        | `19-06`            |
| `{DD-MM-YYYY}`   | `19-06-2026`       |

Exemplos:

| Template                              | Subpath gerado pra 19-06-2026     |
|---------------------------------------|-----------------------------------|
| `{ano}/{mes_extenso}/{DD-MM-YYYY}` (default) | `2026/junho/19-06-2026`    |
| `{ano}/{MMMAA}/{DD-MM-YYYY}`          | `2026/JUN26/19-06-2026`           |
| `{DD-MM-YYYY}`                        | `19-06-2026`                      |
| `""` (vazio)                          | (arquivos sobem na raiz da âncora) |

## Conversão de mês

| Número | Extenso (lowercase, criável)  | Abreviado (UPPER, 3 letras pt-br) |
|--------|-------------------------------|------------------------------------|
| 01     | janeiro                       | JAN                                |
| 02     | fevereiro                     | FEV                                |
| 03     | março                         | MAR                                |
| 04     | abril                         | ABR                                |
| 05     | maio                          | MAI                                |
| 06     | junho                         | JUN                                |
| 07     | julho                         | JUL                                |
| 08     | agosto                        | AGO                                |
| 09     | setembro                      | SET                                |
| 10     | outubro                       | OUT                                |
| 11     | novembro                      | NOV                                |
| 12     | dezembro                      | DEZ                                |

`{mes_extenso}` é lowercase (`março` mantém cedilha). `{MMMAA}` é abrev UPPER + ano 2 dígitos (`JUN26`).

**Mês — match fuzzy ao criar:** se já existe pasta reconhecível como o mês alvo em qualquer formato (`junho`, `JUN`, `06`, `JUN26`, `junho-2026`...), reusa. Se não existe nenhuma variante, cria com **extenso lowercase**.

## Transporte: rclone (obrigatório)

> 🚨 O Google Drive MCP rejeita uploads > 10MB. Vídeos editados quase sempre passam disso. A partir da v1.2 o transporte canônico é `rclone copyto`. Drive MCP fica só pra resolver `webViewLink` e IDs pós-upload (leitura).

Pré-requisito validado por Eve no início do pipeline:
- `rclone` no PATH (`Get-Command rclone`)
- `config.rcloneRemote` presente em `rclone listremotes`
- `rclone config show <remote>` retorna `type = drive`

Falha em qualquer um → abortar com mensagem pedindo `/video-export --setup-rclone`.

## Idempotência

Antes de cada upload:
1. `rclone lsjson "<remote>:<path_destino>" <TD> --files-only` lista arquivos.
2. Pra cada arquivo local, procura mesmo `Name` + mesmo `Size`.
3. Match exato → status `skipped`.
4. Existe + tamanho diferente:
   - Sem `--force` → pula + warning.
   - Com `--force` → `rclone copyto` por cima.
5. Pasta-destino ainda não existe → tratar como vazia.

## Upload

```powershell
rclone mkdir "<remote>:<path_destino>" <TD>
rclone copyto "<video_local>" "<remote>:<path_destino>/<video_basename>" <TD> `
  --progress --transfers 1 --drive-chunk-size 64M --retries 2
if ($capa) {
  rclone copyto "<capa_local>" "<remote>:<path_destino>/<capa_basename>" <TD> --retries 2
}
```

Capa null → segundo `copyto` é pulado (não é falha).

## Validação pós-upload

`rclone lsjson "<remote>:<path_destino>" <TD>` confirma vídeo (e capa, quando esperada) com nome e tamanho corretos.
- Capa null + vídeo ok → `ok`.
- Capa esperada + ambos ok → `ok`.
- Vídeo ok, capa esperada mas faltou no destino → `partial`.
- Vídeo faltou → `failed`.

## Resolução de URL pra comentário (Drive MCP — leitura)

`rclone` não retorna URL navegável. Após `copyto`:
1. `google_drive_list_files` na `<path_destino>` → captura `folder.webViewLink` + IDs.
2. Cache `folder.id` por `(cliente, data)` na sessão.
3. Fallback se MCP offline: `rclone link "<remote>:<path_destino>" <TD>`.

## Tratamento de erros comuns

| Erro                                                  | Ação                                                      |
|-------------------------------------------------------|-----------------------------------------------------------|
| `rclone` ausente do PATH                              | Aborta squad — pedir `/video-export --setup-rclone`       |
| Remote `<rcloneRemote>` não existe em `listremotes`   | Aborta squad — pedir `/video-export --setup-rclone`       |
| `rclone copyto` exit ≠ 0 (não-transitório)            | Falha do par, registra stderr no log                      |
| `rclone copyto` exit 5 (rate-limit / transitório)     | 1 retry com backoff 5s, depois falha do par               |
| `clientes/` ausente na raiz do shared drive (modo padrão) | `failed` → `wrapper_clientes_ausente`, criar manualmente |
| Pasta `<cliente_drive>/` ausente dentro de `clientes/` (modo padrão) | `failed` → `cliente_sem_pasta_no_drive`, criar no onboarding do cliente |
| `cronograma de conteúdo/` ausente dentro do cliente (modo padrão) | `failed` → `cronograma_de_conteudo_ausente`, criar no onboarding |
| `drive_pasta_reels_id` inválido / fora do shared drive (modo override) | Falha imediata — pedir atualização do clientes.yaml       |
| `drive_pasta_ano_id` ainda referenciado pra vídeos                      | Ignorado — é campo legado de artes. Use `drive_pasta_reels_id` |
| `--drive-team-drive` ausente / id errado              | Pastas iam parar no Meu Drive — sempre passar `<rcloneTeamDriveId>` do config/squad.yaml |
| Quota do Drive estourada                              | Falha do par, registra pra retry manual                   |
| MCP do Drive offline                                  | Não aborta — usa `rclone link` pra obter URL              |
| `drive_nome` definido no YAML mas pasta não encontrada (mesmo no fuzzy) | Falha — NÃO faz fallback pro nome extraído pelo Scanner  |
