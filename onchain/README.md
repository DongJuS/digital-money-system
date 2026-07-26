# onchain/ — institution-issued stablecoin (our own, not Liquity)

A minimal **central-issuer** digital currency that matches the "한국은행처럼 기관이 발행 + 달러 환율 연동" model.
Unlike Liquity (which we also run elsewhere in this repo), there is **no collateral and no liquidation** — an
institution simply issues coins to people, and a live FX rate is published on-chain for reference.

## Contracts (`src/`)
- **`StableToken.sol`** — a self-contained ERC-20. The `issuer` (institution) `issue()`/`issueBatch()`/`retire()`;
  holders `transfer`/`approve` freely. No collateral held.
- **`FxOracle.sol`** — the institution (`updater`) publishes a reference rate (e.g. `USD/KRW`, scaled 1e8).
  `latestRate()`, `convert()`, `isStale()`. No funds held.

## Off-chain
- **`../fx-relayer/`** — Node script; fetches USD/KRW from a public API (`open.er-api.com`) and pushes it to
  `FxOracle.setRate` (like an institution publishing the daily reference rate).

## Run it (local anvil already running on :8545)
```bash
forge test                 # 11 tests pass (StableToken + FxOracle)
bash deploy-local.sh       # deploy both, issue dKRW to 5 people -> deployment.local.json
cd ../fx-relayer && npm i && node index.mjs --once   # push live USD/KRW on-chain
cd ../onchain && bash demo.sh                         # holdings + USD value + a p2p transfer
```

## Verified demo output
```
기관 발행 디지털 통화: dKRW | 환율(USD/KRW): 1,462.79 (API 실시간)
person1..5 hold dKRW, each shown with ≈ USD value
person1 → person3: 200 dKRW transfer, balances update
총 발행량: 7,950 dKRW
```

## What this is / isn't
- ✅ institution issues & distributes; people hold & send; USD rate linked via API (on-chain oracle)
- ❌ no real dollar custody/reserves, no KYC, no public deployment, no audit — a working local prototype
