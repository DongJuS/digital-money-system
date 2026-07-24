# 03 — Execution Roadmap (Manager-owned)

Milestones are gated: each ends with a **runnable acceptance test**. Owner in brackets.
`M` = stablecoin-manager, `C` = contracts-engineer, `I` = infra-devops.

## M0 — Toolchain bootstrap  ✅ acceptance: `forge --version` on Mac, `docker version` on Windows
- [C] Run `scripts/bootstrap-mac.sh` → Foundry, pnpm, node confirmed.
- [I] Run `scripts/bootstrap-windows.ps1` → Docker Desktop + WSL2 + Foundry confirmed.
- [I] Establish LAN IPs of both machines; confirm ping both ways.

## M1 — Contracts compile & test  ✅ acceptance: `forge build` + `forge test` green
- [C] Clone & pin `liquity/bold`; `pnpm install`; `forge build`.
- [C] Run the repo test suite; capture pass/fail verbatim.

## M2 — Local deployment on shared Anvil  ✅ acceptance: Windows can query Mac's Anvil
- [I] Start Anvil on Mac `--host 0.0.0.0:8545`; open firewall; verify `cast block-number` from Windows.
- [C] Deploy bold contracts to Anvil; commit ABIs + addresses to `deployments/`.

## M3 — Core flows working  ✅ acceptance: open trove → borrow BOLD → redeem → trigger liquidation, all via `cast`/tests
- [C] Wire price oracle (mock feed, or `anvil --fork` real Chainlink). Script mint/borrow, redeem, and a liquidation scenario.

## M4 — Indexer + explorer  ✅ acceptance: subgraph returns the deployed troves; explorer shows txs
- [I] Bring up graph-node + IPFS + Postgres on Windows (compose), pointed at Mac Anvil.
- [C→I] Deploy the bold subgraph against the M2 addresses.
- [I] Stand up Blockscout/Otterscan on Windows.

## M5 — Frontend + keepers  ✅ acceptance: mint from the browser; keeper auto-liquidates an unhealthy trove
- [I] Run the bold Next.js frontend on Mac, pointed at Anvil + subgraph.
- [I] Deploy a keeper/liquidation bot on Windows.

## M6 — Monitoring + reproducibility  ✅ acceptance: `docker-compose up` reproduces the whole cluster; Grafana shows metrics
- [I] Prometheus + Grafana dashboards (RPC health, trove count, liquidations).
- [M] One-command bring-up per machine; write a runbook.

## Stretch
- Mainnet-fork environment (real collateral + Chainlink) hosted on whichever box has spare RAM.
- Compare crvUSD LLAMMA soft-liquidation vs Liquity hard-liquidation.
- k3s across both machines instead of per-machine compose.

## First action for the team
Manager kicks off **M0** in parallel: `contracts-engineer` on the Mac, `infra-devops` on Windows.
