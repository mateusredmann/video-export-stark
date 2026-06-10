---
name: export-pasta
trigger: "/video-export <pasta>"
---

# Workflow: Export Pasta

Editor aponta uma pasta específica. A skill processa só o conteúdo dela.

```
1. Eve carrega config.json + pré-flight rclone
2. Valida que <pasta> existe (Test-Path)
3. Scan modo "pasta" (não desce em subpastas-cliente)
4. Pra cada par: Match → Up → Noti (paralelo, lotes de 4)
5. Eve consolida relatório
```

Exemplo: `/video-export "D:\Stark MKT\02 - Videos\2026\2026 - Junho\19-06 Diego Gonzalez"` → cliente = `Diego Gonzalez` (extraído do nome da pasta), data = `19-06-2026` (dia+mês do nome + ano da pasta-avó `2026 - Junho`). Capa `.png` é opcional — sem ela, sobe só vídeo. Variantes `-SEM.mp4` descartadas.

Pasta-avó sem padrão `<ano> - <Mês>` → ano vem do mtime do vídeo. Pasta-alvo que não bate `<DD-MM> <Cliente>` → erro fatal pedindo verificação do path (modo `pasta` é literal).
