# Contributing

Thanks for your interest. This project is small and opinionated, but PRs are welcome.

## Scope

- **Target platform:** Windows 10/11 + Git Bash + WezTerm. Ports to Mac/Linux are out of scope for now — happy to discuss them in an issue.
- **Design language:** hacker-minimal, Catppuccin Mocha with green accents. See `CLAUDE.md` for the palette and conventions.
- **No daemons, no databases.** The launcher is stateless; runtime state lives only in `~/.local/state/wezterm/`.

## Before opening a PR

1. **Validate shell syntax:**
   ```bash
   bash -n wezterm/repo-launcher.sh
   ```
2. **Test in a fresh WezTerm window** — not the one running your old version. A bug in `repo-launcher.sh` can lock your login shell. See the "Testing safely" section in `CLAUDE.md`.
3. **Respect the conventional commit format:** `feat:`, `fix:`, `refactor:`, `docs:`, `style:`, `chore:`, `test:`, `perf:`, `ci:`. Scope is optional: `feat(branches): ...`.
4. **Keep diffs focused.** One concern per PR.

## Reporting issues

Use the templates in `.github/ISSUE_TEMPLATE/`. Please include:

- Windows version, Git Bash version, WezTerm version, fzf version (`>= 0.70` required)
- Exact reproduction steps
- Relevant lines from `~/.local/state/wezterm/worktree.log` when applicable

## Design discussions

For open-ended questions or ideas, please open a GitHub **Discussion** instead of an Issue.

## Windows pitfalls you should know about

This project lives on the Windows + MSYS2 + native-Git boundary, which has quirks. Before proposing changes to the launcher, skim the "Armadilhas do Windows / Git Bash" section in `CLAUDE.md` — it documents the seven traps we've already hit and worked around.
