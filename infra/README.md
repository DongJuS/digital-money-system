# infra/ — Windows (Tailscale) box services

All services point at the **Mac tailnet IP `100.123.177.95`** (anvil `:8545`, graph-node `:8040/:8000`).
Prereq on Windows: Docker Desktop (WSL2) + Tailscale up. Confirm reachability first:

```powershell
curl http://100.123.177.95:8545   # anvil
curl http://100.123.177.95:8000/  # graph-node
```

## 1) Monitoring — Prometheus + Grafana
```bash
cd infra/monitoring && docker compose up -d
# Grafana  http://localhost:3001  (admin/admin) → add Prometheus datasource http://prometheus:9090
# Prometheus http://localhost:9090 → target graph-node 100.123.177.95:8040 should be UP
```
graph-node publishes rich Prometheus metrics (subgraph sync head, block ingest, query latency) on `:8040`.

## 2) Blockscout explorer
Blockscout ships a large official compose; only the RPC endpoint needs to change. Use their compose and set:
```
ETHEREUM_JSONRPC_HTTP_URL=http://100.123.177.95:8545
ETHEREUM_JSONRPC_TRACE_URL=http://100.123.177.95:8545
ETHEREUM_JSONRPC_VARIANT=anvil        # (geth-compatible; anvil supports debug/trace)
CHAIN_ID=31337
```
```bash
git clone https://github.com/blockscout/blockscout
cd blockscout/docker-compose
# edit envs/common-blockscout.env with the four vars above, then:
docker compose -f geth.yml up -d      # UI on http://localhost:80
```
(Lightweight alternative: Otterscan — `docker run -p 5100:80 -e ERIGON_URL=http://100.123.177.95:8545 otterscan/otterscan`.)

## 3) Keeper — liquidation daemon
```bash
cd keeper && npm install
RPC_URL=http://100.123.177.95:8545 \
SUBGRAPH=http://100.123.177.95:8000/subgraphs/name/liquity2/liquity2 \
node index.mjs
```
Polls each branch's TroveManager for ICR < MCR and calls `batchLiquidateTroves`. Combine with the M3
price-drop script (mock aggregator `updateAnswer`) on the Mac to trigger a live liquidation end-to-end.
