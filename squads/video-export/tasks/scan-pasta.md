---
name: scan-pasta
owner: scanner
---

# Task: Scan da pasta-raiz

Implementado pelo agente Scan. Detalhes do algoritmo em [agents/scanner.md](../agents/scanner.md).

## Pseudo-código de referência

```python
def scan(videoRoot, modo, pasta=None, cliente=None, videoExt=".mp4", capaExt=".png"):
    hoje = date.today()
    pastas_alvo = []

    if modo == "pasta":
        pastas_alvo = [pasta]
    elif modo == "hoje":
        # 1. tenta subpasta literal por data
        data_hoje = hoje.strftime("%d-%m-%Y")
        pastas_alvo = glob(f"{videoRoot}/*/{data_hoje}")
        # 2. fallback: qualquer pasta com mtime de arquivo = hoje
        if not pastas_alvo:
            pastas_alvo = [p for p in glob(f"{videoRoot}/*/*")
                           if any_mtime_today(p, videoExt)]
    elif modo == "semana":
        dias_uteis = [hoje - timedelta(days=hoje.weekday()) + timedelta(days=i)
                      for i in range(5)]
        for d in dias_uteis:
            pastas_alvo += glob(f"{videoRoot}/*/{d.strftime('%d-%m-%Y')}")
    elif modo == "all":
        pastas_alvo = glob(f"{videoRoot}/*/*")

    if cliente:
        pastas_alvo = [p for p in pastas_alvo
                       if normalize(parent_of(p)) == normalize(cliente)]

    pares, orfaos = [], []
    for pasta in pastas_alvo:
        videos = glob(f"{pasta}/*{videoExt}")
        capas = glob(f"{pasta}/*{capaExt}")
        capa_by_root = {basename_no_ext(c): c for c in capas}
        for video in videos:
            root = basename_no_ext(video)
            capa = capa_by_root.pop(root, None)
            if capa:
                pares.append({
                    "video": video,
                    "capa": capa,
                    "cliente": parent_of(pasta),
                    "data": data_from_pasta_or_mtime(pasta, video),
                })
            else:
                orfaos.append({"video": video, "motivo": "capa ausente"})
        for capa_orfã in capa_by_root.values():
            orfaos.append({"capa": capa_orfã, "motivo": "vídeo ausente"})

    return {"pares": pares, "orfaos": orfaos}
```

## Output esperado

Veja [agents/scanner.md](../agents/scanner.md) → seção Output.
