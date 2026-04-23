# Security Policy

## Reporting a vulnerability

This project is a local terminal launcher — it doesn't handle authentication, network traffic, or sensitive data directly. However, if you find a vulnerability (e.g. shell injection, unsafe handling of untrusted input, or a bug in `install.sh` that could overwrite arbitrary files), please report it privately.

Use GitHub's [security advisory](https://github.com/Joorgem/terminal-setup/security/advisories/new) feature. **Do not open a public issue.**

We aim to acknowledge reports within 7 days.

## In scope

- `wezterm/repo-launcher.sh` — shell injection via branch names, repo paths, or pin files
- `claude/statusline.sh` — injection via `jq` input or unsafe `eval`-like patterns
- `install.sh` — path traversal, unintended file overwrites

## Out of scope

- Vulnerabilities in dependencies (`fzf`, `wezterm`, `git`, `jq`) — please report those upstream
- Issues that require a pre-compromised user environment
- Upstream Claude Code, WezTerm, or MSYS2 bugs
