#!/usr/bin/env bash
# Deploy the PT-sUSDS/USDS market: one on-chain action per step, each self-checked in-script.
# forge's dry-run mispredicts the Pendle factory's CREATE address, so we read each step's
# real deployed address from its mined event and thread it into the next step.
#   RPC=<url> ACCOUNT=<cast keystore name> ./run.sh
set -euo pipefail
echo "Deployment runner is disabled pending completion and review of the PRD workflow." >&2
exit 1
# Historical runner retained below as implementation reference.
: "${RPC:?}" "${ACCOUNT:?}"
FORGE=(forge script --rpc-url "$RPC" --account "$ACCOUNT" --broadcast)
CHAIN=$(cast chain-id --rpc-url "$RPC")

# address the given factory created in <script>'s mined tx (trailing 20 bytes of its event data)
created_by() {
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); \
print(next('0x'+l['data'][-40:] for r in d['receipts'] for l in r['logs'] if l['address'].lower()==sys.argv[2].lower()))" \
        "broadcast/$1/$CHAIN/run-latest.json" "$2"
}

"${FORGE[@]}" script/1_DeployPtOracle.s.sol:DeployPtOracle
PT_ORACLE=$(created_by 1_DeployPtOracle.s.sol 0x34C91651A070664279866E5f3d6B4d5F65cbbFFb) # bare assign so set -e fires on failure
export PT_ORACLE

"${FORGE[@]}" script/2_DeployMorphoOracle.s.sol:DeployMorphoOracle
MORPHO_ORACLE=$(created_by 2_DeployMorphoOracle.s.sol 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766)
export MORPHO_ORACLE

"${FORGE[@]}" script/3_CreateMarket.s.sol:CreateMarket
echo "PT_ORACLE=$PT_ORACLE  MORPHO_ORACLE=$MORPHO_ORACLE"
