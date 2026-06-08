---
name: upload-drive
owner: uploader
---

# Task: Upload pro Google Drive

Implementado pelo agente Up. Algoritmo completo em [agents/uploader.md](../agents/uploader.md).

## Alvo: Drive Compartilhado da Stark (não o "Meu Drive")

Todo comando rclone roda com `--drive-team-drive <config.rcloneTeamDriveId>` (default `squad.yaml` = `0ABl2cpta6dNRUk9PVA`). Sem esse flag o rclone cria pastas no Meu Drive pessoal do editor — bug conhecido, corrigido na v1.3. Nos exemplos abaixo, `<TD>` = `--drive-team-drive 0ABl2cpta6dNRUk9PVA`.

**Só sobe pra cliente com pasta oficial nesse shared drive.** Cliente sem pasta → pendência, nunca cria a raiz.

## Lookup obrigatório

Antes de construir o caminho, consultar `squads/video-export/config/clientes.yaml` pelo nome do cliente. Decide se vai no **modo padrão** ou **modo override**.

## Gate (antes de tudo)

Modo padrão: `rclone lsf "<remote>:Clientes/<drive_nome OR cliente>" <TD> --dirs-only` precisa existir. Senão → `failed` (`cliente sem pasta no Drive Compartilhado`), sem criar nada.

## Hierarquia destino — modo padrão

```
Drive raiz
└── Clientes/
    └── <drive_nome OR cliente>/
        └── Cronograma de Conteudo/
            └── Artes/
                └── <ano>/
                    └── <mes-extenso-pt-br>/
                        └── <DD-MM-YYYY>/
                            ├── reels-01.mp4
                            └── reels-01.png
```

## Hierarquia destino — modo override (com drive_pasta_ano_id)

```
<startFolderId — pasta-âncora preexistente>/
└── <MM. mes-extenso>/         ← formato observado nos overrides reais
    └── <DD-MM-YYYY>/
        ├── reels-01.mp4
        └── reels-01.png
```

Exemplos de pastas-âncora reais (Stark):
- `Artes 2026 | Dr. Gilberto Filho`
- `03. Cronograma de Conteúdo | Dr Luciano Esteves`
- `CRIATIVOS INSTAGRAM | DR. ANDERSON`

## Conversão de mês

| Número | Extenso (padrão) | Com prefixo (override) |
|--------|------------------|------------------------|
| 01     | janeiro          | `01. janeiro`          |
| 02     | fevereiro        | `02. fevereiro`        |
| 03     | março            | `03. março`            |
| 04     | abril            | `04. abril`            |
| 05     | maio             | `05. maio`             |
| 06     | junho            | `06. junho`            |
| 07     | julho            | `07. julho`            |
| 08     | agosto           | `08. agosto`           |
| 09     | setembro         | `09. setembro`         |
| 10     | outubro          | `10. outubro`          |
| 11     | novembro         | `11. novembro`         |
| 12     | dezembro         | `12. dezembro`         |

Tudo lowercase, `março` mantém cedilha.

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
rclone copyto "<capa_local>" "<remote>:<path_destino>/<capa_basename>" <TD> --retries 2
```

## Validação pós-upload

`rclone lsjson "<remote>:<path_destino>" <TD>` confirma vídeo+capa com nome e tamanho corretos. Se algum falhou → `partial` ou `failed`.

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
| Pasta `Clientes/<drive_nome>/` não existe no shared drive (modo padrão) | Falha imediata — pendência `cliente sem pasta no Drive Compartilhado`, NÃO cria raiz |
| `drive_pasta_ano_id` inválido / fora do shared drive (modo override) | Falha imediata — pedir atualização do clientes.yaml       |
| `--drive-team-drive` ausente / id errado              | Pastas iam parar no Meu Drive — sempre passar `<rcloneTeamDriveId>` do config/squad.yaml |
| Quota do Drive estourada                              | Falha do par, registra pra retry manual                   |
| MCP do Drive offline                                  | Não aborta — usa `rclone link` pra obter URL              |
| `drive_nome` definido no YAML mas pasta não encontrada | Falha — NÃO faz fallback pro nome do ClickUp             |
