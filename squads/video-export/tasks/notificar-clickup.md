---
name: notificar-clickup
owner: notifier
---

# Task: Notificar ClickUp

Implementado pelo agente Noti. Algoritmo em [agents/notifier.md](../agents/notifier.md).

## Template de comentário — padrão Stark

```
✅ Edição concluída.
Ref: <cliente> — <DD-MM> <nome_raiz>
Entregue: vídeo (.mp4) + capa (.png)

🔗 Drive: <drive_folder_url>
```

Com mention single:
```
@Mateus ✅ Edição concluída.
Ref: Dr. Rodolfo Soares — 27-05 reels-01
Entregue: vídeo (.mp4) + capa (.png)

🔗 Drive: https://drive.google.com/drive/folders/abc123
```

Múltiplos responsáveis separados por espaço:
```
@Maria @João ✅ Edição concluída.
...
```

## ⚠️ Sequencial obrigatório

**NUNCA chamar `clickup_create_task_comment` e `clickup_update_task` em paralelo.**

O ClickUp dropa o comentário silenciosamente quando os dois competem. Ordem:

```
Passo 1:  clickup_create_task_comment(task_id, comment_text, notify_all=true)
          → AWAIT → confirm comment_id

Passo 2:  clickup_update_task(task_id, status="edição concluída")
          → AWAIT → confirm new status
```

Se o passo 2 falhar, manter resultado `comment_ok_status_fail` (não fazer rollback).

## Resolução de mention

1. Lê `assignees` da `parent_task_id` (tarefa-mãe da subtarefa).
2. Pra cada assignee, pega `username` e converte pra formato `@nome`.
3. Se nenhum assignee na mãe → `mentioned_users: []`, posta sem @ no início.

## Atualização de status

Tenta `clickup_update_task` com `status="edição concluída"`. Se a lista da subtarefa não tem esse status:
- Registra `comment_ok_status_fail`
- Mantém status atual
- Inclui no relatório final pra Eve

## Dry-run

Em `--dry-run`, monta tudo (comentário + payload de update), devolve preview, sem chamar API.

```yaml
dry_run: true
comment_preview: |
  @Mateus ✅ Edição concluída.
  Ref: Dr. Rodolfo Soares — 27-05 reels-01
  Entregue: vídeo (.mp4) + capa (.png)

  🔗 Drive: https://drive.google.com/drive/folders/abc123
status_payload: { task_id: "abc", status: "edição concluída" }
```
