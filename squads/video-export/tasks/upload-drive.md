---
name: upload-drive
owner: uploader
---

# Task: Upload pro Google Drive

Implementado pelo agente Up. Algoritmo completo em [agents/uploader.md](../agents/uploader.md).

## Lookup obrigatório

Antes de construir o caminho, consultar `squads/video-export/config/clientes.yaml` pelo nome do cliente. Decide se vai no **modo padrão** ou **modo override**.

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

## Idempotência

Antes de cada upload:
1. Lista a pasta-destino no Drive.
2. Pra cada arquivo local, procura por mesmo nome.
3. Se encontrado e tamanho idêntico → pula com status `skipped`.
4. Se encontrado e tamanho diferente → sem `--force`, pula e registra warning. Com `--force`, sobrescreve.

## Validação pós-upload

Lista a pasta-destino novamente. Confirma que vídeo e capa estão presentes com nome esperado. Se não → status `partial` ou `failed`.

## Tratamento de erros comuns

| Erro                                                  | Ação                                                      |
|-------------------------------------------------------|-----------------------------------------------------------|
| Pasta `Clientes/<drive_nome>/` não existe (modo padrão) | Falha imediata — pendência, mensagem clara              |
| `drive_pasta_ano_id` inválido (modo override)         | Falha imediata — pedir atualização do clientes.yaml       |
| Quota do Drive estourada                              | Falha do par, registra pra retry manual                   |
| Timeout no upload                                     | 1 retry automático com backoff de 5s, depois falha        |
| MCP do Drive offline                                  | Aborta o squad inteiro com mensagem explícita             |
| `drive_nome` definido no YAML mas pasta não encontrada | Falha — NÃO faz fallback pro nome do ClickUp             |
