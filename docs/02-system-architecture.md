# 02 — Maximum System Architecture (2-machine resource sharing)

Given **Mac M5 Pro (15 cores, 48GB, arm64)** + **Windows PC (32GB+, 8+ cores, GPU)** on one LAN,
the *maximum* system you can comfortably run for a **local full-stack stablecoin (Liquity v2 / bold)** is a
**split "dev vs. services" cluster** joined into one logical devnet.

```
                        HOME LAN (e.g. 192.168.0.0/24)
 ┌──────────────────────────────────┐        ┌───────────────────────────────────────┐
 │  MAC  M5 Pro · 48GB · arm64       │        │  WINDOWS PC · 32GB+ · 8c+ · GPU        │
 │  role: DEV + latency-sensitive    │        │  role: HEAVY / Dockerized services      │
 │                                   │        │                                         │
 │  • Foundry (forge/anvil/cast)     │  RPC   │  Docker Desktop / WSL2:                  │
 │  • Anvil devnet  :8545 ─────────────8545──▶│   • graph-node :8000  (subgraph API)    │
 │      (--host 0.0.0.0)             │◀──idx──│   • IPFS :5001 · Postgres :5432         │
 │  • Next.js frontend :3000 ────────query───▶│   • Blockscout explorer :4000           │
 │  • deploy scripts, ABIs/addrs     │        │   • keeper / liquidation bots           │
 │  • agent orchestration            │        │   • Prometheus :9090 + Grafana :3001    │
 │                                   │        │   • (opt) Reth/Geth mainnet-fork node   │
 └──────────────────────────────────┘        └───────────────────────────────────────┘
        git (GitHub or bare repo on one host)  ── source of truth ──
```

## Why this split
- **Latency-sensitive + native-fast** work (compile, Anvil, cast, the frontend you click on) stays on the **Mac** — arm64 Foundry is very fast, and you avoid LAN round-trips on the hot path.
- **RAM/disk-hungry, long-running services** (The Graph indexer stack, explorer, monitoring, a mainnet-fork archive-ish node) go to the **Windows box**, isolated in Docker so they can't disturb dev flow. The GPU is spare capacity (not needed by the core stack; usable for a monitoring/anomaly-detection or load-sim experiment).

## The "share resources" mechanism (concrete)
1. **One logical devnet:** Anvil runs on the Mac bound to `0.0.0.0:8545`. Every Windows service uses `http://<MAC_LAN_IP>:8545` — not `localhost`.
2. **Firewall:** open inbound 8545/3000 on macOS; open the Docker service ports inbound on Windows Defender.
3. **Alternative topology (heavier fork):** if you want a *mainnet fork* with lots of state, run `anvil --fork-url` (or a Reth dev node) on **Windows** instead, and point the Mac frontend/scripts at `http://<WIN_LAN_IP>:8545`. Pick the fork host = the machine with spare RAM at the time.
4. **Source of truth:** a shared git remote (GitHub, or a bare repo on one machine) so both machines and all 3 agents work off the same tree. ABIs + deployed addresses are committed as JSON artifacts (`deployments/`).
5. **Orchestration:** `docker-compose up` per machine (not k8s). k3s across both is a documented *stretch* goal, not needed for 2 nodes.

## Resource budget (headroom is generous)
| Machine | Reserved for it | Approx peak | Free headroom |
|---|---|---|---|
| Mac 48GB | Foundry + Anvil + frontend + OS + agents | ~8–12GB | large |
| Windows 32GB | graph stack + explorer + monitoring + bots (+ fork node) | ~14–20GB | comfortable |

**Verdict on "maximum system":** with these two machines you can run the *entire* production-shaped topology of a modern CDP stablecoin at once — L1 devnet, full protocol contracts, indexer, explorer, keeper automation, monitoring, and a real UI — with room to also run a **mainnet-fork** environment for realistic oracle/collateral testing. The limiting factor is not hardware; it's build effort, which the 3-agent team is structured to parallelize.

## Ports (defaults)
| Service | Host | Port |
|---|---|---|
| Anvil RPC | Mac (or Win for fork) | 8545 |
| Frontend (Next.js) | Mac | 3000 |
| graph-node (GraphQL) | Windows | 8000 / 8020 (admin) |
| IPFS | Windows | 5001 |
| Postgres | Windows | 5432 |
| Blockscout | Windows | 4000 |
| Prometheus / Grafana | Windows | 9090 / 3001 |
