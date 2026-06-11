# video-export-stark

Squad de IA que automatiza a entrega de vídeos editados da Stark Marketing.

## O que faz

Editor termina um lote → roda `/video-export` (ou `/video-export-task <id|url|caminho>`):

1. Varre pasta-raiz local (ou desce do ClickUp pro filesystem no modo alvo-único).
2. Empareha vídeo + (opcional) capa pelo nome-raiz. Cliente+data extraídos do nome da pasta-alvo (`<DD-MM> <Cliente>`); ano da pasta-avó (`<ano> - <Mês>`). Variantes `-SEM.mp4` descartadas.
3. Localiza subtarefa no ClickUp por cliente+data (ou pelo `task_id` direto).
4. Sobe pro **Drive Compartilhado da Stark** via rclone (`--drive-team-drive`, sem cap de 10MB). Destino default (v1.5): `clientes/<cliente_drive>/Cronograma de Conteúdo/<ano>/artes/<mes_extenso>/<DD-MM-YYYY>/`. 4 wrappers preexistentes (`clientes`, `<cliente_drive>`, `Cronograma de Conteúdo`, `artes`) — skill nunca cria nenhum deles. Só entrega pra cliente que já tem pasta-raiz e pasta-âncora oficiais.
5. Comenta link da pasta + @ responsável + status = `edição concluída`.

Sem Figma. Cada editor usa seu próprio app de edição.

## Time

| Agente | Persona | Papel |
|---|---|---|
| @export-chief | Eve | Orquestrador, onboarding, config, relatório |
| @scanner | Scan | Varre pasta-raiz, descobre pares |
| @matcher | Match | Resolve subtarefa ClickUp (modos forward, reverso, path) |
| @uploader | Up | Upload Drive via rclone |
| @notifier | Noti | Comenta + @resp + muda status (sequencial FR31) |

## Slash commands

| Comando | Uso |
|---|---|
| `/video-export` | Varredura — default = `--hoje` após onboarding |
| `/video-export --hoje \| --semana` | Filtro de data |
| `/video-export "<pasta>"` | Só essa pasta literal |
| `/video-export --cliente "Dr. X" \| --force \| --dry-run` | Filtros/flags |
| `/video-export --reconfigure \| --setup-rclone` | Re-config |
| `/video-export-task <task_id\|URL\|caminho>` | Alvo único — refazer uma entrega ou subir um item específico |
| `/video-export guide` | Manual completo do repositório |

## Onboarding (1ª execução)

A skill pergunta: email ClickUp, pasta-raiz, extensão vídeo/capa, @-mention sim/não, e configura **rclone** (etapa 6 detecta CLI, instala via winget/brew/install.sh, cria remote `gdrive:`). Config salva em `%USERPROFILE%\.stark-video-export\config.json` (v3).

Re-config: `/video-export --reconfigure` (tudo) ou `/video-export --setup-rclone` (só etapa 6). Configs antigas migram sozinhas na próxima execução.

> 🚨 Upload mira o Drive Compartilhado da Stark (`rcloneTeamDriveId=0ABl2cpta6dNRUk9PVA`) via `--drive-team-drive`, não o Meu Drive pessoal. Só entrega pra cliente com pasta oficial nesse shared drive.

## Documentação

- Manual completo: `/video-export guide` → [docs/MANUAL.md](squads/video-export/docs/MANUAL.md)
- [PRD completo](squads/video-export/docs/PRD.md) — todos os FRs
- [squad.yaml](squads/video-export/squad.yaml) — metadata, MCPs, ferramentas externas
- [Onboarding detalhado](squads/video-export/tasks/onboarding.md) — etapa 6 (rclone)
- [clientes.yaml](squads/video-export/config/clientes.yaml) — overrides por cliente (`drive_nome`, `drive_pasta_reels_id`, `drive_reels_subpath_template`, `clickup_alias`)
