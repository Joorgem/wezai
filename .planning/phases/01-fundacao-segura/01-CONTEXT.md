# Phase 1: Fundação Segura — Context

**Gathered:** 2026-04-26
**Status:** Ready for execution

<domain>
## Phase Boundary

Quatro mudanças no `wezterm/repo-launcher.sh`:

1. Fix do bug destrutivo de cleanup em `resolve_worktree` (deleta branches existentes silenciosamente).
2. Auto-fetch just-in-time ao entrar na tela de branches (`select_branch`).
3. Tela de erro full-screen para falhas de worktree, substituindo `STATUS_MESSAGE` inline.
4. Status enriquecido na lista de branches (ahead/behind, stale, merged, tempo relativo).

**Não está nesta fase:** hotkey `r` manual, resize dinâmico, delete branch, multi-pane, criação de repo.
</domain>

<decisions>
## Implementation Decisions

### D1 — Fix do cleanup destrutivo
- **D-01:** Usar abordagem **snapshot before/after**: capturar lista de branches antes de `git worktree add`, comparar com lista após falha. Só deletar branches que **nasceram nesta invocação**.
- **D-02:** Em caso de dúvida (falha do snapshot, qualquer ambiguidade), **NÃO deletar nada**. Comportamento permissivo.
- **D-03:** Manter cleanup do diretório órfão (`rmdir "$wt_path"`) — não é destrutivo.
- **D-04:** Capturar erro completo em nova variável `RESOLVE_FULL_ERROR` (sem truncar) para uso pela tela de erro. `RESOLVE_ERROR` (primeira linha) continua existindo.

### D2 — Auto-fetch
- **D-05:** Fetch é **just-in-time**: dispara ao entrar em `select_branch`, antes do loop principal.
- **D-06:** Timeout de **5 segundos**, hard-coded (sem config por enquanto).
- **D-07:** Sem cache na primeira iteração — fetch a cada entrada na tela de branches do mesmo repo.
- **D-08:** Indicador visual: `clear` + `printf 'fetching... <repo>'` antes de chamar; após retorno, segue normal.
- **D-09:** Implementação preferida: `timeout 5s git fetch --prune --quiet` (se `timeout` disponível). Fallback: bash puro com PID + sleep loop.
- **D-10:** Falha de fetch (incluindo timeout) **não bloqueia** uso — exibe `STATUS_MESSAGE` informativa ("fetch timed out / failed — showing cached") e segue.

### D3 — Tela de erro full-screen
- **D-11:** Nova função reutilizável `show_worktree_error <repo> <branch> <action_type> <error_msg>`.
- **D-12:** Layout: header verde + separadores + contexto (repo/branch/action) + erro git completo (wrapeado via `fold -s -w "$(($(tput cols) - 4))"`) + sugestões + footer "press any key".
- **D-13:** Sugestões via pattern matching no erro:
  - `is already used by worktree at` → "branch já está em uso em outro worktree. Feche aquele primeiro ou escolha outra."
  - `branch named '...' already exists` → "branch local já existe. Volte e escolha tipo `local` em vez de `new`."
  - `not a valid branch name` → "nome inválido. Evite trailing dot, leading dash, chars especiais."
  - default → "log completo em ~/.local/state/wezterm/worktree.log"
- **D-14:** Dismissão via `read -rsn1 _` (qualquer tecla).
- **D-15:** Substitui `STATUS_MESSAGE` nos 3 sites de falha em `select_branch` (linhas ~711, ~727, ~757).

### D4 — Status enriquecido
- **D-16:** Single call `git for-each-ref --format='%(HEAD)|%(refname:lstrip=2)|%(upstream:track,nobracket)|%(committerdate:relative)' refs/heads/ refs/remotes/`.
- **D-17:** Detecção de **default branch** (para `merged`):
  - Tenta `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null` → `origin/main` (etc.)
  - Fallback: `main`, `master`, primeira branch
- **D-18:** Detecção de `merged`: `git branch --merged "$default_branch" --format='%(refname:short)'` em segunda chamada, cruzar com lista.
- **D-19:** `upstream:track` retorna `gone` quando upstream foi deletado → mostrar como `stale` (vermelho).
- **D-20:** Layout responsive (via `tput cols`):
  - ≥120 cols: nome + tracking + status + tempo
  - 80-119 cols: nome + tracking + status (omite tempo)
  - <80 cols: nome + status flag mais relevante apenas
- **D-21:** Cores semânticas (Catppuccin Mocha): `↑` peach `#fab387`, `↓` teal `#94e2d5` (cor nova), `stale` red `#f38ba8`, `merged` dim `#6c7086`, time dim `#6c7086`.
- **D-22:** Truncamento: nome >30 chars → `…`. Tempo abreviado: `2 hours ago` → `2h`, `3 weeks ago` → `3w`.

### Claude's Discretion
- Layout exato dos espaços e alinhamento na linha do branch item (Claude decide visual final, validação manual).
- Nome exato das funções helpers internas (Claude decide nomenclatura).
- Estrutura interna do snapshot before/after (Claude decide algoritmo).
</decisions>

<specifics>
## Specific Ideas

- **Layout-alvo (referência visual)** para a lista de branches em janela larga:
  ```
   ●  main             [wt]                 ↑0 ↓0   2 hours ago
      feat-x                                ↑3 ↓1   1 day ago
      feat-old                          stale       3 weeks ago
      hotfix-merged                ✓ merged         5 hours ago
   ↓  origin/release                                15 minutes ago
  ```

- **Tela de erro alvo** (~60 cols, screen do Xitao):
  ```
   ERROR   worktree add failed
   ──────────────────────────────────────

   repo     supervisor
   branch   gsd/phase-1-schemas-readers
   action   local

   git error:
     fatal: 'gsd/phase-1-schemas-readers' is
     already used by worktree at
     'C:/Users/jorge/Documents/github/
     supervisor-phase-1'

   what you can do:
     branch já está em uso em outro
     worktree. Feche aquele primeiro ou
     escolha outra branch.

   press any key to continue
  ```

- **Bug histórico de referência:** ver `~/.local/state/wezterm/worktree.log` — entrada `[sáb, 25 de abr 16:01:56]` mostra o caso real `is already used by worktree at`.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `wezterm/repo-launcher.sh` — todo o código a ser modificado
- `CLAUDE.md` — convenções, paleta, armadilhas Windows/MSYS, fluxo seguro de teste
- `.planning/PROJECT.md` — contexto geral do projeto
- `.planning/ROADMAP.md` — escopo das ondas

**Linhas-chave em `repo-launcher.sh`:**
- `:13-26` — `FZF_THEME` (paleta a respeitar)
- `:388-415` — `list_branches` (função a refatorar para D4)
- `:417-485` — `resolve_worktree` (onde está o bug destrutivo D1 e onde D2/D3 integram)
- `:537-575` — `build_branch_items` (renderização a atualizar para D4)
- `:677-765` — `select_branch` (onde injetar fetch D2 e tela de erro D3)
</canonical_refs>

<constraints>
## Constraints

- **Plataforma:** Windows + Git Bash + WezTerm. Nada de Mac/Linux.
- **Git nativo (mingw64) não aceita paths MSYS:** sempre `(cd "$path" && git ...)` em subshell.
- **Path conversion:** wrappers fzf usam `MSYS_NO_PATHCONV=1` (já existe via `fzf_safe`).
- **Validação:** sem suite de testes. Manual: `bash -n wezterm/repo-launcher.sh` (sintaxe), depois testar em janela WezTerm nova (não a atual).
- **Backup:** `./install.sh` faz backup automático antes de copiar.
- **Line endings:** LF forçado via `.gitattributes`.
- **Dependências:** não adicionar dep nova. Use só o que já está em uso (`fzf`, `git`, `bash`, `coreutils`, `wezterm cli`).
- **Paleta:** Catppuccin Mocha — só adicionar nova cor (teal `#94e2d5`) se necessário, e adicionar à `FZF_THEME` se for usada em telas fzf.
</constraints>

<execution_protocol>
## Execution Protocol

Cada plan é um commit atômico:

1. Editar
2. `bash -n wezterm/repo-launcher.sh`
3. Testar em janela WezTerm **nova** (não a atual)
4. Se OK, `./install.sh`
5. Validar de novo na nova janela
6. Commit com `feat:` / `fix:` apropriado

**Ordem de execução obrigatória:**

```
01-01 (fix destrutivo) ──→ commit 1
   ↓ (sem dep, mas prioridade alta)
01-02 (tela de erro) ──→ commit 2
   ↓ (sem dep)
01-03 (auto-fetch) ──→ commit 3
   ↓ (sem dep)
01-04 (status enriquecido) ──→ commit 4
```

Todos os 4 plans tocam o mesmo arquivo (`repo-launcher.sh`) — execução **sequencial** para evitar conflitos. Cada commit deve passar `bash -n` e smoke test antes do próximo iniciar.
</execution_protocol>
