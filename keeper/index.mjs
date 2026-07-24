// Liquidation keeper daemon (Liquity v2 / bold).
// Discovers branches from the subgraph, reads each branch's price + trove ICRs
// on-chain, and liquidates under-collateralized troves via batchLiquidateTroves.
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
// Branch MCR (110% default). LST branches may be higher; conservative for a dev keeper.
const MCR = BigInt(process.env.MCR ?? "1100000000000000000");
// anvil fee-negotiation quirk (forge 1.7.1): force legacy gas.
const GAS_PRICE = BigInt(process.env.GAS_PRICE ?? "1000000000");

const tmAbi = parseAbi([
  "function getTroveIdsCount() view returns (uint256)",
  "function getTroveFromTroveIdsArray(uint256) view returns (uint256)",
  "function getCurrentICR(uint256 troveId, uint256 price) view returns (uint256)",
  "function getUnbackedPortionPriceAndRedeemability() view returns (uint256, uint256, bool)",
  "function batchLiquidateTroves(uint256[] troveArray)",
]);

// Two signing modes:
//  - KEEPER_ACCOUNT set  -> "unlocked" mode: the node signs (eth_sendTransaction).
//    Use with anvil (`--unlocked`); avoids a forge/anvil client-side fee-estimation quirk.
//  - otherwise           -> local signer from KEEPER_PK (real deployments).
const UNLOCKED = process.env.KEEPER_ACCOUNT;
const account = UNLOCKED ?? privateKeyToAccount(PK);
const CHAIN_ID = Number(process.env.CHAIN_ID ?? 31337);
const chain = {
  id: CHAIN_ID, name: "local", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
};
const pub = createPublicClient({ chain, transport: http(RPC_URL) });
const wallet = createWalletClient({ account, chain, transport: http(RPC_URL) });

// Discover branch TroveManagers from the subgraph.
async function branches() {
  const q = `{ collaterals{ collIndex addresses{ troveManager } } }`;
  const res = await fetch(SUBGRAPH, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ query: q }),
  }).then((r) => r.json());
  return (res.data?.collaterals ?? []).map((c) => ({ idx: c.collIndex, tm: c.addresses.troveManager }));
}

async function scanBranch(b) {
  const [, price] = await pub.readContract({ address: b.tm, abi: tmAbi, functionName: "getUnbackedPortionPriceAndRedeemability" });
  const count = await pub.readContract({ address: b.tm, abi: tmAbi, functionName: "getTroveIdsCount" });
  const unhealthy = [];
  for (let i = 0n; i < count; i++) {
    const id = await pub.readContract({ address: b.tm, abi: tmAbi, functionName: "getTroveFromTroveIdsArray", args: [i] });
    const icr = await pub.readContract({ address: b.tm, abi: tmAbi, functionName: "getCurrentICR", args: [id, price] }).catch(() => 2n * MCR);
    if (icr < MCR) unhealthy.push(id);
  }
  // The protocol won't let the last trove in a branch be liquidated, so leave one.
  let toLiq = unhealthy;
  if (toLiq.length >= Number(count) && Number(count) > 0) toLiq = toLiq.slice(0, Number(count) - 1);
  if (toLiq.length) {
    console.log(`\n[branch ${b.idx}] price=${price} liquidating ${toLiq.length}/${unhealthy.length} unhealthy trove(s)`);
    const hash = await wallet.writeContract({
      address: b.tm, abi: tmAbi, functionName: "batchLiquidateTroves", args: [toLiq], account,
      // In unlocked mode let the node fill gas/fees; in signer mode force legacy gas (anvil quirk).
      ...(UNLOCKED ? {} : { gas: 5_000_000n, gasPrice: GAS_PRICE }),
    });
    console.log(`  tx ${hash}`);
  }
  return { idx: b.idx, price, count: Number(count), unhealthy: unhealthy.length };
}

async function tick() {
  try {
    const bs = await branches();
    const rows = [];
    for (const b of bs) rows.push(await scanBranch(b));
    const summary = rows.map((r) => `b${r.idx}:${r.count}t/${r.unhealthy}liq`).join(" ");
    process.stdout.write(`\r[${new Date().toISOString()}] ${summary}   `);
  } catch (e) { console.error("tick error:", e.shortMessage ?? e.message); }
}

console.log(`keeper up — RPC ${RPC_URL}, subgraph ${SUBGRAPH}, MCR ${MCR}, poll ${POLL_MS}ms`);
await tick();
setInterval(tick, POLL_MS);
