---
name: scan-pasta
owner: scanner
---

# Task: Scan da pasta-raiz

Implementado pelo agente Scan. Detalhes do algoritmo em [agents/scanner.md](../agents/scanner.md).

## Estrutura local esperada

```
<videoRoot>\<ano>\<ano> - <Mês>\<DD-MM> <Cliente>\<DD-MM> <Cliente>.mp4
                                                  \<DD-MM> <Cliente>.png   (opcional)
                                                  \<DD-MM> <Cliente>-SEM.mp4  (ignorado)
```

## Pseudo-código de referência

```python
import re

PASTA_REGEX = re.compile(r"^(?P<dia>\d{2})-(?P<mes>\d{2})\s+(?P<cliente>.+)$")
ANO_REGEX = re.compile(r"^(?P<ano>\d{4})\s*-\s*[A-Za-zçáéíóúãõ]+$")

def extrai_cliente_data(pasta_alvo):
    """Retorna (cliente, data, fonte_data, fonte_ano) ou None se a pasta não bate o padrão."""
    nome = basename(pasta_alvo)
    m = PASTA_REGEX.match(nome)
    if not m:
        return None
    dia, mes, cliente = m["dia"], m["mes"], m["cliente"].strip()
    pai = basename(dirname(pasta_alvo))
    m_ano = ANO_REGEX.match(pai)
    if m_ano:
        ano = m_ano["ano"]; fonte_ano = "pasta-avo"
    else:
        ano = str(date.today().year); fonte_ano = "mtime-corrente"
    return cliente, f"{dia}-{mes}-{ano}", "pasta", fonte_ano

def scan(videoRoot, modo, pasta=None, cliente_filtro=None, videoExt=".mp4", capaExt=".png"):
    hoje = date.today()
    pastas_alvo = []

    if modo == "pasta":
        pastas_alvo = [pasta]
    elif modo == "hoje":
        # Varre o videoRoot inteiro filtrando arquivos por mtime
        videos_hoje = [v for v in glob(f"{videoRoot}/**/*{videoExt}", recursive=True)
                       if mtime(v).date() == hoje
                       and not basename_no_ext(v).lower().endswith("-sem")]
        pastas_alvo = list({dirname(v) for v in videos_hoje})
    elif modo == "semana":
        seg, sex = semana_atual()
        videos_semana = [v for v in glob(f"{videoRoot}/**/*{videoExt}", recursive=True)
                         if seg <= mtime(v).date() <= sex
                         and not basename_no_ext(v).lower().endswith("-sem")]
        pastas_alvo = list({dirname(v) for v in videos_semana})
    elif modo == "all":
        pastas_alvo = glob(f"{videoRoot}/**/*", recursive=True)

    pares, orfaos = [], []
    for pasta in pastas_alvo:
        meta = extrai_cliente_data(pasta)
        if meta is None:
            continue  # pasta não bate "<DD-MM> <Cliente>", silenciosamente pulada
        cliente, data, fonte_data, fonte_ano = meta

        if cliente_filtro and normalize(cliente) != normalize(cliente_filtro):
            continue

        videos = [v for v in glob(f"{pasta}/*{videoExt}")
                  if not basename_no_ext(v).lower().endswith("-sem")]
        capas = glob(f"{pasta}/*{capaExt}")
        capa_by_root = {basename_no_ext(c): c for c in capas}

        for video in videos:
            root = basename_no_ext(video)
            capa = capa_by_root.pop(root, None)  # None = sem capa, sobe só vídeo
            pares.append({
                "video": video,
                "capa": capa,
                "cliente": cliente,
                "data": data,
                "fonte_data": fonte_data,
                "fonte_ano": fonte_ano,
            })

        for capa_orfã in capa_by_root.values():
            orfaos.append({"capa": capa_orfã, "motivo": "vídeo ausente"})

    return {"pares": pares, "orfaos": orfaos}
```

## Output esperado

Veja [agents/scanner.md](../agents/scanner.md) → seção Output.
