---
name: upload-drive
owner: uploader
---

# Task: Upload pro Google Drive

Implementado pelo agente Up. Algoritmo completo em [agents/uploader.md](../agents/uploader.md).

## Alvo: Drive Compartilhado da Stark (não o "Meu Drive")

Todo comando rclone roda com `--drive-team-drive <config.rcloneTeamDriveId>` (default `squad.yaml` = `0ABl2cpta6dNRUk9PVA`). Sem esse flag o rclone cria pastas no Meu Drive pessoal do editor — bug conhecido, corrigido na v1.3. Nos exemplos abaixo, `<TD>` = `--drive-team-drive 0ABl2cpta6dNRUk9PVA`.

**Só sobe pra cliente com pasta oficial nesse shared drive.** Cliente sem pasta → pendência, nunca cria a raiz.

> 📌 **Raiz do shared drive sem `Clientes/`.** Clientes ficam direto na raiz (`gdrive:Dr Diego Gonzalez/`, `gdrive:Dra Luiza Coutinho/`, ...). Não há wrapper.

## Lookup obrigatório

Antes de construir o caminho, consultar `squads/video-export/config/clientes.yaml` pelo nome do cliente. Decide se vai no **modo padrão** ou **modo override**.

## Gate (antes de tudo)

`rclone lsf "<remote>:<drive_nome OR cliente>" <TD> --dirs-only --max-depth 1` precisa retornar lista (cliente tem pasta-raiz no shared drive). Senão → `failed` (`cliente sem pasta no Drive Compartilhado`), sem criar nada.

No modo override (`drive_pasta_reels_id`), validar que o folderId resolve dentro do shared drive (ex.: `rclone lsf "<remote>:" --drive-root-folder-id <id> <TD> --max-depth 1`).

## Hierarquia destino — modo padrão

```
Drive Compartilhado (raiz)
└── <drive_nome OR cliente>/
    └── 01. Cronograma de Reels | <drive_nome OR cliente>/
        └── <DD-MM-YYYY>/
            ├── <nome_raiz>.mp4
            └── <nome_raiz>.png    (opcional)
```

Ex.: `gdrive:Dr Diego Gonzalez/01. Cronograma de Reels | Dr Diego Gonzalez/19-06-2026/19-06 Diego Gonzalez.mp4`.

## Hierarquia destino — modo override (com drive_pasta_reels_id + template)

```
<startFolderId — pasta-âncora preexistente>/
└── <subpath renderizado a partir de drive_reels_subpath_template>/
    ├── <nome_raiz>.mp4
    └── <nome_raiz>.png    (opcional)
```

Default do template (se omitido no YAML): `{DD-MM-YYYY}`. Template vazio (`""`) → sobe direto na âncora.

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

| Template                          | Subpath gerado pra 19-06-2026     |
|-----------------------------------|-----------------------------------|
| `{DD-MM-YYYY}` (default)          | `19-06-2026`                      |
| `{ano}/{MMMAA}/{DD-MM-YYYY}`      | `2026/JUN26/19-06-2026`           |
| `{ano}/{mes_extenso}/{DD-MM}`     | `2026/junho/19-06`                |
| `""` (vazio)                      | (arquivos sobem na raiz da âncora) |

## Conversão de mês

| Número | Extenso (lowercase, pt-br) | Abreviado (UPPER, pt-br 3 letras) |
|--------|---------------------------|------------------------------------|
| 01     | janeiro                   | JAN                                |
| 02     | fevereiro                 | FEV                                |
| 03     | março                     | MAR                                |
| 04     | abril                     | ABR                                |
| 05     | maio                      | MAI                                |
| 06     | junho                     | JUN                                |
| 07     | julho                     | JUL                                |
| 08     | agosto                    | AGO                                |
| 09     | setembro                  | SET                                |
| 10     | outubro                   | OUT                                |
| 11     | novembro                  | NOV                                |
| 12     | dezembro                  | DEZ                                |

`{mes_extenso}` é lowercase (`março` mantém cedilha). `{MMMAA}` é abrev UPPER + ano 2 dígitos (`JUN26`).

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
| Pasta `<drive_nome>/` não existe no shared drive (modo padrão)         | Falha imediata — pendência `cliente sem pasta no Drive Compartilhado`, NÃO cria raiz |
| Pasta-âncora `01. Cronograma de Reels | <cliente>` ausente (modo padrão) | Falha imediata — pasta criada manualmente no onboarding do cliente, fora desta skill |
| `drive_pasta_reels_id` inválido / fora do shared drive (modo override) | Falha imediata — pedir atualização do clientes.yaml       |
| `drive_pasta_ano_id` ainda referenciado pra vídeos                      | Ignorado — é campo legado de artes. Use `drive_pasta_reels_id` |
| `--drive-team-drive` ausente / id errado              | Pastas iam parar no Meu Drive — sempre passar `<rcloneTeamDriveId>` do config/squad.yaml |
| Quota do Drive estourada                              | Falha do par, registra pra retry manual                   |
| MCP do Drive offline                                  | Não aborta — usa `rclone link` pra obter URL              |
| `drive_nome` definido no YAML mas pasta não encontrada | Falha — NÃO faz fallback pro nome do ClickUp             |
