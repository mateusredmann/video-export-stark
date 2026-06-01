---
description: "Entrega vídeos editados → Drive + ClickUp. Pasta-raiz é configurada no 1º uso."
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - PowerShell
  - Bash
  - mcp__*__clickup_*
  - mcp__*__google_drive*
argument-hint: "[--hoje | --semana | <pasta> | --cliente \"Nome\"] [--force] [--dry-run] [--reconfigure]"
---

# /video-export

Entry-point do squad Video Export. Lê config local, varre pasta-raiz, sobe vídeo+capa pro Drive e comenta na ClickUp.

## Args recebidos

`$ARGUMENTS` pode conter combinações de:

- `--hoje` — default após onboarding
- `--semana` — segunda a sexta da semana corrente
- `<pasta>` — caminho absoluto pra uma pasta específica
- `--cliente "Nome"` — filtra pelo nome da pasta-pai
- `--force` — sobrescreve no Drive
- `--dry-run` — preview sem efeitos colaterais
- `--reconfigure` — reabre o onboarding

## Comportamento por etapa

### 1. Carregar config

Lê `%USERPROFILE%\.stark-video-export\config.json`.

- Não existe OU `--reconfigure` passado → roda [onboarding](../../squads/video-export/tasks/onboarding.md) e continua.
- Existe → segue direto pro scan.

### 2. Resolver modo

Ordem de precedência:
1. `<pasta>` posicional → `modo=pasta`
2. `--semana` → `modo=semana`
3. `--hoje` ou nada → `modo=hoje`

### 3. Executar pipeline

Despacha pra Eve (export-chief) com o config + modo + flags. Eve cuida da cadeia:

```
Scan → (Match ∥ Up ∥ Noti) por par, lotes de 4 → Relatório
```

Detalhes em [squads/video-export/agents/export-chief.md](../../squads/video-export/agents/export-chief.md).

### 4. Mostrar relatório

Imprime o relatório final consolidado pelo Eve no terminal.

## Exemplos

```
/video-export
/video-export --semana
/video-export "D:\Edicoes\Dr. Rodolfo Soares\27-05-2026"
/video-export --cliente "Dr. Felipe" --hoje
/video-export --semana --dry-run
/video-export --reconfigure
```

## Referência

- [README do squad](../../squads/video-export/README.md)
- [PRD](../../squads/video-export/docs/PRD.md)
- [squad.yaml](../../squads/video-export/squad.yaml)
