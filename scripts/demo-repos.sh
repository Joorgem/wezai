#!/bin/bash
# demo-repos.sh — create fake repos for README screenshots
#
# Usage:
#   ./scripts/demo-repos.sh setup     # create demo repos + state dir (isolated from your real pins)
#   ./scripts/demo-repos.sh launch    # setup must have run first; launches repos against demo
#   ./scripts/demo-repos.sh teardown  # remove demo dirs

set -euo pipefail

DEMO_DIR="${DEMO_DIR:-$HOME/.cache/wezai-demo}"
DEMO_STATE="${DEMO_STATE:-$HOME/.cache/wezai-demo-state}"
ACTION="${1:-}"

teardown() {
  local removed=0
  if [[ -d "$DEMO_DIR" ]]; then
    echo "removing $DEMO_DIR"
    rm -rf "$DEMO_DIR"
    removed=1
  fi
  if [[ -d "$DEMO_STATE" ]]; then
    echo "removing $DEMO_STATE"
    rm -rf "$DEMO_STATE"
    removed=1
  fi
  ((removed)) || echo "nothing to remove"
}

launch() {
  if [[ ! -d "$DEMO_DIR" ]]; then
    echo "demo not set up. run: $0 setup" >&2
    exit 1
  fi
  # exec so this process is replaced by the launcher (signals, exit code propagate correctly)
  XDG_STATE_HOME="$DEMO_STATE" GITHUB_DIR="$DEMO_DIR" exec repos
}

# commit helper: cd into repo, add, commit with backdated date
_commit() {
  local msg="$1"
  local days_ago="${2:-0}"
  local d
  d=$(date -d "$days_ago days ago" '+%Y-%m-%dT12:00:00')
  GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" \
    git -c user.name="Demo Dev" -c user.email="demo@example.com" \
    commit -q --allow-empty -m "$msg"
}

# create a new branch pointing at current HEAD
_branch() {
  git branch -q "$1"
}

# simulate a remote-tracking ref so the BRANCHES screen shows the ↓ category
_fake_remote() {
  local branch="$1"
  local sha
  sha=$(git rev-parse HEAD)
  git update-ref "refs/remotes/origin/$branch" "$sha"
  git remote add origin "https://example.com/demo/$(basename "$PWD").git" 2>/dev/null || true
}

# touch a file without committing (creates dirty state)
_dirty() {
  echo "$1" >> "$2"
}

make_nova_api() {
  local path="$DEMO_DIR/nova-api"
  mkdir -p "$path" && cd "$path"
  git init -q -b main

  cat > README.md <<'EOF'
# nova-api

Lightweight HTTP API for the Nova platform. Built on Fastify with typed routes.
EOF
  mkdir -p src routes
  echo 'export const version = "0.4.2";' > src/index.ts
  echo 'export async function users() { return []; }' > routes/users.ts
  echo '{"name":"nova-api","version":"0.4.2"}' > package.json

  git add -A
  _commit "feat: initial route scaffold" 14
  _commit "refactor: extract user router" 9
  _commit "fix: handle empty body on POST" 4
  _commit "docs: update README quickstart" 2

  _branch feature-auth
  _fake_remote main
}

make_user_dashboard() {
  local path="$DEMO_DIR/user-dashboard"
  mkdir -p "$path" && cd "$path"
  git init -q -b main

  cat > README.md <<'EOF'
# user-dashboard

React dashboard for end-user account management.
EOF
  mkdir -p src/components
  echo 'export const App = () => <main>dashboard</main>;' > src/components/App.tsx
  echo 'import { App } from "./components/App";' > src/index.tsx

  git add -A
  _commit "feat: bootstrap vite + react" 21
  _commit "feat: add App shell with router" 18
  _commit "feat: settings page scaffold" 11
  _commit "refactor: split layout components" 5
  _commit "test: cover settings form" 3

  _branch feature-settings
  _branch fix-login
  _fake_remote main
  _fake_remote feature-settings
}

make_payment_service() {
  local path="$DEMO_DIR/payment-service"
  mkdir -p "$path" && cd "$path"
  git init -q -b main

  cat > README.md <<'EOF'
# payment-service

Stripe + Pix reconciliation worker. Idempotent by design.
EOF
  echo 'export class Reconciler {}' > reconciler.ts
  echo 'export const providers = ["stripe","pix"];' > providers.ts

  git add -A
  _commit "feat: idempotent reconciliation loop" 30
  _commit "feat: add Pix provider" 22
  _commit "fix: retry with exponential backoff" 12

  # dirty: uncommitted changes
  _dirty '// TODO: handle partial refunds' reconciler.ts
  _dirty 'export const webhookSecret = process.env.WEBHOOK_SECRET;' providers.ts
  echo 'WEBHOOK_SECRET=' > .env.example
}

make_blog_engine() {
  local path="$DEMO_DIR/blog-engine"
  mkdir -p "$path" && cd "$path"
  git init -q -b main

  cat > README.md <<'EOF'
# blog-engine

Markdown-first static blog generator. 10kb of Go.
EOF
  echo 'package main' > main.go
  echo 'func main() { println("blog") }' >> main.go

  git add -A
  _commit "feat: initial Go module" 60
  _commit "feat: markdown → HTML pipeline" 55
  _commit "feat: RSS feed generator" 42
  _fake_remote main
}

make_cli_kit() {
  local path="$DEMO_DIR/cli-kit"
  mkdir -p "$path" && cd "$path"
  git init -q -b main

  cat > README.md <<'EOF'
# cli-kit

Opinionated CLI builder for Bun — flags, subcommands, help.
EOF
  mkdir -p src
  echo 'export { defineCLI } from "./builder";' > src/index.ts
  echo 'export const defineCLI = (spec) => ({ run: () => {} });' > src/builder.ts

  git add -A
  _commit "feat: define defineCLI contract" 40
  _commit "feat: flag parsing" 35
  _commit "feat: subcommand routing" 28
  _commit "perf: cache help output" 15

  _branch refactor-parser
  _fake_remote main
}

make_data_pipeline() {
  local path="$DEMO_DIR/data-pipeline"
  mkdir -p "$path" && cd "$path"
  git init -q -b main

  cat > README.md <<'EOF'
# data-pipeline

Airflow DAGs for the ingestion ETL. Parquet output to S3.
EOF
  mkdir -p dags
  echo '# ingest.py' > dags/ingest.py
  echo 'def ingest(): pass' >> dags/ingest.py

  git add -A
  _commit "feat: initial ingestion DAG" 18
  _commit "feat: dedupe on natural key" 10
  _commit "fix: handle empty partitions" 6

  _branch feature-etl-v2

  # dirty
  _dirty '# TODO: backfill from 2024-01-01' dags/ingest.py

  _fake_remote main
  _fake_remote feature-etl-v2
  _fake_remote hotfix-rate-limit
}

setup() {
  if [[ -d "$DEMO_DIR" ]]; then
    echo "demo dir already exists: $DEMO_DIR"
    echo "run: $0 teardown"
    exit 1
  fi
  mkdir -p "$DEMO_DIR"
  echo "creating demo repos in $DEMO_DIR"
  echo

  make_nova_api
  echo "  ✓ nova-api"
  make_user_dashboard
  echo "  ✓ user-dashboard"
  make_payment_service
  echo "  ✓ payment-service (dirty)"
  make_blog_engine
  echo "  ✓ blog-engine"
  make_cli_kit
  echo "  ✓ cli-kit"
  make_data_pipeline
  echo "  ✓ data-pipeline (dirty)"

  # isolated state dir with pins pre-set, so real pins are not touched
  mkdir -p "$DEMO_STATE/wezterm"
  printf 'nova-api\nuser-dashboard\n' > "$DEMO_STATE/wezterm/repo-pins.txt"
  # seed a couple of custom modes so the MODE screen looks rich in screenshots
  printf 'aider\taider --model sonnet\ngitui\tgitui\n' > "$DEMO_STATE/wezterm/custom-modes.tsv"

  echo
  echo "launch the launcher against demo (real pins untouched):"
  echo "  bash $0 launch"
}

case "$ACTION" in
  setup)    setup ;;
  teardown) teardown ;;
  launch)   launch ;;
  *)        echo "usage: $0 [setup|teardown|launch]"; exit 1 ;;
esac
