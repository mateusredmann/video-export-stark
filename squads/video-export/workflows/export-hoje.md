---
name: export-hoje
trigger: "/video-export --hoje  (ou /video-export sozinho após onboarding)"
---

# Workflow: Export Hoje

Sobe tudo que foi editado hoje. Modo default quando o editor já tem config.

## Pipeline

```
1. Eve carrega config.json
2. Scan varre videoRoot em modo "hoje":
     - tenta subpastas literais videoRoot/*/<DD-MM-YYYY-hoje>
     - se vazio: filtra arquivos com mtime = hoje
3. Pra cada par: Match → Up → Noti (paralelo, lotes de 4)
4. Eve consolida relatório
```

## Critério "hoje"

`hoje` = data local do sistema (Brasília). A skill não faz timezone gymnastics — confia no relógio do Windows.

Se o editor virou a noite editando, ele pode forçar:
```
/video-export --semana
```
ou apontar a pasta literal:
```
/video-export "D:\Edicoes\Cliente\27-05-2026"
```

## Output

Mesmo formato do relatório consolidado da Eve. Veja [agents/export-chief.md](../agents/export-chief.md).
