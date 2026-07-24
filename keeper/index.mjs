// Liquidation keeper daemon (Liquity v2 / bold).
// Polls the subgraph for troves, checks health via each branch TroveManager,
// and calls batchLiquidateTroves on under-collateralized ones.
// Designed to run on the Windows (Tailscale) box, pointed at the Mac anvil + graph-node.
//
// Run:  RPC_URL=http://MAC_TAILNET_IP:8545 \
//       SUBGRAPH=http://MAC_TAILNET_IP:8000/subgraphs/name/liquity2/liquity2 \
//       node index.mjs
//
// Deps:  npm i viem   (Node 20+)

import { createPublicClient, createWalletClient, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const RPC_URL = process.env.RPC_URL ?? "http://MAC_TAILNET_IP:8545";
const SUBGRAPH = process.env.SUBGRAPH ?? "http://MAC_TAILNET_IP:8000/subgraphs/name/liquity2/liquity2";
// anvil account #0 (dev only — never use a real key here)
const PK = process.env.KEEPER_PK ?? "0xac0974bec39a17e36ba4a6b4d238ff944bae0e5c469daf7d449b5cf1a5c8f97e";
const POLL_MS = Number(process.env.POLL_MS ?? 12000);

const tmAbi = parseAbi([
  "function getTroveIdsCount() view returns (uint256)",
  "function getTroveFromTroveIdsArray(uint256) view returns (uint256)",
  "function getCurrentICR(uint256 troveId, uint256 price) view returns (uint256)",
  "function getTroveStatus(uint256) view returns (uint8)",
  "function batchLiquidateTroves(uint256[] troveArray)",
]);
const pfAbi = parseAbi(["function fetchPrice() returns (uint256, bool)", "function lastGoodPrice() view returns (uint256)"]);
const MCR = 1100000000000000000n; // 110% (branch-dependent; read from TroveManager.MCR() for production)

const account = privateKeyToAccount(PK);
const pub = createPublicClient({ transport: http(RPC_URL) });
const wallet = createWalletClient({ account, transport: http(RPC_URL) });

// Discover branches (TroveManager + PriceFeed) from the subgraph's CollateralAddresses.
async function branches() {
  const q = `{ collaterals{ collIndex addresses{ troveManager priceFeed } } }`;
  const res = await fetch(SUBGRAPH, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ query: q }),
  }).then((r) => r.json());
  return (res.data?.collaterals ?? []).map((c) => ({
    idx: c.collIndex, tm: c.addresses.troveManager, pf: c.addresses.priceFeed,
  }));
}

async function scanBranch(b) {
  const price = await pub.readContract({ address: b.pf, abi: pfAbi, functionName: "lastGoodPrice" }).catch(() => 0n);
  const count = await pub.readContract({ address: b.tm, abi: tmAbi, functionName: "getTroveIdsCount" });
  const unhealthy = [];
  for (let i = 0n; i < count; i++) {
    const id = await pub.readContract({ address: b.tm, abi: tmAbi, functionName: "getTroveFromTroveIdsArray", args: [i] });
    const icr = await pub.readContract({ address: b.tm, abi: tmAbi, functionName: "getCurrentICR", args: [id, price] }).catch(() => 2n * MCR);
    if (icr < MCR) unhealthy.push(id);
  }
  if (unhealthy.length) {
    console.log(`[branch ${b.idx}] liquidating ${unhealthy.length} trove(s) @ price ${price}`);
    const hash = await wallet.writeContract({ address: b.tm, abi: tmAbi, functionName: "batchLiquidateTroves", args: [unhealthy] });
    console.log(`  tx ${hash}`);
  }
}

async function tick() {
  try {
    const bs = await branches();
    for (const b of bs) await scanBranch(b);
    process.stdout.write(".");
  } catch (e) { console.error("tick error:", e.shortMessage ?? e.message); }
}

console.log(`keeper up — RPC ${RPC_URL}, subgraph ${SUBGRAPH}, poll ${POLL_MS}ms`);
await tick();
setInterval(tick, POLL_MS);
