// FX relayer — fetches the USD/KRW exchange rate from a public API and pushes it
// on-chain to the FxOracle (like an institution publishing a reference rate).
// No funds held. Uses anvil "unlocked" signing to avoid a forge/anvil fee-estimation quirk.
//
// Run (once):     node index.mjs --once
// Run (loop):     INTERVAL_MS=60000 node index.mjs
// Deps:           npm i viem

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { createPublicClient, createWalletClient, http, parseAbi } from "viem";

const __dir = dirname(fileURLToPath(import.meta.url));
const dep = JSON.parse(readFileSync(resolve(__dir, "../onchain/deployment.local.json"), "utf8"));

const RPC_URL = process.env.RPC_URL ?? dep.rpc ?? "http://localhost:8545";
const ORACLE = process.env.FX_ORACLE ?? dep.fxOracle;
const UPDATER = process.env.UPDATER ?? dep.issuer; // anvil unlocked account
const PAIR = process.env.PAIR ?? "USD/KRW";        // BASE/QUOTE
const FX_API = process.env.FX_API ?? "https://open.er-api.com/v6/latest/USD";
const INTERVAL_MS = Number(process.env.INTERVAL_MS ?? 60000);
const ONCE = process.argv.includes("--once");
const CHAIN_ID = Number(process.env.CHAIN_ID ?? 31337);

const abi = parseAbi([
  "function setRate(uint256 rate)",
  "function latestRate() view returns (uint256, uint256)",
  "function pair() view returns (string)",
]);
const chain = { id: CHAIN_ID, name: "local", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [RPC_URL] } } };
const pub = createPublicClient({ chain, transport: http(RPC_URL) });
const wallet = createWalletClient({ account: UPDATER, chain, transport: http(RPC_URL) });

// FxOracle stores the rate scaled by 1e8.
const SCALE = 100000000n;

async function fetchRate() {
  const [base, quote] = PAIR.split("/");
  const res = await fetch(FX_API).then((r) => r.json());
  const rate = res?.rates?.[quote];
  if (!rate || !Number.isFinite(rate)) throw new Error(`no ${quote} in FX response`);
  // scale to 1e8 as a BigInt without float drift
  const scaled = BigInt(Math.round(rate * 1e8));
  return { human: rate, scaled, base, quote, asof: res?.time_last_update_utc ?? "" };
}

async function push() {
  const { human, scaled, base, quote, asof } = await fetchRate();
  const hash = await wallet.writeContract({ address: ORACLE, abi, functionName: "setRate", args: [scaled], account: UPDATER });
  const [onchain] = await pub.readContract({ address: ORACLE, abi, functionName: "latestRate" });
  console.log(`[${new Date().toISOString()}] 1 ${base} = ${human} ${quote}  -> on-chain rate ${onchain} (1e8)  tx ${hash}  (api asof ${asof})`);
}

console.log(`fx-relayer: ${PAIR} from ${FX_API} -> FxOracle ${ORACLE} @ ${RPC_URL}`);
await push();
if (!ONCE) setInterval(() => push().catch((e) => console.error("push error:", e.shortMessage ?? e.message)), INTERVAL_MS);
