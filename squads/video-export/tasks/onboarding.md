---
name: onboarding
owner: export-chief
---

# Task: Onboarding (1ª execução)

Roda quando `%USERPROFILE%\.stark-video-export\config.json` não existe, ou quando o editor passou `--reconfigure`.

## Fluxo

Pergunta ao editor (uma de cada vez ou agrupadas via UI de questionário):

### 1. Email no ClickUp
```
Qual seu email no ClickUp? (precisa pra resolver suas tarefas e @-menções)
> mateus.redmann@starkmkt.com
```
Validação: deve conter `@`. Se ClickUp MCP estiver disponível, busca `workspace_members` e oferece autocomplete.

### 2. Pasta-raiz dos vídeos
```
Onde você salva os vídeos editados?
> D:\Edicoes
```
Validação:
- Pasta deve existir (`Test-Path`).
- Aviso se vazia: "Pasta existe mas está vazia. Tudo bem, vai funcionar quando você adicionar vídeos."

### 3. Extensão do vídeo (default `.mp4`)
```
Extensão padrão dos vídeos? [.mp4]
>
```

### 4. Extensão da capa (default `.png`)
```
Extensão padrão das capas? [.png]
>
```

### 5. @-mention do responsável
```
Quando comentar no ClickUp, devo @-mencionar o responsável da tarefa-mãe? [sim]
>
```

### 6. rclone — checagem e instalação guiada

> ⚠️ **Obrigatório.** O Google Drive MCP rejeita arquivos > 10MB. Vídeo editado quase sempre passa de 10MB, então o upload do vídeo é feito via `rclone copyto` contra um remote configurado pelo editor. Sem rclone, a skill não consegue entregar.

#### 6.1 Detectar instalação

```powershell
$rclonePath = (Get-Command rclone -ErrorAction SilentlyContinue).Source
```

- **`$rclonePath` retornou caminho** → ler versão (`rclone version | Select-Object -First 1`) e mostrar:
  ```
  ✅ rclone detectado: <versão> em <caminho>
  ```
  Pular pra 6.3.

- **Não encontrado** → seguir 6.2.

#### 6.2 Instalação guiada

Mostrar instrução **por sistema operacional** (detectar via `$IsWindows` / `$env:OS` / fallback Bash `uname`):

**Windows (default neste repo):**
```
rclone não está instalado. Vou guiar você:

Opção A (winget — recomendado):
  winget install Rclone.Rclone

Opção B (Chocolatey):
  choco install rclone

Opção C (manual):
  1. Baixe https://rclone.org/downloads/ (escolha Windows AMD64 zip)
  2. Extraia rclone.exe pra C:\Program Files\rclone\
  3. Adicione ao PATH: System Properties → Environment Variables → Path → C:\Program Files\rclone

Depois rode: rclone version
Quando terminar, digite "ok" pra continuar.
```

**macOS:**
```
brew install rclone
```

**Linux:**
```
curl https://rclone.org/install.sh | sudo bash
```

Após o editor confirmar com "ok" / Enter, **re-executar a detecção da 6.1**. Loop até detectar (máx 3 tentativas; depois aborta com mensagem clara).

#### 6.3 Configurar o remote `gdrive:`

Listar remotes existentes:

```powershell
rclone listremotes
```

- **Saída contém `gdrive:` (ou outro remote do tipo `drive`)** → perguntar qual usar:
  ```
  rclone já tem remotes configurados:
    - gdrive:
    - work:

  Qual usar pro Drive da Stark? [gdrive]
  >
  ```
  Validar que o tipo é `drive` (via `rclone config show <nome> | Select-String "type ="`).

- **Nenhum remote `drive`** → guiar criação interativa:
  ```
  Vou abrir o wizard do rclone agora. Siga essas respostas:

    n         # New remote
    gdrive    # Name
    drive     # Storage (digite "drive" ou escolha o número de "Google Drive")
    <Enter>   # client_id (deixa em branco)
    <Enter>   # client_secret (deixa em branco)
    1         # scope = Full access
    <Enter>   # service_account_file (em branco)
    n         # Edit advanced config? = No
    y         # Use auto config? = Yes (vai abrir o browser pra login Google)
    n         # Configure as Shared Drive? = No  ← responda N MESMO. O shared drive é
              #   mirado por flag (--drive-team-drive), não baked no remote. Ver 6.4.
    y         # Confirma
    q         # Quit

  Pronto pra abrir o wizard? [s/N]
  ```

  Quando o editor confirmar, executar:
  ```powershell
  rclone config
  ```

  > ℹ️ O comando é interativo — Eve mostra a sequência acima e deixa o editor pilotar. Após o wizard fechar, validar com `rclone listremotes` que `gdrive:` apareceu.
  >
  > 🆕 **Por que "No" em Shared Drive?** O remote fica apontado pra conta do editor
  > (auth pessoal). O alvo — o Drive Compartilhado da Stark — é passado em TODO comando
  > via `--drive-team-drive <rcloneTeamDriveId>` (id versionado em `squad.yaml`). Assim a
  > skill nunca cria pasta no "Meu Drive" e configs já existentes se corrigem sozinhas
  > sem refazer o wizard.

#### 6.4 Validar acesso ao Drive Compartilhado da Stark

> O `rcloneTeamDriveId` (`0ABl2cpta6dNRUk9PVA`) vem de `squad.yaml`. Ele aponta pro
> Drive Compartilhado da Stark. Na raiz desse shared drive existe o wrapper
> `clientes/` — dentro dele cada cliente tem sua pasta, com a subpasta
> `cronograma de conteúdo/` que serve de âncora pra hierarquia padrão (v1.4):
> `clientes/<cliente>/cronograma de conteúdo/<ano>/<mes_extenso>/<DD-MM-YYYY>/`.
> A skill só cria `<ano>`, `<mes_extenso>` e `<DD-MM-YYYY>` — os wrappers
> são preexistentes (cliente sem pasta vira pendência, nunca cria no Meu Drive).

Confirmar que o remote enxerga o wrapper `clientes/` na raiz do shared drive:

```powershell
rclone lsd gdrive:clientes --drive-team-drive 0ABl2cpta6dNRUk9PVA --max-depth 1
```

- **Retornou lista com pastas de cliente** (`Dr Diego Gonzalez/`, `Dra Luiza Coutinho/`, ...) → OK, salvar o nome do remote + o team-drive id no config.
- **Erro de permissão / "directory not found" / lista vazia** → mostrar:
  ```
  ⚠️ O remote 'gdrive:' está configurado mas não enxerga 'clientes/' no Drive Compartilhado.
     Verifica:
       1. O Google logado no rclone é o da Stark (não o pessoal).
       2. Esse usuário tem acesso ao Drive Compartilhado 0ABl2cpta6dNRUk9PVA.
       3. A pasta `clientes/` existe na raiz desse shared drive (case-insensitive — a skill
          faz fuzzy match exato normalizado; ausência total → pendência).
       4. O ID `0ABl2cpta6dNRUk9PVA` é o do Drive Compartilhado correto (vide squad.yaml).
     Rode 'rclone config reconnect gdrive:' pra refazer o login se for o caso.
  ```
  Pedir confirmação manual antes de continuar.

## Persistência

Escreve `%USERPROFILE%\.stark-video-export\config.json` com formato:

```json
{
  "editorEmail": "mateus.redmann@starkmkt.com",
  "videoRoot": "D:\\Edicoes",
  "videoExt": ".mp4",
  "capaExt": ".png",
  "mentionResponsavel": true,
  "rcloneRemote": "gdrive",
  "rcloneTeamDriveId": "0ABl2cpta6dNRUk9PVA",
  "rcloneCheckedAt": "<ISO timestamp>",
  "version": 3,
  "createdAt": "<ISO timestamp>"
}
```

> 🆕 Campo `rcloneRemote` adicionado na v2. Configs v1 (sem esse campo) disparam um mini-onboarding só da etapa 6 ao serem carregadas, sem perguntar de novo email/pasta/extensões.
>
> 🆕 Campo `rcloneTeamDriveId` adicionado na v3 — id do Drive Compartilhado da Stark. Valor canônico vive em `squad.yaml` (`defaults.rcloneTeamDriveId`); o config.json só guarda uma cópia. Quando ausente, os agentes caem no default do squad.

Cria também os diretórios:
- `%USERPROFILE%\.stark-video-export\` (raiz)
- `%USERPROFILE%\.stark-video-export\logs\` (logs por execução)

## Mensagem final

```
✅ Setup concluído. Sua config está em %USERPROFILE%\.stark-video-export\config.json
   rclone remote: gdrive: → Drive da Stark ✓
   Use /video-export --reconfigure pra mudar.

Próxima execução vai direto pro modo --hoje. Bora?
```

E continua o pipeline com `--hoje` por default (a menos que o editor já tenha passado outra flag junto com o `/video-export`).

## Migração v1 → v2 (config sem `rcloneRemote`)

Quando Eve carrega a config e detecta `version: 1` (ou ausência do campo `rcloneRemote`):

1. Mostra:
   ```
   Sua config é da v1 (pré-rclone). Vou completar o setup só do rclone — leva 2 min.
   ```
2. Executa as etapas 6.1 → 6.4 sem repetir 1-5.
3. Salva o config preservando todos os campos antigos + `rcloneRemote` + `version: 2`.
4. Continua o pipeline original.

## Migração v2 → v3 (config sem `rcloneTeamDriveId`)

Quando Eve carrega a config e detecta `version: 2` (ou ausência do campo `rcloneTeamDriveId`):

1. **Sem perguntar nada** — injeta `rcloneTeamDriveId` com o default do `squad.yaml`
   (`0ABl2cpta6dNRUk9PVA`) e bumpa pra `version: 3`. É o conserto que faz a skill mirar o
   Drive Compartilhado em vez do Meu Drive.
2. Roda só a validação 6.4 (`rclone lsd gdrive:clientes --drive-team-drive <id>`) pra confirmar acesso.
3. Continua o pipeline original.
