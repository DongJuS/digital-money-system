#!/usr/bin/env bash
# Demo: show that the institution issued coins to people, the USD/KRW rate is live
# from the oracle, and people can send coins to each other. Read-only + one transfer.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"

RPC=$(node -e "console.log(require('./deployment.local.json').rpc)")
TOKEN=$(node -e "console.log(require('./deployment.local.json').stableToken)")
ORACLE=$(node -e "console.log(require('./deployment.local.json').fxOracle)")
PEOPLE=()
while IFS= read -r line; do PEOPLE+=("$line"); done < <(node -e "require('./deployment.local.json').people.forEach(p=>console.log(p))")

SYM=$(cast call "$TOKEN" 'symbol()(string)' --rpc-url "$RPC" | tr -d '"')
RATE=$(cast call "$ORACLE" 'rate()(uint256)' --rpc-url "$RPC" | awk '{print $1}')      # USD/KRW * 1e8
PAIR=$(cast call "$ORACLE" 'pair()(string)' --rpc-url "$RPC" | tr -d '"')

# USD value of a KRW(18-dec) balance: (bal/1e18) / (rate/1e8)
usd() { python3 -c "print(f'{(int('$1')/1e18)/(int('$RATE')/1e8):,.4f}')"; }
won() { python3 -c "print(f'{int('$1')/1e18:,.0f}')"; }

echo "기관 발행 디지털 통화: $SYM   |   환율($PAIR): $(python3 -c "print(f'{int('$RATE')/1e8:,.2f}')") (API 실시간)"
echo "-------------------------------------------------------------"
printf "%-9s %-46s %18s %12s\n" "사람" "주소" "보유($SYM)" "≈ USD"
i=1
for p in "${PEOPLE[@]}"; do
  b=$(cast call "$TOKEN" 'balanceOf(address)(uint256)' "$p" --rpc-url "$RPC" | awk '{print $1}')
  printf "person%-3d %-46s %18s %12s\n" "$i" "$p" "$(won "$b")" "\$$(usd "$b")"
  i=$((i+1))
done

echo "-------------------------------------------------------------"
echo "▶ person1 → person3 로 200 $SYM 송금 (사람끼리 전송)"
cast send "$TOKEN" 'transfer(address,uint256)' "${PEOPLE[2]}" 200000000000000000000 \
  --from "${PEOPLE[0]}" --unlocked --rpc-url "$RPC" >/dev/null
echo "  완료. 갱신된 잔액:"
for idx in 0 2; do
  b=$(cast call "$TOKEN" 'balanceOf(address)(uint256)' "${PEOPLE[$idx]}" --rpc-url "$RPC" | awk '{print $1}')
  printf "  person%d: %s %s  (≈ \$%s)\n" "$((idx+1))" "$(won "$b")" "$SYM" "$(usd "$b")"
done
echo
echo "총 발행량: $(won "$(cast call "$TOKEN" 'totalSupply()(uint256)' --rpc-url "$RPC" | awk '{print $1}')") $SYM"
