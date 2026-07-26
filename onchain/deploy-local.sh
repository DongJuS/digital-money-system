#!/usr/bin/env bash
# Deploy the institution-issued stablecoin + FX oracle to the local anvil,
# then issue demo balances to several "people". Uses --unlocked (anvil signs)
# to avoid a forge/anvil client-signing fee-estimation quirk.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

RPC="${RPC:-http://localhost:8545}"
ISSUER="${ISSUER:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"   # anvil acct0 = institution
cd "$(dirname "$0")"

say(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

say "build"; forge build >/dev/null

say "deploy StableToken (Digital Won / dKRW)"
TOKEN=$(forge create src/StableToken.sol:StableToken --rpc-url "$RPC" --from "$ISSUER" --unlocked --broadcast --json \
  --constructor-args "DigitalWon" "dKRW" "$ISSUER" | grep '"deployedTo"' | grep -oE '0x[0-9a-fA-F]{40}')
echo "  StableToken = $TOKEN"

say "deploy FxOracle (USD/KRW)"
ORACLE=$(forge create src/FxOracle.sol:FxOracle --rpc-url "$RPC" --from "$ISSUER" --unlocked --broadcast --json \
  --constructor-args "USD/KRW" "$ISSUER" | grep '"deployedTo"' | grep -oE '0x[0-9a-fA-F]{40}')
echo "  FxOracle    = $ORACLE"

say "issue coins to 5 people (anvil accounts 1..5)"
PEOPLE=(0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC \
        0x90F79bf6EB2c4f870365E785982E1f101E93b906 \
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 \
        0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc)
AMTS=(1000000000000000000000 2500000000000000000000 500000000000000000000 750000000000000000000 3200000000000000000000)
PJOIN=$(IFS=,; echo "${PEOPLE[*]}")
AJOIN=$(IFS=,; echo "${AMTS[*]}")
cast send "$TOKEN" "issueBatch(address[],uint256[])" "[$PJOIN]" "[$AJOIN]" \
  --from "$ISSUER" --unlocked --rpc-url "$RPC" >/dev/null
echo "  issued to ${#PEOPLE[@]} holders"

# persist addresses for the relayer / demo
cat > deployment.local.json <<EOF
{
  "rpc": "$RPC",
  "issuer": "$ISSUER",
  "stableToken": "$TOKEN",
  "fxOracle": "$ORACLE",
  "people": ["${PEOPLE[0]}","${PEOPLE[1]}","${PEOPLE[2]}","${PEOPLE[3]}","${PEOPLE[4]}"]
}
EOF
echo "wrote deployment.local.json"
