# digital_money_system — local full-stack stablecoin lab

A learning/dev build of a modern **CDP stablecoin**, run across two home machines with a 3-agent team.

## Decision summary (2026-07-24)
- **Base protocol:** **Liquity v2 — [`liquity/bold`](https://github.com/liquity/bold)** (Foundry monorepo: contracts + subgraph + frontend; actively maintained). Learning ramp: **Liquity v1 [`liquity/dev`](https://github.com/liquity/dev)**. See [`docs/01-research-brief.md`](docs/01-research-brief.md) for the full ranked catalog and why.
- **Topology:** Mac M5 Pro (48GB, arm64) = **dev + latency-sensitive**; Windows PC (32GB+, GPU) = **heavy Dockerized services**, joined into one LAN devnet. See [`docs/02-system-architecture.md`](docs/02-system-architecture.md).
- **Goal level:** local testnet full-stack — mint / borrow / redeem / liquidate + oracle + indexer + explorer + frontend + monitoring.

> **Environment values:** infra files use placeholders (`MAC_TAILNET_IP`, `WINDOWS_TAILNET_IP`, `LINUX_TAILNET_IP`). The real Tailscale IPs/hostnames live in the **private** overlay repo `digital-money-system-env` — substitute them from there.

## The 3-agent team (`.claude/agents/`)
| Agent | Role | Machine focus |
|---|---|---|
| `stablecoin-manager` | **Manager** — plans, delegates, integrates, gates milestones | both |
| `contracts-engineer` | Worker — Solidity/Foundry: protocol, oracle, liquidations, tests | Mac |
| `infra-devops` | Worker — cluster, Anvil/LAN, subgraph, explorer, bots, monitoring | Windows |

Invoke the manager to drive: it splits work to the two workers and tracks the roadmap.

## Quick start
```bash
# Mac
bash scripts/bootstrap-mac.sh
# Windows (elevated PowerShell)
powershell -ExecutionPolicy Bypass -File scripts/bootstrap-windows.ps1
```
Then follow [`docs/03-roadmap.md`](docs/03-roadmap.md) M0 → M6.

## Layout
```
.claude/agents/   3 agent definitions (manager + 2 workers)
docs/             research brief · architecture · roadmap
scripts/          per-machine bootstrap
deployments/      (created at M2) committed ABIs + addresses
```
