---
name: export-semana
trigger: "/video-export --semana"
---

# Workflow: Export Semana

Sobe tudo editado na semana corrente (segunda a sexta).

## Pipeline

```
1. Eve carrega config.json
2. Eve calcula janela: segunda 00:00 → sexta 23:59 da semana corrente (timezone local)
3. Scan varre videoRoot em modo "semana":
     - tenta subpastas literais videoRoot/*/<DD-MM-YYYY> pra cada dia útil
     - fallback: filtra arquivos com mtime dentro da janela
4. Agrupa pares por (cliente, data) → dispara lotes paralelos
5. Eve consolida relatório com sub-totais por dia
```

## Sub-totais no relatório

```
✅ Video Export — semana 25/05 a 29/05/2026

Segunda 25/05 — 3 pares
Terça   26/05 — 5 pares
Quarta  27/05 — 4 pares
Quinta  28/05 — 0 pares
Sexta   29/05 — 6 pares

Total: 18 pares
Sucesso: 17
Pendências: 1
  • [Dra. X] 26-05 reels-02 — par órfão (capa ausente)
```

## Performance

Com 4 uploads simultâneos e ~30s por par (vídeo+capa pequenos), uma semana de 20 pares roda em ~3-4 min.
