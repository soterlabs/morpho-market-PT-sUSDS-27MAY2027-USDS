#!/usr/bin/env bash
# Deploy the PT-sUSDS/USDS market: one on-chain action per step, each self-checked in-script.
# forge's dry-run mispredicts the Pendle factory's CREATE address, so we read each step's
# real deployed address from its mined event and thread it into the next step.
#   LOCAL_FORK=1 RPC=http://127.0.0.1:18545 DEPLOYER=<impersonated-address> ./run.sh
set -euo pipefail
# Only a loopback Anvil fork is enabled while production receipt/restart work is pending.
if [[ "${LOCAL_FORK:-0}" != "1" ]]; then
    echo "Production deployment remains disabled. Set LOCAL_FORK=1 for a local Anvil fork rehearsal." >&2
    exit 1
fi
: "${RPC:?}" "${DEPLOYER:?}"
python3 - "$RPC" <<'PYFORK'
import json, sys, urllib.parse, urllib.request
url = urllib.parse.urlparse(sys.argv[1])
if url.scheme != "http" or url.hostname not in ("127.0.0.1", "localhost", "::1"):
    raise SystemExit("Fork mode requires a loopback HTTP RPC")
def rpc(method):
    request = urllib.request.Request(sys.argv[1], data=json.dumps({"jsonrpc":"2.0", "id":1, "method":method, "params":[]}).encode(), headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(request))["result"]
info = rpc("anvil_nodeInfo")
if not info.get("forkConfig", {}).get("forkBlockNumber"):
    raise SystemExit("Anvil must be forked from Ethereum")
if rpc("eth_chainId") != "0x1":
    raise SystemExit("Expected Ethereum chain ID 1")
print("Local fork source block:", info["forkConfig"]["forkBlockNumber"])
PYFORK
export FOUNDRY_BROADCAST="${FORK_ARTIFACT_DIR:-$(mktemp -d /tmp/pendle-may2027-broadcast.XXXXXX)}"
mkdir -p "$FOUNDRY_BROADCAST"
echo "Local-only broadcast receipts: $FOUNDRY_BROADCAST"
# Interest accrual can cost more in a later mined block than in same-block simulation.
# Gas limit headroom is not gas spent: unused gas is not charged.
FORGE=(forge script --rpc-url "$RPC" --sender "$DEPLOYER" --unlocked --broadcast --slow --gas-estimate-multiplier 300)
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
        "$FOUNDRY_BROADCAST/$1/$CHAIN/run-latest.json" "$2"
}

"${FORGE[@]}" script/1_DeployPtOracle.s.sol:DeployPtOracle
PT_ORACLE=$(created_by 1_DeployPtOracle.s.sol "$(config_address SPARK_LINEAR_DISCOUNT_ORACLE_FACTORY)") # bare assign so set -e fires on failure
export PT_ORACLE

"${FORGE[@]}" script/2_DeployMorphoOracle.s.sol:DeployMorphoOracle
MORPHO_ORACLE=$(created_by 2_DeployMorphoOracle.s.sol "$(config_address MORPHO_CHAINLINK_ORACLE_V2_FACTORY)")
export MORPHO_ORACLE

"${FORGE[@]}" script/3_CreateMarket.s.sol:CreateMarket
"${FORGE[@]}" script/4_SeedMarket.s.sol:SeedMarket

echo "PT_ORACLE=$PT_ORACLE  MORPHO_ORACLE=$MORPHO_ORACLE"
