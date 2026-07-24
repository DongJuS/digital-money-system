#!/usr/bin/env bash
# One-command bring-up of the full local stablecoin stack on the Mac (co-located).
# Reproduces the verified M2–M6 pipeline: anvil -> deploy -> Multicall3 -> subgraph -> frontend -> monitoring.
# Prereq (M0/M1): Foundry, Node 20 (nvm), pnpm 8.15.8, colima/docker, and the bold/ clone present.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOLD="$ROOT/bold"
RPC="http://localhost:8545"
FROM="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"   # anvil acct0 (dev only)
MC3="0xca11bde05977b3631167028862be2a173976ca11"
SUBGRAPH_URL="http://localhost:8000/subgraphs/name/liquity2/liquity2"

export PATH="$HOME/.foundry/bin:/opt/homebrew/bin:$PATH"
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use 20 >/dev/null

say(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

say "1/7 anvil (31337, LAN-exposed)"
if ! cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
  nohup anvil --host 0.0.0.0 --chain-id 31337 > /tmp/anvil.log 2>&1 &
  for i in $(seq 1 20); do cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break; sleep 1; done
fi
echo "anvil block $(cast block-number --rpc-url "$RPC")"

say "2/7 deploy contracts (testnet pricefeeds + demo troves)"
cd "$BOLD"; pnpm install --filter ./contracts >/dev/null
cd "$BOLD/contracts"; export USE_TESTNET_PRICEFEEDS=true
printf 'y\n' | ./deploy local --open-demo-troves >/dev/null
BOLD_ADDR=$(node -e "console.log(require('./deployment-manifest.json').boldToken)")
GOV_ADDR=$(node -e "const m=require('./deployment-manifest.json');console.log(m.governance.governance||m.governance)")
echo "BOLD=$BOLD_ADDR"

say "3/7 inject Multicall3 at $MC3"
TMP="$(mktemp -d)"; mkdir -p "$TMP/src"; cp "$ROOT/scripts/Multicall3.sol" "$TMP/src/"
printf '[profile.default]\nsrc="src"\nout="out"\n' > "$TMP/foundry.toml"
( cd "$TMP" && forge build >/dev/null )
CODE=$(node -e "console.log(require('$TMP/out/Multicall3.sol/Multicall3.json').deployedBytecode.object)")
cast rpc anvil_setCode "$MC3" "$CODE" --rpc-url "$RPC" >/dev/null
echo "multicall3 getBlockNumber() = $(cast call "$MC3" 'getBlockNumber()(uint256)' --rpc-url "$RPC")"

say "4/7 subgraph: point networks.json at deploy, reset graph-node, deploy subgraph"
cd "$BOLD/subgraph"
node -e "const fs=require('fs');const p='networks.json';const j=JSON.parse(fs.readFileSync(p));j.local.BoldToken.address='$BOLD_ADDR';j.local.Governance.address='$GOV_ADDR';fs.writeFileSync(p,JSON.stringify(j,null,2))"
pnpm install --filter . >/dev/null
docker-compose down -v >/dev/null 2>&1 || true
docker-compose up -d >/dev/null
for i in $(seq 1 30); do docker logs subgraph-graph-node-1 2>&1 | grep -q "Downloading latest blocks" && break; sleep 2; done
pnpm codegen >/dev/null
printf 'y\n' | ./deploy-subgraph local --version v1 --create >/dev/null
echo "subgraph deployed"

say "5/7 frontend .env.local from manifest"
cd "$BOLD/contracts"; pnpm tsx utils/deployment-manifest-to-app-env.ts deployment-manifest.json > /tmp/app-contracts.env
cd "$BOLD"
node -e '
const fs=require("fs");
const parse=s=>s.split(/\r?\n/).filter(l=>l&&!l.startsWith("#")&&l.includes("=")).reduce((m,l)=>{const i=l.indexOf("=");m[l.slice(0,i)]=l.slice(i+1);return m;},{});
const base=parse(fs.readFileSync("frontend/app/.env","utf8"));
const c=parse(fs.readFileSync("/tmp/app-contracts.env","utf8"));
const o={NEXT_PUBLIC_CHAIN_ID:"31337",NEXT_PUBLIC_CHAIN_NAME:"Anvil Local",NEXT_PUBLIC_CHAIN_RPC_URL:"http://localhost:8545",NEXT_PUBLIC_CHAIN_BLOCK_EXPLORER:"Local|http://localhost:4000",NEXT_PUBLIC_SUBGRAPH_URL:"'"$SUBGRAPH_URL"'",NEXT_PUBLIC_SAFE_API_URL:"",NEXT_PUBLIC_DEMO_MODE:"false"};
fs.writeFileSync("frontend/app/.env.local",Object.entries({...base,...c,...o}).map(([k,v])=>k+"="+v).join("\n")+"\n");
'
echo ".env.local written"

say "6/7 frontend dev server (:3000)"
cd "$BOLD/frontend/app"; pnpm build-deps >/dev/null 2>&1 || true
nohup pnpm dev > /tmp/frontend.log 2>&1 &
for i in $(seq 1 40); do curl -sf -o /dev/null "http://localhost:3000" && break; sleep 3; done
echo "frontend: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000)"

say "7/7 monitoring (Prometheus :9090 + Grafana :3001)"
cd "$ROOT/infra/monitoring" && docker-compose up -d >/dev/null

cat <<EOF

Stack up.
  RPC/anvil   $RPC   (chainId 31337)
  subgraph    $SUBGRAPH_URL
  frontend    http://localhost:3000
  grafana     http://localhost:3001  (admin/admin)
  prometheus  http://localhost:9090
  keeper      cd keeper && RPC_URL=$RPC SUBGRAPH=$SUBGRAPH_URL KEEPER_ACCOUNT=$FROM node index.mjs
EOF
