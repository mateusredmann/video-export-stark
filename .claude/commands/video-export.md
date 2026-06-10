---
description: "Entrega vídeos editados → Drive (via rclone) + ClickUp. Use `/video-export guide` pra abrir o manual do repositório."
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - PowerShell
  - Bash
  - mcp__*__clickup_*
  - mcp__*__google_drive*
argument-hint: "[guide | --hoje | --semana | <pasta> | --cliente \"Nome\"] [--force] [--dry-run] [--reconfigure | --setup-rclone]"
---

# /video-export

Entry-point do squad. Lê config local, varre pasta-raiz, sobe vídeo+capa pro Drive (rclone) e comenta no ClickUp.

## `guide` — abre o manual

Se o primeiro token de `$ARGUMENTS` for `guide` (case-insensitive), leia e imprima o conteúdo de [`squads/video-export/docs/MANUAL.md`](../../squads/video-export/docs/MANUAL.md) como markdown e encerre o turno. Não rode tools, não toque ClickUp/Drive. Argumentos depois de `guide` são ignorados.

Caso contrário, segue o pipeline abaixo.

## Args

Flags combinam livremente:

- `--hoje` (default pós-onboarding) — sobe **união** de (a) arquivos com `mtime`=hoje no `videoRoot` + (b) subtarefas ClickUp com `due_date`=hoje atribuídas ao `editorEmail`. Não usa o nome da pasta-local como gatilho.
- `--semana` (seg-sex, mtime na janela) | `<pasta>` absoluta (modo pasta) | `--cliente "Nome"`
- `--force` (sobrescreve Drive) | `--dry-run` (preview)
- `--reconfigure` (onboarding completo) | `--setup-rclone` (só etapa 6)

## Etapas

1. **Config:** lê `%USERPROFILE%\.stark-video-export\config.json`. Se ausente ou `--reconfigure` → roda [onboarding](../../squads/video-export/tasks/onboarding.md). v1 → roda só etapa 6 (sobe pra v2). v2 → injeta `rcloneTeamDriveId=0ABl2cpta6dNRUk9PVA` sem perguntar (v3). `--setup-rclone` força só a etapa 6.
2. **Pré-flight rclone:** `Get-Command rclone` + `rclone listremotes` contém o remote + `rclone config show <remote>` tipo `drive` + `rclone lsd <remote>: --drive-team-drive <rcloneTeamDriveId> --max-depth 1` retorna a lista de clientes (clientes ficam direto na raiz do shared drive; não há wrapper `Clientes/`). Falhou qualquer um → aborta com `/video-export --setup-rclone`.
3. **Modo:** `<pasta>` posicional > `--semana` > `--hoje`/default.
4. **Pipeline:** despacha pra Eve ([export-chief](../../squads/video-export/agents/export-chief.md)) → `Scan → (Match ∥ Up ∥ Noti)` em lotes de 4 → relatório.

> 🚨 Todo comando rclone roda com `--drive-team-drive <rcloneTeamDriveId>` (default `0ABl2cpta6dNRUk9PVA`). Sem o flag, upload cai no "Meu Drive" pessoal. Só sobe pra cliente com pasta oficial nesse shared drive.

## Exemplos

```
/video-export
/video-export --semana
/video-export "D:\Stark MKT\02 - Videos\2026\2026 - Junho\19-06 Diego Gonzalez"
/video-export --cliente "Diego Gonzalez" --hoje
/video-export --semana --dry-run
/video-export --reconfigure
/video-export guide
```

## Referência

- Manual completo: `/video-export guide` (ou [docs/MANUAL.md](../../squads/video-export/docs/MANUAL.md))
- [README do squad](../../squads/video-export/README.md), [squad.yaml](../../squads/video-export/squad.yaml), [PRD](../../squads/video-export/docs/PRD.md)
