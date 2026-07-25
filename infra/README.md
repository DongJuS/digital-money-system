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

## 2) Blockscout explorer  (RUNNING on Windows/WSL2 — 12 services, indexing the Mac chain)
Blockscout ships a dedicated **`anvil.yml`** compose (variant `anvil`, CHAIN_ID 31337). Verified recipe:
```bash
cd ~/blockscout/docker-compose
# a) repoint every RPC URL at the Mac (default host.docker.internal points at Windows, not the Mac)
sed -i "s#host.docker.internal:8545#MAC_TAILNET_IP:8545#g" envs/common-blockscout.env anvil.yml
# b) fixes needed for a local anvil deploy:
echo "ECTO_USE_SSL=false"            >> envs/common-blockscout.env   # db has no SSL
echo "NFT_MEDIA_HANDLER_ENABLED=false" >> envs/common-blockscout.env # avoids dets :eacces
mkdir -p dets logs && chmod -R 777 dets logs                          # backend writes ./dets
docker compose -f anvil.yml up -d                                     # 12 services; UI on proxy :80
docker update --restart unless-stopped $(docker ps -q)                # survive WSL restarts
```
Bridge containers reach `MAC_TAILNET_IP` fine; backend indexes from block 0 (verified: 193 txns, "index caught up",
API 200, UI 200). **Pull caveat:** ~several GB / 12 images on a flaky link — pull under a persistent `systemd-run`
unit (sequential per-service with retries) so WSL idle-shutdown doesn't kill it; add `[wsl2]\nvmIdleTimeout=-1` to
`%USERPROFILE%\.wslconfig` for stability.

**Browser access from the Mac (the hard part):** WSL2 services are NOT reachable from the Windows host by default —
the **WSL Hyper-V firewall blocks inbound** (`DefaultInboundAction=Block`) and localhost-forwarding/portproxy then
fail. One of these (each a one-time action) fixes it:
- *Elevated PowerShell on Windows:* `Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow`
  then `netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=4000 connectaddress=<WSL_IP> connectport=80`
  + firewall-allow 4000 → browse `http://WINDOWS_TAILNET_IP:4000`.
- *Or* run `tailscale up` inside WSL (join the tailnet directly) → browse the WSL tailnet IP:80.
- *Or* run Blockscout on the Mac (colima) pointed at `localhost:8545` (no cross-host networking).
(Note: `networkingMode=mirrored` failed on this box — `0x8007054f` — keep NAT.)

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
