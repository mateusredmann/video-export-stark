# video-export-stark

Squad de IA para automatizar a entrega de vídeos editados da Stark Marketing.

## O que faz

Toda vez que o editor termina um lote de vídeos, ele roda `/video-export` (ou `/video-export-task <id>`) e o squad:

1. Varre a pasta-raiz dos vídeos do editor (ou desce do ClickUp pro filesystem no modo alvo-único)
2. Identifica pares vídeo+capa pelo mesmo nome-raiz
3. Extrai cliente do nome da pasta-pai e data da subpasta (ou `due_date` da subtarefa)
4. Localiza a subtarefa no ClickUp por cliente + data
5. Sobe vídeo + capa pro **Drive Compartilhado da Stark** na hierarquia padrão — via **rclone** (`--drive-team-drive`), sem o cap de 10MB do MCP. Só entrega pra cliente que já tem pasta oficial lá
6. Comenta o link da pasta no ClickUp + @ no responsável
7. Move a subtarefa pra status `edição concluída`

Sem Figma. Cada editor usa seu próprio app de edição — a skill só cuida do delivery.

## Time

| Agente       | Nome    | Papel                                              | Pipeline                          |
|--------------|---------|----------------------------------------------------|-----------------------------------|
| @export-chief   | Eve     | Orquestrador master, onboarding, config local      | `/video-export`, `/video-export-task` |
| @scanner     | Scan    | Varre pasta-raiz, descobre pares vídeo+capa        | `/video-export`                   |
| @matcher     | Match   | Resolve subtarefa ClickUp por cliente+data (e modo reverso) | `/video-export`, `/video-export-task` |
| @uploader    | Up      | Upload pro Google Drive via rclone                 | `/video-export`, `/video-export-task` |
| @notifier    | Noti    | Comenta no ClickUp + @responsável + muda status    | `/video-export`, `/video-export-task` |

## Slash commands

Apenas **dois** entry-points vivem no repo:

### `/video-export` — modo varredura

Varre `videoRoot` por filtro de data ou pasta literal e entrega TODOS os pares que encontrar.

```
/video-export                              # 1ª vez: roda onboarding; depois: --hoje
/video-export --hoje                       # vídeos com mtime = hoje
/video-export --semana                     # seg-sex da semana corrente
/video-export "D:\Edicoes\Dr. X\27-05"     # pasta específica
/video-export --cliente "Dr. Rodolfo"      # só esse cliente
/video-export --force                      # sobrescreve no Drive
/video-export --dry-run                    # preview sem subir
/video-export --reconfigure                # reabre o onboarding inteiro
/video-export --setup-rclone               # roda só a etapa 6 (rclone) do onboarding
/video-export guide                        # abre o manual completo do repositório
```

### `/video-export-task <task_id|URL>` — modo alvo único

Inverte o fluxo: começa pelo ClickUp e desce pro filesystem. Entrega exatamente uma subtarefa.

```
/video-export-task 8gqkmtp                              # ID curto
/video-export-task https://app.clickup.com/t/8gqkmtp    # URL completa
/video-export-task 8gqkmtp --nome-raiz "reels-02"       # pasta tem múltiplos pares
/video-export-task 8gqkmtp --force                      # re-entrega
/video-export-task 8gqkmtp --dry-run                    # preview do comentário + rclone copyto
```

Útil quando uma entrega ficou pra trás e a varredura por `--hoje`/`--semana` não pegaria, ou pra refazer um delivery específico.

## Onboarding (1ª execução)

A skill pergunta:

1. Email do editor no ClickUp
2. Pasta-raiz dos vídeos (ex: `D:\Edicoes`)
3. Extensão do vídeo (`.mp4` default)
4. Extensão da capa (`.png` default)
5. @-mention do responsável da tarefa-mãe? (sim/não)
6. **rclone** — detecta a CLI, instala (winget/brew/install.sh) e roda `rclone config` pra criar o remote `gdrive:`

Salvo em `%USERPROFILE%\.stark-video-export\config.json` (schema v3). Próximas execuções pulam o briefing.

Pra reconfigurar só o rclone (re-login, trocar remote) sem repetir o resto: `/video-export --setup-rclone`.
Configs v1 (sem `rcloneRemote`) e v2 (sem `rcloneTeamDriveId`) ganham migração silenciosa na próxima execução.

> 🚨 **Upload mira o Drive Compartilhado da Stark** (`rcloneTeamDriveId=0ABl2cpta6dNRUk9PVA`), não o "Meu Drive" pessoal — todo comando rclone passa `--drive-team-drive`. A skill só entrega pra cliente que já tem pasta oficial nesse shared drive.

## Convenções

A skill assume a seguinte estrutura na pasta-raiz do editor:

```
D:\Edicoes\
└── [Cliente]\
    └── [DD-MM-YYYY]\
        ├── reels-01.mp4
        ├── reels-01.png
        ├── reels-02.mp4
        └── reels-02.png
```

- **Cliente** = nome da pasta-pai (deve bater com o nome usado no ClickUp/Drive — normalização cuida de acentos e abreviações `Dr.`/`Dr`)
- **Data** = nome da subpasta `DD-MM-YYYY` (fallback: mtime do arquivo)
- **Par vídeo+capa** = mesmo nome-raiz na mesma pasta

## Resultado

```
Drive: [Drive Compartilhado Stark]/Clientes/[cliente]/Cronograma de Conteudo/Artes/[ano]/[mes]/[data]/
ClickUp: subtarefa com comentário + link Drive + status = edição concluída
```

## Overrides por cliente (opcional)

A maioria dos clientes não precisa de nada além do nome da pasta. Mas ~9 clientes da Stark têm estrutura Drive não-padrão — pra esses, `squads/video-export/config/clientes.yaml` traz overrides:

- `drive_nome` — quando a pasta no Drive tem nome diferente da pasta local
- `drive_pasta_ano_id` — quando o cliente tem pasta-âncora fora de `Clientes/<cli>/Cronograma/...`
- `clickup_alias` — quando a tarefa-mãe no ClickUp tem nome diferente da pasta local

Importado do upstream `prep-agenda-stark` — manter sincronizado quando clientes novos ganham estrutura especial.

## Pré-requisitos

- **rclone** ≥ 1.65 com remote `gdrive:` configurado (o onboarding cuida disso na etapa 6)
- Conta Google logada no rclone com **acesso ao Drive Compartilhado da Stark** (`0ABl2cpta6dNRUk9PVA`) — é onde ficam as pastas oficiais dos clientes
- **ClickUp MCP** conectado
- **Google Drive MCP** conectado (apenas leitura — resolver `webViewLink` pós-upload)
- Acesso de leitura na pasta-raiz dos vídeos

## Regras críticas (NÃO violar)

- **FR31 — Sequencial obrigatório no Noti.** `clickup_create_task_comment` + `clickup_update_task` nunca em paralelo na mesma subtarefa. O ClickUp dropa o comentário silenciosamente quando os dois competem.
- **Tudo no Drive Compartilhado, nunca no Meu Drive.** Todo comando rclone roda com `--drive-team-drive <rcloneTeamDriveId>`. Sem o flag o upload cai no "Meu Drive" pessoal do editor (bug corrigido na v1.3).
- **Pasta-âncora preexistente (FR21).** A skill não cria `Clientes/<cliente>/` nem `<startFolderId>` — cliente sem pasta oficial no shared drive vira pendência, nunca cria a raiz.
- **Match é read-only.** Sem subtarefa encontrada → pendência, nunca cria.
- **Mismatch silencioso proibido (FR25a).** Se `drive_nome` está no YAML mas a pasta não existe no Drive, falha — não cai pro `cliente` original.

## Documentação

- [Manual completo do repositório](.claude/commands/video-export.md#manual-do-squad-video-export) — também acessível via `/video-export guide`
- [README do squad](squads/video-export/README.md)
- [PRD completo](squads/video-export/docs/PRD.md)
- [squad.yaml](squads/video-export/squad.yaml)
- [Onboarding detalhado](squads/video-export/tasks/onboarding.md) (etapa 6 = rclone)
