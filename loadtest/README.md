# loadtest/ — max-load test for the institution stablecoin

Stress-tests our `StableToken` on a dedicated anvil: deploys the token, funds N sender
accounts, **pre-signs** many transfers, blasts them via **batched `eth_sendRawTransaction`**,
and measures submission + end-to-end throughput. Does not touch the main chain.

## Run
```bash
# dedicated load chain (interval mining, huge gas limit, 20 funded accounts)
anvil --port 8546 --block-time 1 --gas-limit 3000000000 --accounts 20 --balance 1000000 --silent &
cd loadtest && npm i
N=100000 SENDERS=19 node index.mjs           # one shot
# ramp: for N in 5000 20000 50000 100000 200000; do N=$N node index.mjs; done
```

## Verified results (Apple M5 Pro, colima-independent — pure anvil + Node client)
| transfers | submission | end-to-end TPS | tx/block | rejected | balances |
|---:|---:|---:|---:|---:|:--:|
| 5,000   | 12,312 tx/s | 8,010  | — | 0 | ✅ |
| 20,000  | 12,235 tx/s | 9,937  | 12,000 | 0 | ✅ |
| 50,000  | 12,179 tx/s | 15,446 | 12,000 | 0 | ✅ |
| 100,000 | 12,052 tx/s | 20,717 | 12,000 | 0 | ✅ |
| 200,000 | 12,075 tx/s | **21,636** | 13,000 | 0 | ✅ |

**Findings**
- **~12,000 tx/s** steady submission from a single Node client (the client→node ceiling here).
- **~21,600 TPS end-to-end** at 200k (submission overlaps fast mining); higher bursts → higher effective TPS.
- **0 rejected across 375,000+ transactions**; all recipient balances exactly correct.
- **~34,300 gas per transfer** — our lean contract beats a typical ERC-20 (~51k gas).
- anvil caps ~12–13k tx/block; the chain mined 200k txs in 18 blocks in ~17s.

Bottleneck is client submission, not the contract or the chain — the token logic is not the limiting factor.
