#!/usr/bin/env bash
# Deploy the PT-sUSDS/USDS market: one on-chain action per step, each self-checked in-script.
# forge's dry-run mispredicts the Pendle factory's CREATE address, so we read each step's
# real deployed address from its mined event and thread it into the next step.
#   LOCAL_FORK=1 RPC=http://127.0.0.1:18545 DEPLOYER=<impersonated-address> ./run.sh
set -euo pipefail
: "${RPC:?}" "${DEPLOYER:?}"
if [[ "${LOCAL_FORK:-0}" == "1" ]]; then
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
    export DEPLOYMENT_DIR="${FORK_ARTIFACT_DIR:-$(mktemp -d /tmp/pendle-may2027-broadcast.XXXXXX)}"
    if [[ -n "${ACCOUNT:-}" ]]; then
        : "${PASSWORD_FILE:?}"
        signer=$(cast wallet address --account "$ACCOUNT" --password-file "$PASSWORD_FILE")
        [[ "${signer,,}" == "${DEPLOYER,,}" ]] || exit 1
        FORGE=(forge script --rpc-url "$RPC" --sender "$DEPLOYER" --account "$ACCOUNT" --password-file "$PASSWORD_FILE")
    else
        FORGE=(forge script --rpc-url "$RPC" --sender "$DEPLOYER" --unlocked)
    fi
else
    : "${MAINNET:?Set MAINNET=1 for production}" "${ACCOUNT:?}" "${PASSWORD_FILE:?}"
    [[ "$MAINNET" == "1" ]] || exit 1
    signer=$(cast wallet address --account "$ACCOUNT" --password-file "$PASSWORD_FILE")
    [[ "${signer,,}" == "${DEPLOYER,,}" ]] || { echo "Keystore/deployer mismatch" >&2; exit 1; }
    export DEPLOYMENT_DIR="deployments/mainnet"
    FORGE=(forge script --rpc-url "$RPC" --sender "$DEPLOYER" --account "$ACCOUNT" --password-file "$PASSWORD_FILE")
fi
export FOUNDRY_BROADCAST="$DEPLOYMENT_DIR/broadcast"
mkdir -p "$FOUNDRY_BROADCAST"
# Later mined blocks can execute additional interest-accrual work.
FORGE+=(--broadcast --slow --gas-estimate-multiplier 300)
STATE=(python3 script/deployment_state.py)
"${STATE[@]}" preflight

run_step() {
    local file="$1" contract="$2" stage="$3"
    local receipt="$FOUNDRY_BROADCAST/$file/1/run-latest.json"
    local intent="$DEPLOYMENT_DIR/$file.intent"
    if [[ -f "$receipt" ]]; then
        "${STATE[@]}" recover "$file"
        "${STATE[@]}" verify "$stage"
        echo "Reused verified completed step: $file"
        return
    fi
    if [[ -f "$intent" ]]; then
        echo "Unresolved prior attempt for $file: reconcile its nonce and receipts before retrying." >&2
        exit 1
    fi
    cast nonce "$DEPLOYER" --rpc-url "$RPC" > "$intent"
    if ! "${FORGE[@]}" "script/$file:$contract"; then
        # Record any mined state before stopping. Never automatically redeploy.
        if [[ -f "$receipt" ]]; then "${STATE[@]}" recover "$file" || true; fi
        echo "Step stopped; mined transactions cannot be undone. Reconcile saved receipts." >&2
        exit 1
    fi
    if [[ -f "$receipt" ]]; then "${STATE[@]}" recover "$file"; fi
    "${STATE[@]}" verify "$stage"
}
run_step 1_DeployPtOracle.s.sol DeployPtOracle 1
PT_ORACLE=$("${STATE[@]}" get ptOracle)
export PT_ORACLE
run_step 2_DeployMorphoOracle.s.sol DeployMorphoOracle 2
MORPHO_ORACLE=$("${STATE[@]}" get morphoOracle)
export MORPHO_ORACLE
run_step 3_CreateMarket.s.sol CreateMarket 3
run_step 4_SeedMarket.s.sol SeedMarket 4
echo "PT_ORACLE=$PT_ORACLE MORPHO_ORACLE=$MORPHO_ORACLE"
echo "Manifest: $DEPLOYMENT_DIR/USDS-PT-sUSDS-27MAY2027.json"
