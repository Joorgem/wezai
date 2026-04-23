# terminal-setup

WezTerm + Claude Code terminal setup — estética hacker minimalista (Catppuccin Mocha + acentos verde-neon).

## O que tem

### WezTerm
Launcher interativo de repositórios com 4 telas conectadas:

1. **REPOS** — lista dos repos de `~/Documents/github/`, com pin (★) para os favoritos, busca com `/`, preview git ao vivo do repo sob cursor (branch, último commit, status).
2. **BRANCHES** — seleção obrigatória de branch via `git worktree`. Separa branches locais (`●` atual), locais não-checkadas, e remotas (`↓`). Tecla `n` cria worktree novo inline.
3. **MODE** — escolhe entre `shell`, `claude`, `claude --resume`, ou `claude UNSAFE` (com confirmação extra).
4. **TARGET** — bússola para escolher onde o novo pane abre: current, up, down, left, right.

Tudo com preview lateral contextual e mesma paleta.

### Claude Statusline
Status line powerline com Nerd Font em 2 linhas:
- Linha 1: projeto · branch (com dirty dot) · modelo · custo
- Linha 2: contexto usado (com cor por gravidade) · rate limit 5h + countdown

## Pré-requisitos

No Windows (Git Bash + WezTerm):

```
winget install wez.wezterm junegunn.fzf jqlang.jq
```

- **fzf ≥ 0.70** (usa `--with-shell`, `--gap`, `--header-border`, `--footer`)
- **wezterm** (terminal)
- **git** (via Git for Windows)
- **jq** (para statusline)
- **JetBrains Mono** + Nerd Font fallback (para glifos)

## Instalação

```
git clone https://github.com/Joorgem/terminal-setup.git ~/Documents/github/terminal-setup
cd ~/Documents/github/terminal-setup
./install.sh
```

O script:
- Copia os arquivos do wezterm para `~/.config/wezterm/`
- Copia `statusline.sh` para `~/.claude/`
- Faz backup `.bak-YYYYMMDD-HHMMSS` de tudo que já existia

Depois, cole o snippet de `claude/settings.snippet.json` no seu `~/.claude/settings.json` (só o bloco `statusLine`).

Abra uma janela nova do WezTerm. Digite `repos` — o launcher abre.

### Instalação seletiva

```
./install.sh wezterm   # só o launcher
./install.sh claude    # só o statusline
./install.sh deps      # só verifica dependências
```

## Uso rápido do launcher

```
repos   →   Enter   →   BRANCHES   →   Enter   →   MODE   →   Enter   →   TARGET
```

### Teclas por tela

**REPOS**
- `Enter` — seleciona repo
- `/` — entrar em modo busca
- `p` — pin/unpin
- `Esc` — sair

**BRANCHES**
- `Enter` — checkout (cria worktree se preciso)
- `/` — buscar
- `n` — nova branch (prompt inline)
- `Esc` — voltar

**MODE**
- `Enter` — selecionar modo
- `Esc` — voltar

**TARGET** (bússola)
- `←` `→` `↑` `↓` — abre split na direção
- `Enter` — abre no pane atual
- `Esc` — voltar

## Onde fica o quê

| O que | Caminho |
|---|---|
| Config WezTerm | `~/.config/wezterm/wezterm.lua` |
| Launcher | `~/.config/wezterm/repo-launcher.sh` |
| Comando `repos` | `~/.config/wezterm/repos` (no PATH) |
| Bashrc custom | `~/.config/wezterm/bashrc.wezterm` |
| Statusline Claude | `~/.claude/statusline.sh` |
| Pins salvos | `~/.local/state/wezterm/repo-pins.txt` (até 3) |
| Log de worktrees | `~/.local/state/wezterm/worktree.log` |

## Worktrees

Cada branch vira um diretório paralelo ao repo principal:

```
~/Documents/github/
├── meu-repo/              ← worktree principal (branch default)
└── meu-repo.wt/
    ├── main/
    ├── feature-x/
    └── origin--hotfix/    ← de branch remota (tracking criado)
```

Nomes com `/` viram `--` no filesystem. `git worktree prune` roda automaticamente ao abrir a tela de branches.

## Atualizando

```
cd ~/Documents/github/terminal-setup
git pull
./install.sh
```

O script sobrescreve com backup. Edita no repo, faz push, e todo mundo puxa pra atualizar.

## Estrutura do repo

```
terminal-setup/
├── README.md
├── install.sh              # instalador com backup
├── wezterm/
│   ├── wezterm.lua         # config principal
│   ├── bashrc.wezterm      # bashrc que define a função 'repos'
│   ├── repo-launcher.sh    # o launcher em si
│   └── repos               # stub no PATH
└── claude/
    ├── statusline.sh
    └── settings.snippet.json   # cole o bloco statusLine no seu settings.json
```

## Customização

- **Cores**: todas as cores ANSI estão no topo de `repo-launcher.sh` (`FZF_THEME`). Paleta Catppuccin Mocha.
- **Font size**: `config.font_size` em `wezterm.lua` (atualmente 13).
- **Filtro de repos**: `load_repos()` filtra `*-agent-*` e `*.wt` — ajuste o grep se precisar.

## Problemas comuns

- **"fzf: command not found"** → instale com `winget install junegunn.fzf`, reabra o terminal.
- **Pointer `▸` aparece como `)`** → fonte não tem o glifo. JetBrains Mono + Nerd Font fallback resolve.
- **`git worktree add` falha** → veja `~/.local/state/wezterm/worktree.log`. Nomes com trailing `.` não funcionam no Windows.
- **Branches remotas não aparecem** → rode `git fetch` no repo primeiro.
