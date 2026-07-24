# RUNBOOK — 로컬 풀스택 스테이블코인 (실측 동작 기준)

이 문서는 **실제로 검증된** 브링업 절차다. 토폴로지는 계획(`docs/02`) 대비 한 곳을 조정했다:
**인덱서(graph-node)를 anvil과 같은 Mac에 co-locate** — Windows 박스로 SSH 구동이 불가했고(키/암호 필요),
인덱싱은 RPC 왕복이 잦아 체인과 동일 호스트에 두는 편이 기술적으로 우수하기 때문. Windows(Tailscale)
박스는 **익스플로러 + 모니터링 + 키퍼**(상시성·무거움, dev 핫패스 밖)를 담당한다.

## Tailnet 토폴로지 (Tailscale)
| 호스트 | tailnet IP | 역할 |
|---|---|---|
| `mac-ddongui` (this Mac, M5 Pro 48GB) | **100.123.177.95** | anvil + 컨트랙트 + graph-node/서브그래프 + 프론트(dev) |
| `ddj127` (Windows, 32GB+/GPU) | 100.95.248.14 | Blockscout 익스플로러 + Prometheus/Grafana + 키퍼 |
| `alpha-oci-hub` (Linux, OCI) | 100.106.57.42 | (예비) 상시 서비스 오프로드 후보 |

- anvil은 `--host 0.0.0.0`로 바인딩되어 **100.123.177.95:8545** 로 tailnet 어디서든 도달 가능(검증됨).

## 검증된 환경 (Mac)
- Foundry 1.7.1 · Node 20.20.2(nvm) · pnpm 8.15.8 · colima(도커, arm64 VM 4cpu/8GB)
- 레포: `bold/` (liquity/bold, 서브모듈 포함)

## 브링업 순서 (Mac) — 전부 실측 통과
```bash
# 0) 셸 환경
export PATH="$HOME/.foundry/bin:/opt/homebrew/bin:$PATH"
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm use 20

# 1) 로컬 체인 (tailnet 노출, chainid 고정)
anvil --host 0.0.0.0 --chain-id 31337        # :8545

# 2) 컨트랙트 배포 (3담보 브랜치 + PriceFeed + 데모 trove 8개)
cd bold && pnpm install --filter ./contracts
cd contracts && printf 'y\n' | ./deploy local --open-demo-troves
#   → deployment-manifest.json / deployment-context-latest.json 생성

# 3) 인덱서 스택 (graph-node + ipfs + postgres)
cd ../ && docker context use colima
#   networks.json "local" 의 BoldToken/Governance 를 배포 주소로 갱신 (스크립트로 자동화 예정)
cd subgraph && pnpm install --filter . && docker-compose up -d
#   graph-node 가 host.docker.internal:8545(=anvil) 에 'mainnet' 네트워크로 연결

# 4) 서브그래프 빌드/배포
pnpm codegen                                  # generated/ 생성 (필수, 최초 1회)
printf 'y\n' | ./deploy-subgraph local --version v1 --create
```

## 검증 쿼리 (실측 결과)
```bash
curl -s -X POST http://localhost:8000/subgraphs/name/liquity2/liquity2 \
  -H 'content-type: application/json' \
  --data '{"query":"{ _meta{block{number}} collaterals{collIndex} troves(first:1000){id status} }"}'
# => collaterals: 3, troves: 24 (active), _meta.block: 191
```
```bash
# 온체인 크로스체크
cast call 0x720d6cddec51199cac4d2b146674df61f75a669c 'totalSupply()(uint256)' --rpc-url http://localhost:8545
# => 120,781 BOLD  (8 데모 trove의 차입 합)
```

## 알려진 이슈 / 주의
- **cast send 가스**: anvil이 EIP-1559 수수료를 부풀려 "insufficient funds"가 나면 `--legacy --gas-price 1000000000` 사용.
- **codegen 필수**: `deploy-subgraph`는 codegen을 자동 실행하지 않음 → 최초 `pnpm codegen` 먼저.
- **docker compose vs docker-compose**: colima엔 `docker-compose`(하이픈) 사용. `~/.docker/cli-plugins`에 심링크로 플러그인도 연결해둠.
- **anvil 재시작 시**: 상태 소실 → 재배포 → networks.json 갱신 → `./start-graph --reset` → `deploy-subgraph` 순서로 재현.
- **라이브 청산 미완(M3)**: 로컬 배포가 `USE_TESTNET_PRICEFEEDS=no`라 실제 PriceFeed 래퍼(+mock aggregator) 사용.
  가격 하락은 래퍼 `setPrice`가 아니라 **하위 mock aggregator의 `updateAnswer`** 로 해야 함(→ M3 잔여 작업).

## 다음 (Windows / Tailscale 박스)
`infra/` 의 compose들을 Windows에서 실행, 모두 `100.123.177.95`(Mac anvil/graph) 를 가리킴:
- `infra/monitoring/` — Prometheus(graph-node `:8040` 메트릭 스크레이프) + Grafana
- `infra/blockscout/` — 익스플로러 (anvil RPC = tailnet Mac)
- `keeper/` — TS 청산 키퍼 데몬
