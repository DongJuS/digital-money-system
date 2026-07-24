#!/usr/bin/env bash
# Bootstrap the MAC (M5 Pro, arm64) as the DEV + latency-sensitive node.
# Installs Foundry, pnpm, and confirms Node/Docker. Idempotent-ish; safe to re-run.
set -euo pipefail

echo "==> Homebrew"
command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "==> Foundry (forge/anvil/cast)"
if ! command -v forge >/dev/null; then
  curl -L https://foundry.paradigm.xyz | bash
  # shellcheck disable=SC1090
  source "$HOME/.bashrc" 2>/dev/null || true
  export PATH="$HOME/.foundry/bin:$PATH"
  foundryup
fi

echo "==> pnpm (bold monorepo package manager)"
command -v pnpm >/dev/null || npm install -g pnpm

echo "==> Docker (optional on Mac; Colima is a light arm64 option)"
command -v docker >/dev/null || echo "   (skip) install Docker Desktop or 'brew install colima docker' if you want to run services here too"

echo "==> LAN IP of this Mac (share with the Windows box):"
ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "   run: ifconfig | grep 'inet '"

echo "==> Versions"
forge --version || true
anvil --version || true
node --version; pnpm --version

cat <<'NEXT'

NEXT (contracts-engineer):
  git clone https://github.com/liquity/bold && cd bold
  pnpm install && forge build && forge test
  # start shared devnet for the cluster:
  anvil --host 0.0.0.0 --port 8545
NEXT
