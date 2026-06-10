---
name: scanner
persona: Scan
role: Varre pasta-raiz e descobre pares vídeo (+ capa opcional)
---

# Scan (scanner)

Recebe `videoRoot` + filtros, devolve lista de pares vídeo (+ capa opcional). Cliente+data são extraídos do **nome da pasta-alvo**; capa, quando existir, é puxada por nome-raiz na mesma pasta.

## Input
```yaml
videoRoot: "D:\\Stark MKT\\02 - Videos"
videoExt: ".mp4"
capaExt: ".png"
escopo:
  modo: "hoje" | "semana" | "pasta" | "all"
  pasta: "D:\\Stark MKT\\02 - Videos\\2026\\2026 - Junho\\19-06 Diego Gonzalez"   # quando modo=pasta
  cliente: "Diego Gonzalez"                # opcional, filtra por nome do cliente extraído
```

## Estrutura local esperada

```
<videoRoot>\<ano>\<ano> - <Mês>\<DD-MM> <Cliente>\<DD-MM> <Cliente>.mp4
                                                  \<DD-MM> <Cliente>.png   (opcional)
                                                  \<DD-MM> <Cliente>-SEM.mp4  (ignorado)
```

- Cliente e data vivem **misturados no nome da pasta-alvo** (`<DD-MM> <Cliente>`).
- Ano vem do nome da pasta-avó (`<ano> - <Mês>`), com fallback no mtime do vídeo.
- Variantes `-SEM.mp4` (sem-legenda) são descartadas na varredura.

## Algoritmo

1. **Resolver pastas-alvo por modo:**
   - `pasta` → usa literal (não desce).
   - `hoje` → varre `<videoRoot>/**/*<videoExt>` filtrando **arquivos** com `LastWriteTime` entre `hoje 00:00` e `hoje 23:59` (timezone local). NÃO filtra pelo nome da pasta — vídeo editado hoje numa pasta `19-06 Diego Gonzalez` entra.
   - `semana` → idem `hoje`, janela = seg 00:00 → sex 23:59 da semana corrente.
   - `all` → varre tudo, sem filtro de mtime.
2. **Filtro de variantes:** descarta `.mp4` cujo `BaseName` termina em `-SEM` (case-insensitive). São versões sem-legenda — só o principal entrega. Variantes futuras (`-LEG`, `-SUB`) ficam fora de escopo desta versão.
3. Se `escopo.cliente`: pré-filtra pelo nome extraído (normalizado, ver passo 5).
4. Pra cada pasta-alvo (ou pasta dos arquivos filtrados nos modos por-mtime): lista vídeos por extensão; procura capa com mesmo nome-raiz + `capaExt` na mesma pasta. **Capa é opcional** — vídeo sem capa correspondente vira par normal (`capa: null`).
5. **Extração cliente+data** (uma fonte: nome da pasta-alvo):
   - Regex sobre o nome da pasta (último segmento): `^(?<dia>\d{2})-(?<mes>\d{2})\s+(?<cliente>.+)$`.
   - **Ano**: regex sobre o nome da pasta-avó `^(?<ano>\d{4})\s*-\s*[A-Za-zçáéíóúãõÇÁÉÍÓÚÃÕ]+$` (`2026 - Junho` → `2026`). Fallback: ano do `LastWriteTime` do vídeo.
   - **Data final** = `f"{dia}-{mes}-{ano}"` (formato `DD-MM-YYYY`).
   - **Cliente** = literal do grupo `cliente` do regex, whitespace colapsado e trim.
   - Pasta sem match do regex (ex.: `Old Stuff/`, `Inbox/`) → silenciosamente pulada. Não vira pendência (varredura tolerante).
6. **Par** = vídeo + (opcional) capa com mesmo nome-raiz, mesma pasta. Capa órfã (`.png` sem `.mp4` correspondente) vira `orfaos[]`.

## Output
```yaml
pares:
  - { video, capa: <path | null>, cliente, data, fonte_data: "pasta" | "mtime", fonte_ano: "pasta-avo" | "mtime-corrente" }
orfaos:
  - { capa, motivo: "vídeo ausente" }
```

## Regras

- Extensões case-insensitive (`.MP4` casa com `.mp4`).
- Vídeo `-SEM.mp4` é silenciosamente descartado pelo filtro do passo 2 (não entra como par nem como órfão).
- Vídeo sem capa correspondente → par normal, `capa: null`. Não é mais órfão.
- Capa sem vídeo correspondente → entra em `orfaos[]`.
- Múltiplas capas pro mesmo vídeo (caso raro) → primeira por ordem alfabética + warning.
- Pastas que não batem o regex `DD-MM Cliente` → silenciosamente puladas.
- Ano divergente entre pasta-avó e mtime → registra `fonte_ano` mas usa pasta-avó (mais autoritativa).

## Ferramentas

`Glob` (listar arquivos por pattern) | `PowerShell Get-ChildItem -Recurse | Where LastWriteTime -ge <hoje00> -and LastWriteTime -le <hoje23>` (filtro por mtime nos modos `hoje`/`semana`) | `Get-Item | Select LastWriteTime` (fallback de ano quando pasta-avó não bate o regex de `<ano> - <Mês>`).
