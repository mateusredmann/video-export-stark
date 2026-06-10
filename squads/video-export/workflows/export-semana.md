---
name: export-semana
trigger: "/video-export --semana"
---

# Workflow: Export Semana

Sobe tudo editado na semana corrente (segunda a sexta, timezone local).

## Pipeline

```
1. Eve carrega config.json + pré-flight rclone
2. Calcula janela seg 00:00 → sex 23:59 (timezone local)
3. Scan modo "semana": varre <videoRoot>/**/*<videoExt> filtrando arquivos com mtime na janela
                       (ignora -SEM.mp4); extrai cliente+data do nome da pasta-alvo
4. Agrupa por (cliente, data), dispara lotes paralelos
5. Eve consolida relatório com sub-totais por dia útil (formato em [export-chief.md](../agents/export-chief.md))
```
