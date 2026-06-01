# Squad Video Export

Squad de delivery de vídeos editados. Lê pasta-raiz local → sobe pro Drive → comenta no ClickUp.

## Pipeline

```
[Eve export-chief]  carrega config, valida flags, define escopo
   │
[Scan scanner]   varre pasta-raiz → lista pares (vídeo, capa, cliente, data)
   │
   ├──► [Match matcher]   busca subtarefa ClickUp por cliente+data    ─┐ (paralelo, lotes de 4)
   │
   ├──► [Up uploader]     upload Drive: Clientes/[cli]/.../[data]/    ─┤
   │
   └──► [Noti notifier]   comenta link + @resp + status "edição concluída"
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
Cache em `%USERPROFILE%\.stark-video-export\config.json`:

```json
{
  "editorEmail": "mateus.redmann@starkmkt.com",
  "videoRoot": "D:\\Edicoes",
  "videoExt": ".mp4",
  "capaExt": ".png",
  "mentionResponsavel": true,
  "version": 1
}
```

Para reconfigurar: `/video-export --reconfigure`.

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
