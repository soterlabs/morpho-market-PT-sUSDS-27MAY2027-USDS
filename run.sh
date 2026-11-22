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

# Read shared factory addresses from Config.sol so the runner cannot drift.
config_address() {
    python3 - "$1" <<'PYCONFIG'
import pathlib, re, sys
source = (pathlib.Path("script") / "Config.sol").read_text()
values = re.findall(r"address constant " + re.escape(sys.argv[1]) + r"\s*=\s*(0x[0-9a-fA-F]{40});", source)
if len(values) != 1:
    raise SystemExit("Expected exactly one configured address for " + sys.argv[1])
print(values[0])
PYCONFIG
}

# address the given factory created in <script>'s mined tx (trailing 20 bytes of its event data)
created_by() {
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); \
print(next('0x'+l['data'][-40:] for r in d['receipts'] for l in r['logs'] if l['address'].lower()==sys.argv[2].lower()))" \
        "broadcast/$1/$CHAIN/run-latest.json" "$2"
}

"${FORGE[@]}" script/1_DeployPtOracle.s.sol:DeployPtOracle
PT_ORACLE=$(created_by 1_DeployPtOracle.s.sol "$(config_address SPARK_LINEAR_DISCOUNT_ORACLE_FACTORY)") # bare assign so set -e fires on failure
export PT_ORACLE

"${FORGE[@]}" script/2_DeployMorphoOracle.s.sol:DeployMorphoOracle
MORPHO_ORACLE=$(created_by 2_DeployMorphoOracle.s.sol "$(config_address MORPHO_CHAINLINK_ORACLE_V2_FACTORY)")
export MORPHO_ORACLE

"${FORGE[@]}" script/3_CreateMarket.s.sol:CreateMarket
echo "PT_ORACLE=$PT_ORACLE  MORPHO_ORACLE=$MORPHO_ORACLE"
