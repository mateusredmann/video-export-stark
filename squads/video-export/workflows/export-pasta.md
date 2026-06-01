---
name: export-pasta
trigger: "/video-export <pasta>"
---

# Workflow: Export Pasta (modo manual)

Editor aponta uma pasta específica. A skill processa só o conteúdo dessa pasta.

## Pipeline

```
1. Eve carrega config.json (ou dispara onboarding se ausente)
2. Eve valida que <pasta> existe
3. Scan varre <pasta> em modo "pasta"
4. Pra cada par retornado: dispara em paralelo
     ├─ Match resolve subtarefa ClickUp
     ├─ Up faz upload Drive
     └─ Noti comenta + muda status
5. Eve consolida relatório
```

## Exemplo

```
/video-export "D:\Edicoes\Dr. Rodolfo Soares\27-05-2026"
```

Scan encontra:
```
- reels-01.mp4 + reels-01.png
- reels-02.mp4 + reels-02.png
- reels-03.mp4 (sem capa → órfão)
```

Cliente extraído da pasta-pai = `Dr. Rodolfo Soares`.
Data extraída da subpasta = `27-05-2026`.

Processa os 2 pares em paralelo, registra o órfão na pendência.

## Edge cases

- **Pasta sem subpasta-data** (ex: `D:\Edicoes\Dr. X\videos-soltos`): Scan usa mtime como data. Pode resultar em datas diferentes pro mesmo lote — comportamento esperado.
- **Pasta no formato errado** (não tem cliente identificável): Eve avisa e oferece input manual de cliente. (v1: avisa e pula.)
