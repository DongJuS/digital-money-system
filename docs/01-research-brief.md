# 01 — Stablecoin Implementation Research Brief

**Date:** 2026-07-24 · **Method:** GitHub REST API (stars, last-push) + web verification.
**Question:** Which most-starred / most-recent open-source stablecoin can a 2-person home lab actually build end-to-end?

## Verified candidate catalog (2026-07-24)

| Repo | ★ | Last push | Stack | Type | Notes |
|---|---:|---|---|---|---|
| `sky-ecosystem/dss` (Maker→Sky) | 839 | 2023-10 | Solidity | Crypto CDP | Authoritative, battle-tested, but **frozen** in this repo; heavy, sparse local-devnet story. |
| `curvefi/curve-stablecoin` (crvUSD) | 539 | **2026-07-23** | **Vyper**/Python | LLAMMA soft-liquidation | Most *active*; brilliant AMM-liquidation design but **highest build friction** (Vyper, math-heavy). |
| `FraxFinance/frax-solidity` | 534 | 2025-10 | Solidity | Fractional-algorithmic | Broad, sprawling; many products in one repo. |
| `liquity/dev` (v1) | 358 | 2025-11 | Solidity + Hardhat | Crypto CDP (110%) | Clean, superbly documented, includes a dev frontend. Great **learning ramp**. |
| `aave/gho-core` | 263 | 2025-09 | Solidity | Facilitator-minted | Depends on the wider Aave stack to be interesting. |
| `reflexer-labs/geb` (RAI) | 142 | 2023-12 | Solidity | Non-pegged (PID) | Elegant control theory; **abandoned**. |
| **`liquity/bold` (v2)** | 133 | **2026-07-13** | **Solidity + Foundry** | Crypto CDP + user-set rates | **Monorepo: contracts + subgraph + frontend.** Active. Best full-stack buildability. |
| `BeanstalkFarms/Beanstalk` | 127 | 2026-05 | TypeScript/Sol | Credit-based algo | Complex, unusual model. |
| `OriginProtocol/origin-dollar` (OUSD) | 151 | 2026-07-23 | Solidity | Yield-bearing wrapper | Not a from-scratch peg mechanism. |
| `AngleProtocol/angle-core` | 92 | 2024-02 | Solidity | Over-collateralized EUR | Superseded by newer Angle repos. |

Star counts favor category leaders; **build-ability** favors a self-contained, actively maintained, well-tooled monorepo.

## Recommendation — base = **Liquity**

1. **Primary: `liquity/bold` (Liquity v2).** A single Foundry monorepo shipping **contracts + subgraph + frontend** — the whole full-stack in one place, still maintained (July 2026). Lowest friction to reach "mint/borrow/redeem/liquidate + oracle + UI running locally."
2. **Learning ramp: `liquity/dev` (Liquity v1).** Simpler 110%-CDP + Stability Pool, excellent docs — ideal to understand the mechanics before v2's user-set interest rates and multi-collateral design.
3. **Stretch / comparison: `curvefi/curve-stablecoin`.** Study LLAMMA soft-liquidation after v1/v2 land; expect Vyper toolchain overhead.

**Why not Maker/Sky `dss`:** authoritative but frozen in that repo and operationally heavy for a home lab. **Why not crvUSD as the base:** most active and elegant, but Vyper + LLAMMA math is the steepest on-ramp.

## Full-stack component map (nothing missed)

- **On-chain:** core CDP/trove manager · stablecoin (ERC-20) token · price oracle (Chainlink feed or mock) · liquidation engine · Stability Pool / redemption logic · optional governance.
- **Off-chain:** keeper/liquidation bot · oracle relayer (if not forking real feeds) · subgraph/indexer (The Graph) · RPC node (Anvil, or Reth/Geth for a mainnet fork).
- **Frontend:** the bold monorepo Next.js dApp (open a trove, borrow, redeem, watch liquidations).
- **Local chain:** Anvil (fresh) or `anvil --fork-url <mainnet>` to deploy against real Chainlink + collateral tokens.

### Rough resource demands (drives the 2-machine split — see `02`)
| Component | CPU | RAM | Disk | Home |
|---|---|---|---|---|
| Foundry build/test | bursty high | low (<1GB) | low | Mac |
| Anvil (fresh) | low | ~0.5GB | low | Mac |
| Anvil `--fork` mainnet | medium | 2–6GB (state) | medium | Windows |
| graph-node + IPFS + Postgres | medium | 3–5GB | medium/high | Windows |
| Frontend dev server | low | ~1GB | low | Mac |
| Keeper bots | low | <0.5GB ea | low | Windows |
| Blockscout explorer | medium | 2–4GB | medium | Windows |
| Prometheus + Grafana | low | ~1GB | low/med | Windows |

## Sources
- https://github.com/liquity/bold · https://github.com/liquity/dev
- https://github.com/curvefi/curve-stablecoin · https://github.com/sky-ecosystem/dss
- https://github.com/FraxFinance/frax-solidity · https://github.com/aave/gho-core
- https://github.com/reflexer-labs/geb · https://github.com/OriginProtocol/origin-dollar
