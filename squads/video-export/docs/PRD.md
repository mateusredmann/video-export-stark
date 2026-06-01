# Squad Video Export — PRD

**Owner:** Mateus Redmann | **Status:** Draft (v1.1) | **Atualizado:** 2026-06-01

---

## 1. Objetivo

Automatizar a entrega de vídeos editados pelos editores da Stark. Cada editor usa um app de edição diferente (Premiere, DaVinci, CapCut, etc.), então não tem etapa de Figma. A skill cuida só do **delivery**: vídeo local → Drive → comentário na ClickUp.

| Workflow         | Comando                                     | Quando                          | Tempo alvo |
|------------------|---------------------------------------------|----------------------------------|------------|
| Onboarding       | `/video-export` (1ª vez) ou `--reconfigure`   | Setup inicial / mudou config     | ~2 min     |
| Export Pasta     | `/video-export <pasta>`                       | Editor entregou um lote          | ~30s/par   |
| Export Hoje      | `/video-export --hoje`                        | Fim do dia, sobe tudo            | ~30s/par   |
| Export Semana    | `/video-export --semana`                      | Sexta à noite, fechamento        | ~30s/par   |

Zero interação humana após o disparo (depois do onboarding).

---

## 2. Pipeline

```
[Eve export-chief] valida flags, carrega ou cria config
   │
[Scan scanner]  varre videoRoot → pares (video, capa, cliente, data)
   │
   └─► por par, em paralelo (lotes de 4):
        ├─ [Match matcher]  busca subtarefa ClickUp por cliente+data
        ├─ [Up uploader]    cria pasta Drive, sobe vídeo + capa
        └─ [Noti notifier]  comenta link + @resp + status "edição concluída"
   │
[Eve export-chief] consolida relatório (sucessos + pendências)
```

---

## 3. Requisitos Funcionais

### Eve — Orquestração
- **FR1:** Carregar `%USERPROFILE%\.stark-video-export\config.json`. Se ausente, executar onboarding antes.
- **FR2:** Suportar flags: `--hoje`, `--semana`, `--cliente`, `--force`, `--reconfigure`, `--dry-run`, e `<pasta>` posicional.
- **FR3:** Falha em um par não aborta os demais; consolida tudo no relatório final.
- **FR4:** Gerar log de execução em `%USERPROFILE%\.stark-video-export\logs\<timestamp>.log`.

### Onboarding
- **FR5:** Perguntar email ClickUp, pasta-raiz, extensão de vídeo, extensão de capa, opção de @-mention.
- **FR6:** Validar que a pasta-raiz existe (não exige que esteja preenchida).
- **FR7:** Salvar `config.json` com versão (`version: 1`) pra permitir migração futura.
- **FR8:** `--reconfigure` reabre todas as perguntas com defaults vindos da config anterior.

### Scan — Varredura
- **FR9:** Listar pares vídeo+capa por mesmo nome-raiz na mesma pasta.
- **FR10:** Extrair cliente do nome da pasta-pai (1 nível acima da pasta da data).
- **FR11:** Extrair data da subpasta no formato `DD-MM-YYYY`; fallback = `mtime` do vídeo.
- **FR12:** Filtros temporais: `--hoje`, `--semana`. Modo `pasta` ignora filtros temporais.
- **FR13:** Filtro `--cliente` normaliza acentos/case na comparação com a pasta-pai.
- **FR14:** Reportar órfãos (vídeo sem capa, capa sem vídeo) sem bloquear os pares válidos.

### Match — ClickUp
- **FR15:** Buscar subtarefa por `<cliente> <data-DD-MM>` via `clickup_search` ou `clickup_filter_tasks`.
- **FR16:** Ranking favorece match em path/lista do cliente + match de data no nome.
- **FR17:** Sem score mínimo atingido → marcar como `não encontrado` (pendência).
- **FR18:** Ler `assignees` da tarefa-mãe pra @-mention futura.
- **FR19:** Match é **read-only** no ClickUp.
- **FR19a:** Normalização obrigatória do nome do cliente antes de comparar: remover pontos de abreviação (`Dr.` → `Dr`), lowercase, remover acentos, colapsar whitespace. Anti-duplicação.
- **FR19b:** Consultar `clickup_alias` em `config/clientes.yaml` se disponível antes da busca.

### Up — Upload
- **FR20:** Hierarquia destino padrão: `Clientes/<drive_nome OR cliente>/Cronograma de Conteudo/Artes/<ano>/<mes-extenso>/<DD-MM-YYYY>/`.
- **FR20a:** Modo override (quando cliente tem `drive_pasta_ano_id` em `clientes.yaml`): `<startFolderId>/<MM. mês>/<DD-MM-YYYY>/`. Pula a navegação automática.
- **FR20b:** Lookup obrigatório em `config/clientes.yaml` antes de construir o caminho. Campos: `drive_nome`, `drive_pasta_ano_id`, `clickup_alias`.
- **FR21:** Criar subpastas faltantes; **não** criar `Clientes/<cliente>/` nem a pasta-âncora `<startFolderId>` (ambas assumidas preexistentes, falha se não).
- **FR22:** Idempotência: skip se arquivo já existe com mesmo nome e tamanho. `--force` sobrescreve.
- **FR23:** Upload paralelo vídeo+capa pra mesma pasta-destino.
- **FR24:** Validação pós-upload: listar pasta-destino e confirmar presença.
- **FR25:** 1 retry automático em timeout (backoff 5s); depois falha.
- **FR25a:** Mismatch silencioso proibido: se `drive_nome` está no YAML mas a pasta não existe no Drive, falha — não cai pra `cliente`.

### Noti — Notificação
- **FR26:** Postar comentário no template padrão Stark:
  ```
  ✅ Edição concluída.
  Ref: <cliente> — <DD-MM> <nome_raiz>
  Entregue: vídeo (.mp4) + capa (.png)

  🔗 Drive: <drive_folder_url>
  ```
- **FR27:** Se `mentionResponsavel=true`, prefixar com `@<responsável>` baseado nos `assignees` da tarefa-mãe.
- **FR28:** Atualizar status da subtarefa pra `edição concluída` via `clickup_update_task`.
- **FR29:** Se o status não existe na lista, manter status atual e marcar como `comment_ok_status_fail`.
- **FR30:** `--dry-run`: monta o payload e devolve preview, sem chamar a API.
- **FR31:** **CRÍTICO — Sequencial obrigatório:** `clickup_create_task_comment` e `clickup_update_task` NUNCA executam em paralelo. Ordem: comentário primeiro (await), status depois. ClickUp dropa comentário silenciosamente quando há corrida.

---

## 4. Regras de Negócio

### Estrutura de pasta esperada
```
<videoRoot>\<Cliente>\<DD-MM-YYYY>\<nome-raiz>.<ext>
```

### Conversão local → Drive
| Local (input editor)            | Drive (output)                                            |
|---------------------------------|-----------------------------------------------------------|
| Pasta-pai do vídeo              | `Clientes/<pasta-pai>/`                                   |
| Subpasta `DD-MM-YYYY`           | `Cronograma de Conteudo/Artes/<ano>/<mês>/<DD-MM-YYYY>/`  |
| `nome-raiz.mp4` + `nome-raiz.png` | mesmos nomes, mesma pasta-destino                       |

### Idempotência
- Arquivo destino existe com mesmo tamanho → pula
- Arquivo destino existe com tamanho diferente + sem `--force` → pula com warning
- `--force` → sobrescreve sempre
- Comentário ClickUp não é deduplicado (re-rodar duplica o comentário)

### Status final
- Sempre `edição concluída`. Não é configurável no v1.
- Se o status não existir na lista, comentário ainda vai (FR29).

---

## 5. Arquitetura

| Agente       | Persona | MCPs / Tools                          |
|--------------|---------|---------------------------------------|
| @export-chief   | Eve     | Filesystem                            |
| @scanner     | Scan    | Filesystem, PowerShell (mtime)        |
| @matcher     | Match   | ClickUp MCP (read)                    |
| @uploader    | Up      | Google Drive MCP (write), Filesystem  |
| @notifier    | Noti    | ClickUp MCP (write)                   |

---

## 6. Requisitos Não-Funcionais

| #     | Requisito                                  | Alvo                  |
|-------|--------------------------------------------|-----------------------|
| NFR1  | Performance por par                        | ≤ 30s (vídeos ≤ 50MB) |
| NFR2  | Paralelismo de uploads                     | 4 simultâneos         |
| NFR3  | Taxa de sucesso por par                    | ≥ 95%                 |
| NFR4  | Interação humana após disparo              | Zero                  |
| NFR5  | Credenciais                                | Via MCPs autenticados |
| NFR6  | Plataforma                                 | Windows 11 + MCPs     |
| NFR7  | Onboarding rodado 1 vez                    | Cache local persiste  |

---

## 7. Output esperado

### Drive
```
Clientes/Dr. Rodolfo Soares/Cronograma de Conteudo/Artes/2026/maio/27-05-2026/
├── reels-01.mp4
└── reels-01.png
```

### ClickUp
```
Subtarefa "Edição de vídeo — 27/05 Reels"
  Comentário: @Mateus ✅ Edição concluída — arquivos no Drive: <url>
  Status: edição concluída
```

### Relatório local
```
✅ Video Export — concluído em 1m42s

Sucesso: 5 pares
  • [Dr. Rodolfo Soares] 27-05-2026 reels-01 (vídeo + capa) → Drive ✓ ClickUp ✓
  • ...

Pendências: 1
  • [Dra. Y] 27-05-2026 reels-03 — par órfão (capa ausente)
```

---

## 8. Critérios de Aceite

- [ ] `/video-export` na 1ª vez roda onboarding completo em ≤ 2 min e cria `config.json`.
- [ ] `/video-export` (sem flag) após onboarding equivale a `/video-export --hoje`.
- [ ] `/video-export <pasta>` processa só essa pasta, mesmo se mtime ≠ hoje.
- [ ] Par vídeo+capa em pasta `Cliente\DD-MM-YYYY\` sobe pra hierarquia Drive correta.
- [ ] Comentário no ClickUp é postado e status muda pra `edição concluída`.
- [ ] @-mention do responsável da tarefa-mãe aparece quando `mentionResponsavel=true`.
- [ ] Re-rodar sem `--force` pula arquivos já presentes no Drive.
- [ ] `--force` sobrescreve no Drive.
- [ ] Falha em 1 par não aborta os outros 5.
- [ ] Órfãos (vídeo sem capa) aparecem em pendências, não bloqueiam pares válidos.
- [ ] `--dry-run` lista o que faria sem subir nada nem comentar.
- [ ] `--reconfigure` reabre o onboarding com defaults da config atual.

---

## 9. Fora do Escopo (v1.0)

- Múltiplos editores no mesmo cache (assume 1 config por usuário do Windows).
- Conversão automática de formato (HEIC→PNG, MOV→MP4, etc.).
- Geração automática de capa a partir do vídeo (sem Pixel).
- Validação de arte / nudez (sem Bia).
- Notificação Slack/WhatsApp.
- Criação automática de subtarefa quando Match não encontra.
- Multi-tenant / suporte a múltiplas workspaces ClickUp.
- Status final configurável por tipo de post.

---

## Histórico

| Data       | Versão | Descrição                                                                  |
|------------|--------|----------------------------------------------------------------------------|
| 2026-06-01 | 1.0    | PRD inicial                                                                |
| 2026-06-01 | 1.1    | Integração de melhorias do upstream prep-agenda-stark (até `d1d4de5`):     |
|            |        | • Template de comentário ClickUp padronizado (✅ / Ref / Entregue / 🔗 Drive) |
|            |        | • FR31: sequencial obrigatório comentário→status (fix anti-drop)           |
|            |        | • FR20a/b: overrides por cliente em `config/clientes.yaml`                 |
|            |        | • FR19a: normalização cliente com remoção de `Dr.`/`Dra.` antes do match   |
