# terminal-setup (wezai)

## What This Is

Setup de terminal para Windows + Git Bash + WezTerm + Claude Code. Combina um launcher interativo de repositórios (`repos`), uma statusline powerline para o Claude Code, e um instalador. Distribuído como repo MIT público; usuários clonam e rodam `./install.sh`.

## Core Value

**Setup multi-pane fluido:** abrir vários repositórios/branches/agentes em paralelo no menor número de teclas possível, sem fricção, em qualquer máquina Windows com WezTerm.

## Requirements

### Validated

- [x] Launcher interativo `repos` em 4 telas (repos → branches → mode → target)
- [x] Statusline Claude powerline em 2 linhas
- [x] Modos custom + reorder
- [x] Pinning de repos (até 3)
- [x] Worktrees automáticos por branch (`.wt/`)
- [x] Auto-detect de Git Bash + override via env var

### Active

- [ ] **REQ-01:** Launcher nunca deve deletar branches do usuário sem ação explícita
- [ ] **REQ-02:** Usuário deve ver refs remotas atualizadas sem sair do launcher
- [ ] **REQ-03:** Erros de worktree devem ser legíveis em telas pequenas (≤80 cols)
- [ ] **REQ-04:** Lista de branches deve mostrar estado de sync com upstream (ahead/behind/stale/merged)
- [ ] **REQ-05:** Abrir setups multi-pane (2/3/4 colunas + grid 1+2) via hotkey direto, em nova tab
- [ ] **REQ-06:** Criar novos repositórios pelo launcher (clone + `gh repo create` com escolha de owner pessoal/org)
- [ ] **REQ-07:** Telas do launcher devem se adaptar a resize de janela
- [ ] **REQ-08:** Deletar branches (local seguro, remoto com confirmação dupla) e worktrees pelo launcher
- [ ] **REQ-09:** Help screen acessível de qualquer tela via `?`

### Out of Scope

- **Mac/Linux** — único platform target é Windows; nenhum colaborador atual usa outras plataformas
- **Pair sync entre panes** — broadcast de input ou cwd-follow descartado por baixo valor vs custo
- **Layouts nomeados / workspaces persistidos** — alta complexidade, muitos edge cases (branch não existe na máquina do colaborador, etc.)
- **Restore de "última sessão"** — adiado indefinidamente; pode reentrar se houver demanda real
- **Balance de panes** — descartado, hotkeys de criação já produzem panes proporcionais
- **`git init` puro no launcher** — raro caso de uso real; `clone` e `gh-create` cobrem trabalho real
- **Inter-agent Claude communication** — fora do escopo do terminal; problema de outro projeto (MCP server custom)

## Context

- Single platform: Windows 10/11 + Git Bash + WezTerm
- Distribuído como public repo no GitHub (MIT)
- Mantenedor principal: Joorgem
- Colaborador atual: SuperXitao (usa tela menor — ergonomia em janelas pequenas é importante)
- Workflow real: usuários abrem o `repos` on-demand para iniciar trabalho, não deixam aberto
- Trabalho diário envolve múltiplos repositórios em paralelo (typical: 3 panes side-by-side com Claude em cada)

## Constraints

- **Tech stack**: Bash 4+ (git-bash), fzf ≥0.70, wezterm CLI, git ≥2.13, jq (statusline only). `gh` necessário só para criação de repos (Onda 3).
- **Path conversion**: MSYS converte argumentos `/foo` para Windows paths. Wrappers usam `MSYS_NO_PATHCONV=1`. Git nativo (mingw64) não aceita paths MSYS — sempre `(cd "$path" && git ...)` em subshell.
- **Line endings**: `.gitattributes` força LF em `*.sh`, `*.lua`, `repos`, `bashrc.wezterm`.
- **Sem suite de testes**: validação é manual (executar o launcher e seguir o flow). Cada commit deve ser testado em janela WezTerm nova antes de push.
- **Backup obrigatório**: `./install.sh` faz backup com sufixo `.bak-YYYYMMDD-HHMMSS`. Mudanças em arquivos instalados não destroem versão anterior.

## Key Decisions

- **2026-04-26 — Onda 1 priorizada como segurança/correção**: bug destrutivo de cleanup em `resolve_worktree` deletava branches locais existentes silenciosamente. Tratado como fix urgente.
- **2026-04-26 — Multi-pane via Alt+N abre em NOVA TAB sempre**: protocolo β escolhido. Gesto significa "começar workspace novo" — nunca destrói layout existente.
- **2026-04-26 — Auto-fetch é just-in-time, não no startup**: dispara ao entrar em `select_branch`, com timeout de 5s. Sem cache na primeira iteração.
- **2026-04-26 — Erros de worktree em tela full-screen**: substitui `STATUS_MESSAGE` inline (ilegível em janela pequena do Xitao). Nova função `show_worktree_error` reutilizável para futuros erros.
- **2026-04-26 — Status enriquecido via `git for-each-ref`**: single-call com `%(upstream:track)` + `%(committerdate:relative)` em vez de N calls. Detecção de `merged` requer descobrir default branch via `origin/HEAD`.
