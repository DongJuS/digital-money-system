# infra/ — Windows (Tailscale) box services

All services point at the **Mac tailnet IP `MAC_TAILNET_IP`** (anvil `:8545`, graph-node `:8040/:8000`).
The Windows box is driven from the Mac over **Tailscale SSH** (`ssh <user>@<win-host>`).

> **VERIFIED (2026-07-25):** keeper + monitoring run on the Windows box against the Mac's chain over Tailscale.
> - Keeper (native Node) → cross-machine liquidation: dropped a branch price on the Mac, the **Windows keeper
>   liquidated 7/8 troves** on the Mac's anvil (branch count 8→1), confirmed from the Mac.
> - Prometheus (WSL2 docker) → `up{job="graph-node", instance="MAC_TAILNET_IP:8040"} = 1` + Grafana v13.1.1.

### Docker on Windows — use native dockerd in WSL2 (headless), not Docker Desktop
Docker Desktop needs an interactive desktop session and won't start over SSH. Use WSL2's native engine:
```bash
wsl -d Ubuntu -u root -- bash -lc \
  "dpkg --configure -a; rm -f /usr/bin/docker; \
   apt-get update && apt-get install -y docker.io docker-compose-v2 && \
   systemctl enable --now docker && docker --version"
# WSL2 reaches the Mac tailnet IP directly (verified). Use network_mode: host so containers hit MAC_TAILNET_IP.
```
Confirm reachability first (from WSL): `curl http://MAC_TAILNET_IP:8545` and `http://MAC_TAILNET_IP:8040/metrics`.

## 1) Monitoring — Prometheus + Grafana  (VERIFIED on Windows/WSL2)
For the Windows box, set the Prometheus target to `MAC_TAILNET_IP:8040` and use `network_mode: host`
(so containers reach the Mac tailnet IP directly). Grafana `GF_SERVER_HTTP_PORT=3001`, host networking.
```bash
cd infra/monitoring && docker compose up -d
# Prometheus :9090 -> up{job="graph-node"} == 1   (scraping the Mac over Tailscale)
# Grafana :3001 (admin/admin), datasource Prometheus = http://localhost:9090
```
graph-node publishes rich Prometheus metrics (subgraph sync head, block ingest, query latency) on `:8040`.

## 2) Blockscout explorer  (config verified; heavy pull)
Blockscout ships a dedicated **`anvil.yml`** compose (variant `anvil`, CHAIN_ID 31337). In WSL2 docker the
default `host.docker.internal:8545` points at Windows, not the Mac — **repoint every RPC URL to the Mac tailnet IP**:
```bash
cd ~/blockscout/docker-compose
sed -i "s#host.docker.internal:8545#MAC_TAILNET_IP:8545#g" envs/common-blockscout.env anvil.yml
docker compose -f anvil.yml up -d      # 12 services; UI on the proxy port (:80)
```
Bridge containers in WSL2 reach `MAC_TAILNET_IP` fine (verified). **Caveat:** the stack is ~several GB across
12 images; on a slow/flaky link the pull can take a long time. Pull it while a live WSL session is held (or as a
persistent `systemd-run` unit) so it isn't killed by WSL idle-shutdown, then `up -d`. If the box bogs down under
the pull, let it settle and resume `up -d` (cached layers continue). Alternatively run Blockscout on the Mac
(colima) where pulls are fast, pointed at `localhost:8545`.
(Lightweight alternative: Otterscan — `docker run -p 5100:80 -e ERIGON_URL=http://MAC_TAILNET_IP:8545 otterscan/otterscan`.)

## 3) Keeper — liquidation daemon  (VERIFIED on Windows, native Node)
No Docker needed — just Node 20+.
```bash
cd keeper && npm install
RPC_URL=http://MAC_TAILNET_IP:8545 \
SUBGRAPH=http://MAC_TAILNET_IP:8000/subgraphs/name/liquity2/liquity2 \
KEEPER_ACCOUNT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
node index.mjs
```
Discovers branches via the subgraph, reads price from `getUnbackedPortionPriceAndRedeemability`,
liquidates ICR<MCR troves via `batchLiquidateTroves` (caps to count-1). `KEEPER_ACCOUNT` = node-signing
(anvil unlocked); real deployments set `KEEPER_PK`. Trigger with the M3 price-drop on the Mac.
