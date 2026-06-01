# video-export-stark

Squad de IA para automatizar a entrega de vídeos editados da Stark Marketing.

## O que faz

Toda vez que o editor termina um lote de vídeos, ele roda `/video-export` e o squad vai:

1. Varrer a pasta-raiz dos vídeos do editor
2. Identificar pares vídeo+capa pelo mesmo nome-raiz
3. Extrair cliente do nome da pasta-pai e data da subpasta (ou mtime)
4. Localizar a subtarefa no ClickUp por cliente + data
5. Subir vídeo + capa pro Google Drive na hierarquia padrão
6. Comentar o link da pasta no ClickUp + @ no responsável
7. Mover a subtarefa pra status `edição concluída`

Sem Figma. Cada editor usa seu próprio app de edição — a skill só cuida do delivery.

## Time

| Agente       | Nome    | Papel                                              | Pipeline      |
|--------------|---------|----------------------------------------------------|---------------|
| @export-chief   | Eve     | Orquestrador master                                | /video-export   |
| @scanner     | Scan    | Varre pasta-raiz, descobre pares vídeo+capa        | /video-export   |
| @matcher     | Match   | Resolve cliente da pasta-pai → subtarefa ClickUp   | /video-export   |
| @uploader    | Up      | Upload pro Google Drive                            | /video-export   |
| @notifier    | Noti    | Comenta no ClickUp + @responsável + muda status    | /video-export   |

## Como usar

```
/video-export                             # 1ª vez: roda onboarding; depois: --hoje
/video-export --hoje                      # vídeos com mtime = hoje
/video-export --semana                    # seg-sex da semana corrente
/video-export "D:\Edicoes\Dr. X\27-05"    # pasta específica
/video-export --cliente "Dr. Rodolfo"     # só esse cliente
/video-export --force                     # sobrescreve no Drive
/video-export --reconfigure               # reabre o onboarding
/video-export --dry-run                   # lista o que faria sem subir
```

## Onboarding (1ª execução)

A skill pergunta:

1. Email do editor no ClickUp
2. Pasta-raiz dos vídeos (ex: `D:\Edicoes`)
3. Extensão do vídeo (`.mp4` default)
4. Extensão da capa (`.png` default)
5. @-mention do responsável da tarefa-mãe? (sim/não)

Salvo em `%USERPROFILE%\.stark-video-export\config.json`. Próximas execuções pulam o briefing.

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

- **Cliente** = nome da pasta-pai (deve bater com o nome usado no ClickUp/Drive)
- **Data** = nome da subpasta `DD-MM-YYYY` (fallback: mtime do arquivo)
- **Par vídeo+capa** = mesmo nome-raiz na mesma pasta

## Resultado

```
Drive: Clientes/[cliente]/Cronograma de Conteudo/Artes/[ano]/[mes]/[data]/
ClickUp: subtarefa com comentário + link Drive + status = edição concluída
```

## Overrides por cliente (opcional)

A maioria dos clientes não precisa de nada além do nome da pasta. Mas ~9 clientes da Stark têm estrutura Drive não-padrão — pra esses, `squads/video-export/config/clientes.yaml` traz overrides:

- `drive_nome` — quando a pasta no Drive tem nome diferente da pasta local
- `drive_pasta_ano_id` — quando o cliente tem pasta-âncora fora de `Clientes/<cli>/Cronograma/...`

Importado do upstream `prep-agenda-stark` — manter sincronizado quando clientes novos ganham estrutura especial.

## Pré-requisitos

- ClickUp MCP conectado
- Google Drive MCP conectado
- Acesso de leitura na pasta-raiz dos vídeos

## Documentação

- [PRD completo](squads/video-export/docs/PRD.md)
- [Configuração do squad](squads/video-export/squad.yaml)
