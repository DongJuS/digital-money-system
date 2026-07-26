// Max-load test for the institution stablecoin (StableToken) on a dedicated anvil.
// Deploys the token, funds sender accounts, pre-signs N transfers, blasts them via
// batched eth_sendRawTransaction, and measures submission + inclusion throughput (TPS).
//
// Run:  N=5000 SENDERS=19 node index.mjs
// Deps: viem

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  createPublicClient, createWalletClient, http, encodeFunctionData, parseAbi, getAddress,
} from "viem";
import { mnemonicToAccount } from "viem/accounts";

const __dir = dirname(fileURLToPath(import.meta.url));
const art = JSON.parse(readFileSync(resolve(__dir, "../onchain/out/StableToken.sol/StableToken.json"), "utf8"));
const BYTECODE = art.bytecode.object;

const RPC = process.env.LOAD_RPC ?? "http://localhost:8546";
const MNEMONIC = "test test test test test test test test test test test junk";
const CHAIN_ID = Number(process.env.CHAIN_ID ?? 31337);
const N = Number(process.env.N ?? 5000);            // total transfers to fire
const SENDERS = Number(process.env.SENDERS ?? 19);  // sender accounts (excl. issuer)
const CHUNK = Number(process.env.CHUNK ?? 1000);    // raw txs per JSON-RPC batch
const GAS_PRICE = BigInt(process.env.GAS_PRICE ?? "1000000000");
const GAS = 60000n;

const abi = parseAbi([
  "function issueBatch(address[] to, uint256[] value)",
  "function transfer(address to, uint256 value) returns (bool)",
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
]);

const chain = { id: CHAIN_ID, name: "load", nativeCurrency: { name: "E", symbol: "E", decimals: 18 }, rpcUrls: { default: { http: [RPC] } } };
const pub = createPublicClient({ chain, transport: http(RPC) });

const issuer = mnemonicToAccount(MNEMONIC, { addressIndex: 0 });
const senders = Array.from({ length: SENDERS }, (_, i) => mnemonicToAccount(MNEMONIC, { addressIndex: i + 1 }));
const recipients = Array.from({ length: 64 }, (_, i) => mnemonicToAccount(MNEMONIC, { addressIndex: 100 + i }).address);

const wIssuer = createWalletClient({ account: issuer, chain, transport: http(RPC) });
const ms = (a, b) => Number(b - a) / 1e6;

async function rpcBatch(reqs) {
  const res = await fetch(RPC, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(reqs) });
  return res.json();
}

async function main() {
  console.log(`load test: N=${N} transfers, ${SENDERS} senders, chunk ${CHUNK}, chain ${RPC}`);

  // 1) deploy
  let t = process.hrtime.bigint();
  const hash = await wIssuer.deployContract({ abi: art.abi, bytecode: BYTECODE, args: ["LoadWon", "LW", issuer.address] });
  const rc = await pub.waitForTransactionReceipt({ hash });
  const token = rc.contractAddress;
  console.log(`deployed StableToken @ ${token} (${ms(t, process.hrtime.bigint()).toFixed(0)} ms)`);

  // 2) fund senders (one issueBatch)
  t = process.hrtime.bigint();
  const big = 10n ** 30n;
  const h2 = await wIssuer.writeContract({ address: token, abi, functionName: "issueBatch",
    args: [senders.map((s) => s.address), senders.map(() => big)] });
  await pub.waitForTransactionReceipt({ hash: h2 });
  console.log(`funded ${SENDERS} senders (${ms(t, process.hrtime.bigint()).toFixed(0)} ms)`);

  // 3) pre-sign N transfers (round-robin senders, explicit nonce/gas/gasPrice)
  t = process.hrtime.bigint();
  // start from each sender's current on-chain nonce so the script is re-runnable
  const nonces = await Promise.all(senders.map((s) => pub.getTransactionCount({ address: s.address, blockTag: "pending" })));
  const raws = new Array(N);
  for (let i = 0; i < N; i++) {
    const si = i % SENDERS;
    const s = senders[si];
    const to = recipients[i % recipients.length];
    const data = encodeFunctionData({ abi, functionName: "transfer", args: [to, 1000000000000n] });
    raws[i] = await s.signTransaction({ to: token, data, nonce: nonces[si]++, gas: GAS, gasPrice: GAS_PRICE, value: 0n, chainId: CHAIN_ID, type: "legacy" });
  }
  console.log(`pre-signed ${N} txs (${ms(t, process.hrtime.bigint()).toFixed(0)} ms, ${(N / (ms(t, process.hrtime.bigint()) / 1000)).toFixed(0)} sign/s)`);

  // 4) blast via batched eth_sendRawTransaction
  const startBlock = Number(await pub.getBlockNumber());
  const tSubmit = process.hrtime.bigint();
  let accepted = 0, rejected = 0;
  for (let off = 0; off < N; off += CHUNK) {
    const slice = raws.slice(off, off + CHUNK);
    const reqs = slice.map((raw, j) => ({ jsonrpc: "2.0", id: off + j, method: "eth_sendRawTransaction", params: [raw] }));
    const out = await rpcBatch(reqs);
    for (const r of out) (r.error ? rejected++ : accepted++);
  }
  const tSubmitted = process.hrtime.bigint();
  const subSec = ms(tSubmit, tSubmitted) / 1000;
  console.log(`submitted: accepted=${accepted} rejected=${rejected} in ${subSec.toFixed(2)}s -> ${(accepted / subSec).toFixed(0)} tx/s (submission)`);

  // 5) wait for inclusion (all sender nonces mined)
  const target = nonces.reduce((a, b) => a + b, 0);
  let mined = 0;
  while (mined < target) {
    const counts = await Promise.all(senders.map((s) => pub.getTransactionCount({ address: s.address, blockTag: "latest" })));
    mined = counts.reduce((a, b) => a + b, 0);
    if (mined < target) await new Promise((r) => setTimeout(r, 50));
  }
  const tMined = process.hrtime.bigint();
  const e2e = ms(tSubmit, tMined) / 1000;
  const endBlock = Number(await pub.getBlockNumber());

  // 6) gas/block stats over the mined range (scan blocks that carried our txs)
  let totalGas = 0n, txCount = 0, maxBlockTx = 0, blocksWithTx = 0;
  for (let b = startBlock; b <= endBlock; b++) {
    const blk = await pub.getBlock({ blockNumber: BigInt(b), includeTransactions: false });
    const n = blk.transactions.length;
    if (n > 0) { totalGas += blk.gasUsed; txCount += n; blocksWithTx++; if (n > maxBlockTx) maxBlockTx = n; }
  }
  console.log(`included ${mined - (target - N)} of our txs; ${txCount} txs in ${blocksWithTx} blocks (max ${maxBlockTx} tx/block)`);
  console.log(`END-TO-END: ${e2e.toFixed(2)}s -> ${(mined / e2e).toFixed(0)} TPS (submit+mine)`);
  console.log(`gas: ${(totalGas / BigInt(Math.max(txCount, 1)))} avg/tx, ${totalGas} total`);

  // 7) correctness spot-check
  const bal = await pub.readContract({ address: token, abi, functionName: "balanceOf", args: [recipients[0]] });
  console.log(`correctness: recipient[0] received ${bal} wei (expected ${1000000000000n * BigInt(Math.ceil(N / recipients.length))} approx)`);
}

main().catch((e) => { console.error(e); process.exit(1); });
