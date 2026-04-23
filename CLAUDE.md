# CLAUDE.md

Contexto e convenções do projeto para agentes (Claude Code, Codex, etc).
Este arquivo é carregado automaticamente quando o Claude abre dentro do repo.

## O que é este projeto

Setup de terminal para Windows + Git Bash + WezTerm + Claude Code:

- **Launcher interativo de repositórios** (`wezterm/repo-launcher.sh`) em 4 telas: repos → branches (worktree) → mode → target (compass).
- **Statusline Claude** (`claude/statusline.sh`) powerline em 2 linhas com Nerd Font.
- **`install.sh`** que copia tudo para `~/.config/wezterm/` e `~/.claude/` com backup automático.

Distribuído como repo público no GitHub (MIT). Usuários clonam e rodam `./install.sh` para aplicar. Atualizações são `git pull && ./install.sh`.

## Alvo

**Único platform target: Windows 10/11 + Git Bash + WezTerm.** Não portamos para Mac/Linux porque nenhum de nós usa.

Isso tem implicações práticas em várias decisões (ver "Armadilhas do Windows" abaixo).

## Estrutura

```
wezai/
├── README.md                      # docs para humanos (instalação, uso, teclas)
├── CLAUDE.md                      # este arquivo — contexto para agentes
├── .gitattributes                 # força LF em *.sh/*.lua
├── .gitignore
├── install.sh                     # instalador com backup
├── wezterm/
│   ├── wezterm.lua                # config do terminal (tema, font, keybinds)
│   ├── bashrc.wezterm             # bashrc carregado pelo WezTerm; define função 'repos'
│   ├── repo-launcher.sh           # ~1000 linhas — o launcher em si
│   └── repos                      # stub executável ($PATH) que source/chama o launcher
└── claude/
    ├── statusline.sh              # powerline 2-line (project / branch / model / cost / ctx / rate)
    └── settings.snippet.json      # bloco `statusLine` para colar em ~/.claude/settings.json
```

## Arquitetura do launcher (`repo-launcher.sh`)

**Fluxo**:
```
repos → Enter → BRANCHES → Enter → MODE → Enter → TARGET → ação
```

**Módulos (por ordem no arquivo)**:
- `FZF_THEME` (array bash) — tema compartilhado: cores, padding, gap, pointer, preview bg
- `fzf_safe` — wrapper que seta `MSYS_NO_PATHCONV=1` (ver "Armadilhas")
- `repo_preview` — função de preview (invocada como `bash $LAUNCHER --preview REPO`)
- `load_repos` / `load_pins` / `save_pins` / `toggle_pin` — estado
- `build_repo_items` / `run_repo_nav` / `run_repo_search` / `select_repo` — Tela 1 & 2
- `list_branches` / `resolve_worktree` / `prompt_new_branch` / `build_branch_items` / `run_branch_nav` / `run_branch_search` / `select_branch` — Tela 3 (branches)
- `BUILTIN_MODE_IDS` / `BUILTIN_MODE_LABELS` — hardcoded, keep in sync com `prepare_launch_mode`
- `load_custom_modes` / `save_custom_modes` / `find_custom_command` — state em `custom-modes.tsv` (TAB-separated: label\tcommand)
- `load_mode_order` / `save_mode_order` — state em `mode-order.txt` (um ID por linha, `terminal` / `claude` / `custom:<label>`)
- `render_mode_meta` — dispatch por mode ID → linha colorida (built-ins são hardcoded por case, customs usam label + command truncado)
- `add_custom_mode` / `delete_custom_mode` — prompt inline (pós-fzf), rejeita labels reservados, confirma deleção
- `edit_modes_screen` — tela full-screen separada (sem fzf), lê `read -rsn1`, setas movem o item selecionado, `j/k` alt vim-style, Enter salva, Esc cancela
- `confirm_unsafe` / `select_launch_mode` — Tela 4 (modes) — loop com `--expect=esc,n,d,e`, recarrega custom+order a cada iteração
- `prepare_launch_mode` — traduz mode → `LAUNCH_ARGS`. Customs rodam via `bash -c "$cmd"` pra suportar shell metacharacters
- `select_target` — Tela 5 (compass, bash puro, sem fzf)
- `open_split_pane` / `launch_in_current_pane` / `launch_in_split` — efeitos finais via `wezterm cli`
- `repo_launcher_main` — orquestra

**Convenções das telas fzf**:
- Items têm 3 colunas tab-separated: `<action>\t<label_com_cor>\t<valor_limpo>` — o fzf mostra col 2 (`--with-nth=2`), extraímos col 3 no parse (sem ANSI pra strip).
- Cada tela tem `nav` (sem input, `--no-input`) e pode ter `search` (aceita digitação). Convenção: tecla `/` alterna para search, `esc` volta.
- Headers usam truecolor ANSI `\033[38;2;R;G;Bm` inline. Paleta no topo de cada função.
- Footers com separadores `│` em cinza `#585b70`, tecla em verde `#a6e3a1`, label em dim `#6c7086`.
- Breadcrumbs: `TELA_ATUAL   REPO ▸ {repo} ▸ {extra}`.

## Paleta (Catppuccin Mocha + acentos)

| Papel | Hex | Uso |
|---|---|---|
| primary | `#a6e3a1` | prompt, pointer, keys, brand, pins, current branch |
| text | `#cdd6f4` | nomes, valores |
| dim | `#6c7086` | labels footer, metadados, branches remotas |
| subtle | `#585b70` | separadores `│`, border |
| danger | `#f38ba8` | UNSAFE mode, erros |
| warn | `#fab387` | branches dirty |
| bg | `#11111b` | fundo launcher + preview (mais escuro que Mocha default) |
| bg+ | `#1e1e2e` | linha selecionada |

**Regra**: só usar azul/amarelo/roxo em casos específicos e intencionais. Estética é "hacker terminal" — verde + cinzas + branco.

## Armadilhas do Windows / Git Bash

Problemas reais que já custaram debugging. Memorize.

### 1. MSYS path conversion
Git Bash converte argumentos que começam com `/` para paths Windows (`/foo` → `C:\Program Files\Git\foo`). Isso quebra coisas tipo `fzf --prompt='/ '` (prompt virava `C:\Program Files\Git\ `).

**Solução adotada**: `MSYS_NO_PATHCONV=1` em todas as chamadas fzf via wrapper `fzf_safe`. Evite prompts começando com `/`.

### 2. Git nativo não aceita paths MSYS (`/c/Users/...`)
`git.exe` (Windows nativo em `/mingw64/bin/git`) só entende `C:\Users\...` ou `C:/Users/...`. Com `MSYS_NO_PATHCONV=1` ligado, a conversão automática some. Por isso `git -C "/c/Users/..."` falha silenciosamente.

**Solução adotada**: sempre usar `(cd "$path" && git ...)` em subshell. O bash resolve `/c/...` e o git herda o cwd já no formato nativo.

### 3. `cmd.exe` como default shell do fzf
No Windows, `fzf.exe --preview "bash ... {3}"` roda o preview via `cmd.exe /c` por padrão. Quebra comandos bash complexos.

**Solução adotada**: `--with-shell='bash -c'` no `FZF_THEME`. Força uso de bash em todos os subprocess.

### 4. CRLF line endings quebram shell scripts
Arquivos `.sh` checkados com CRLF não executam via bash (`^M: command not found`).

**Solução adotada**: `.gitattributes` força LF em `*.sh`, `*.lua`, `repos`, `bashrc.wezterm`.

### 5. Windows não aceita dirs terminando em `.`
`mkdir dir.` falha. `git worktree add .wt/branch-name.` também falha (git cria a branch mas dir rejeita).

**Solução adotada**: em `resolve_worktree`, validamos o nome da branch antes (rejeita trailing dot, leading dash, `..`, chars `: \ * ? < > | "`). Se git worktree falhar mesmo assim, faz cleanup da branch criada.

### 6. Worktrees: `.git` é arquivo, não diretório
Em worktrees (secundários), `.git` é um FILE apontando pro repo principal. `[[ -d path/.git ]]` falha. Use `[[ -e path/.git ]]`.

### 7. Nerd Font fallback
O `▸` (pointer) pode renderizar como `)` em fontes sem o glifo. A config `wezterm.lua` usa `JetBrains Mono` com fallback `JetBrainsMono Nerd Font`. Se o usuário não tiver nerd font instalada, glifos quebram.

## Como testar mudanças sem quebrar

O launcher está rodando aqui mesmo (você provavelmente está dentro do WezTerm agora). Um bug no `repo-launcher.sh` pode travar o login shell na próxima vez que abrir uma janela.

**Fluxo seguro**:
1. Editar dentro do repo (`~/Documents/github/wezai/wezterm/`).
2. **Validar sintaxe primeiro**: `bash -n wezterm/repo-launcher.sh`.
3. Testar em subshell isolado antes de instalar:
   ```bash
   bash wezterm/repo-launcher.sh --preview SOME_REPO   # valida modo preview
   ```
4. Se parecer ok, rodar `./install.sh` (já faz backup `.bak-YYYYMMDD-HHMMSS`).
5. Abrir **janela nova** do WezTerm (não a atual) e testar. Se quebrar, a atual ainda tem a sessão rodando — dá pra restaurar.

**Rollback**:
```bash
cd ~/.config/wezterm
mv repo-launcher.sh.bak-YYYYMMDD-HHMMSS repo-launcher.sh
```

## Como estender

### Adicionar novo modo no launcher
1. Em `select_launch_mode`, adicionar nova linha no `printf '%s\n'` (3 colunas tab-sep: `id\tlabel_colorido\t...`).
2. Em `prepare_launch_mode`, tratar o novo `id` case: setar `MODE_LABEL` e `LAUNCH_ARGS`.
3. Se for perigoso, adicionar confirmação via `confirm_unsafe` ou equivalente.

### Adicionar nova tela/etapa
Segue o padrão: função `run_<tela>_nav` + `build_<tela>_items` + orquestrador `select_<tela>`. Header breadcrumb, footer consistente, usa `FZF_THEME` global.

### Adicionar novo repo-type filter
`load_repos` filtra via `grep -v` pipe. Adicione novo `grep -v 'PATTERN'` na pipeline.

### Mudar paleta
`FZF_THEME` no topo + as variáveis `c_green`/`c_text`/`c_dim`/`c_sep`/`c_red` em cada função. São truecolor ANSI — `\033[38;2;R;G;Bm`.

## Variáveis de ambiente

O repo assume defaults razoáveis mas permite override via env var — útil quando outro computador tem Git instalado fora dos locais padrão ou repos em `C:\dev` em vez de `~/Documents/github`.

| Var | Default | Onde é lido |
|---|---|---|
| `GITHUB_DIR` | `~/Documents/github` | `wezterm.lua` (cwd inicial) **e** `repo-launcher.sh` (load_repos) |
| `WEZAI_GIT_BASH` | `find_git_bash()` — tenta `C:\Program Files\Git\`, `~/AppData/Local/Programs/Git/`, `C:\Program Files (x86)\Git\` | `wezterm.lua` (default_prog do shell) |
| `XDG_STATE_HOME` | `~/.local/state` | State root para `wezterm/repo-pins.txt`, `custom-modes.tsv`, `mode-order.txt` |

**Regra:** nunca hardcode paths específicos de máquina em `wezterm.lua`. Se precisa de um path novo, adiciona auto-detect + env var override seguindo o mesmo padrão.

## Dependências runtime

Requeridas:
- `fzf ≥ 0.70` (usa `--with-shell`, `--gap`, `--header-border`, `--footer`, `--padding`)
- `wezterm` (>= versão recente para `wezterm cli split-pane --cwd`)
- `git` (via Git for Windows — `/mingw64/bin/git`)
- `jq` (só para statusline)

Opcional:
- `claude` (Claude Code CLI) — **lazy**: só exigido quando o modo escolhido for `claude-*`. Ver `prepare_launch_mode`.

## Arquivos pessoais que NÃO estão neste repo

Propositadamente fora:
- `~/.claude/settings.json` (modelo default, plugins habilitados, hooks pessoais)
- `~/.claude/hooks/*` (scripts de hook pessoais)
- `~/.claude/agents/*`, `~/.claude/commands/*`, `~/.claude/rules/*`
- `~/.credentials.json` (nunca no git)
- `~/.local/state/wezterm/repo-pins.txt` (pins individuais)
- `~/.local/state/wezterm/custom-modes.tsv` (custom modes por user)
- `~/.local/state/wezterm/mode-order.txt` (ordem customizada dos modes)

Usuários configuram esses separadamente. Este repo é só o "shell visível" do terminal.

## Convenções de commit

Conventional commits:
- `feat:` nova funcionalidade
- `fix:` correção de bug
- `refactor:` reestruturação sem mudança de comportamento
- `docs:` README/CLAUDE.md
- `style:` formatação/espaçamento sem lógica

Exemplos do histórico: `feat(modes): add codex built-in, custom modes, and reorder editor`, `fix: worktree path conversion on MSYS`.

Escopo opcional entre parênteses quando útil: `feat(branches): …`, `fix(preview): …`.

## Fluxo de publicação

```bash
cd ~/Documents/github/wezai
# editar
bash -n wezterm/repo-launcher.sh   # validar sintaxe
git add . && git commit -m "..." && git push
./install.sh   # aplicar no próprio sistema
```

Colaboradores puxam com `git pull && ./install.sh`.

## Contatos

- Repo: https://github.com/Joorgem/wezai (MIT, público)
- Owner: Joorgem
- Colaboradores atuais: SuperXitao
