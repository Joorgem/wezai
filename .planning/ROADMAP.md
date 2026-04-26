# Roadmap: terminal-setup (wezai)

## Overview

Três ondas de evolução do `repo-launcher.sh` e configuração WezTerm. Onda 1 corrige um bug destrutivo e endurece a base do launcher antes de adicionar novas features. Onda 2 entrega o foco principal do trabalho atual (multi-pane com Xitao). Onda 3 cobre ergonomia geral e novas capacidades.

## Phases

- [ ] **Phase 1: Fundação Segura** — corrigir bug destrutivo, auto-fetch, mensagens de erro legíveis, status enriquecido
- [ ] **Phase 2: Multi-pane** — hotkeys Alt+N para abrir setups multi-pane em nova tab
- [ ] **Phase 3: Ergonomia & Capacidades** — criação de repo, resize dinâmico, delete branch/worktree, help screen

## Phase Details

### Phase 1: Fundação Segura
**Goal**: tornar o launcher seguro e informativo: nunca deletar branches inadvertidamente, mostrar refs atualizadas, exibir erros legíveis em qualquer tamanho de tela, e enriquecer a lista de branches com estado real de sync.

**Depends on**: Nothing (first phase)
**Requirements**: REQ-01, REQ-02, REQ-03, REQ-04
**Success Criteria** (what must be TRUE):
  1. Tentar criar worktree de uma branch local existente NÃO apaga a branch — ela continua intacta após o erro.
  2. Ao entrar na tela de branches, refs remotas estão atualizadas (auto-fetch executado, com timeout de 5s).
  3. Erro de worktree é exibido em tela full-screen, com texto wrapeado, legível em janela de 60 cols.
  4. Lista de branches mostra ↑N ↓N (ahead/behind), `stale` quando upstream sumiu, `✓ merged` quando integrada na default branch, e tempo relativo do último commit.
  5. Tudo continua funcionando: pinning, search, criar nova branch, modos, splits.

**Plans**: 4 plans

Plans:
- [ ] 01-01: Fix do bug destrutivo de cleanup em `resolve_worktree`
- [ ] 01-02: Tela de erro full-screen para falhas de worktree (`show_worktree_error`)
- [ ] 01-03: Auto-fetch just-in-time ao entrar em `select_branch`
- [ ] 01-04: Status enriquecido na lista de branches (`for-each-ref` + render)

---

### Phase 2: Multi-pane
**Goal**: hotkeys diretos do WezTerm que abrem setups multi-pane em **nova tab**, com `repos` rodando em cada pane novo. Foco no workflow real (Joorgem + Xitao trabalhando em 3 repos paralelos).

**Depends on**: Phase 1 (não estritamente necessário, mas Onda 2 herda os fixes da 1)
**Requirements**: REQ-05
**Success Criteria** (what must be TRUE):
  1. `Alt+2` abre nova tab com 2 colunas iguais, ambas executando `repos` automaticamente.
  2. `Alt+3` abre nova tab com 3 colunas iguais (33/33/33), todas executando `repos`.
  3. `Alt+4` abre nova tab com 4 colunas iguais.
  4. `Alt+Shift+3` abre nova tab com layout 1+2 (esquerda full-height, direita split top/bottom).
  5. Hotkey acionado em qualquer pane existente NÃO destrói o layout atual — sempre abre em nova tab.
  6. Funciona em qualquer tamanho de janela (com aviso visual se cols < N×30 — pane pequeno demais).

**Plans**: TBD (a ser detalhado via `/gsd:plan-phase 2` quando chegar a hora)

---

### Phase 3: Ergonomia & Capacidades
**Goal**: cobrir os gaps remanescentes que aumentam fricção no dia-a-dia: criar repos sem sair, telas que se adaptam a resize, deletar branches/worktrees seguro, help acessível, refetch manual.

**Depends on**: Phase 1
**Requirements**: REQ-06, REQ-07, REQ-08, REQ-09
**Success Criteria** (what must be TRUE):
  1. Tela de criação de repo via launcher: `clone <url>` e `gh repo create` com escolha de owner (pessoal/MyceRealm/orgs detectadas).
  2. Resizar a janela WezTerm faz o launcher refluir: separadores e headers se ajustam dinamicamente, telas bash puras (target compass, edit modes) re-renderizam.
  3. Hotkey `r` na tela de branches força re-fetch manual.
  4. Hotkey `D` deleta branch local com `git branch -d` (fail-safe). `Shift+D` deleta remoto com confirmação dupla.
  5. Hotkey de delete de worktree na tela de branches (worktrees órfãos saem do `.wt/`).
  6. Hotkey `?` em qualquer tela abre help com lista de keybinds e flow.

**Plans**: TBD (a ser detalhado via `/gsd:plan-phase 3` quando chegar a hora)

---

## Out of Scope (não vai virar phase)

- Pair sync entre panes (descartado — baixo valor vs custo)
- Layouts nomeados / workspaces persistidos (descartado — muitos edge cases)
- Restore de última sessão estilo browser (adiado indefinidamente)
- Balance de panes existentes (descartado — Alt+N já produz proporção igual)
- `git init` puro no launcher (raro; `clone` e `gh-create` cobrem)
- Inter-agent Claude communication (fora do escopo deste projeto)
