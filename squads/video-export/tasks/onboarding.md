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

## Persistência

Escreve `%USERPROFILE%\.stark-video-export\config.json` com formato:

```json
{
  "editorEmail": "mateus.redmann@starkmkt.com",
  "videoRoot": "D:\\Edicoes",
  "videoExt": ".mp4",
  "capaExt": ".png",
  "mentionResponsavel": true,
  "version": 1,
  "createdAt": "<ISO timestamp>"
}
```

Cria também os diretórios:
- `%USERPROFILE%\.stark-video-export\` (raiz)
- `%USERPROFILE%\.stark-video-export\logs\` (logs por execução)

## Mensagem final

```
✅ Setup concluído. Sua config está em %USERPROFILE%\.stark-video-export\config.json
   Use /video-export --reconfigure pra mudar.

Próxima execução vai direto pro modo --hoje. Bora?
```

E continua o pipeline com `--hoje` por default (a menos que o editor já tenha passado outra flag junto com o `/video-export`).
