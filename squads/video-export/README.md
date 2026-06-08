# Squad Video Export

Squad de delivery de vídeos editados. Lê pasta-raiz local → sobe pro Drive (via **rclone**) → comenta no ClickUp.

## Pipeline (modo varredura — `/video-export`)

```
[Eve export-chief]  carrega config, valida flags, define escopo, pré-flight do rclone
   │
[Scan scanner]   varre pasta-raiz → lista pares (vídeo, capa, cliente, data)
   │
   ├──► [Match matcher]   busca subtarefa ClickUp por cliente+data    ─┐ (paralelo, lotes de 4)
   │
   ├──► [Up uploader]     rclone copyto vídeo+capa → Drive            ─┤
   │
   └──► [Noti notifier]   comenta link + @resp + status "edição concluída"
```

## Pipeline (modo alvo único — `/video-export-task <id>`)

```
[Eve]  carrega config + pré-flight rclone
   │
[Match em modo REVERSO]  clickup_get_task(id) → deriva cliente + data + parent_assignees
   │
[Scan dirigido]  procura pasta-data esperada (+ fallbacks) → 1 par filtrado
   │
[Up rclone]  upload do par único
   │
[Noti]  comenta na subtask + status
```

## Agentes

| Agente       | Papel                                             | MCPs / Tools                    |
|--------------|---------------------------------------------------|---------------------------------|
| @export-chief   | Orquestrador, onboarding, gestão de cache         | Filesystem                      |
| @scanner     | Varredura de pasta + emparelhamento por nome-raiz | Filesystem, PowerShell          |
| @matcher     | Resolve subtarefa ClickUp dinamicamente           | ClickUp MCP                     |
| @uploader    | Cria pasta no Drive e sobe vídeo + capa           | Google Drive MCP                |
| @notifier    | Comenta no ClickUp + @ + muda status              | ClickUp MCP                     |

## Configuração

### Config do editor (cache local, gerado no onboarding)
Cache em `%USERPROFILE%\.stark-video-export\config.json` (v2 a partir de 2026-06):

```json
{
  "editorEmail": "mateus.redmann@starkmkt.com",
  "videoRoot": "D:\\Edicoes",
  "videoExt": ".mp4",
  "capaExt": ".png",
  "mentionResponsavel": true,
  "rcloneRemote": "gdrive",
  "rcloneTeamDriveId": "0ABl2cpta6dNRUk9PVA",
  "version": 3
}
```

- Para reconfigurar tudo: `/video-export --reconfigure`
- Para reconfigurar só o rclone (re-login, trocar remote): `/video-export --setup-rclone`

### rclone (obrigatório a partir da v1.2)

Por que: o MCP do Google Drive rejeita uploads > 10MB. Vídeos editados quase sempre passam disso. O onboarding (etapa 6) detecta a CLI, instala se faltar (winget/brew/install.sh) e roda `rclone config` pra criar o remote `gdrive:`.

### Overrides por cliente (versionado no repo)
`config/clientes.yaml` lista clientes com estrutura Drive não-padrão:

```yaml
clientes:
  "Dr. Anderson Kuboniwa":
    drive_nome: "Dr. Anderson"
    drive_pasta_ano_id: "1938YPt9KZtC..."

  "Dr. Gilberto Filho":
    drive_pasta_ano_id: "1PU7nohuXw-..."
```

Clientes sem entrada usam a hierarquia padrão automaticamente. Importado do upstream `prep-agenda-stark/config/figma-files.yaml`.

## Convenção de pasta-raiz

```
<videoRoot>\
└── <Cliente>\
    └── <DD-MM-YYYY>\
        ├── reels-01.mp4
        ├── reels-01.png
        └── ...
```

- Cliente = pasta-pai (deve bater com nome no ClickUp/Drive)
- Data = subpasta `DD-MM-YYYY` (fallback: mtime)
- Par = mesmo nome-raiz na mesma pasta

Veja [PRD completo](docs/PRD.md).
