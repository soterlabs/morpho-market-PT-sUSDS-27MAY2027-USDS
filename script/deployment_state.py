#!/usr/bin/env python3
"""Read-only deployment preflight, receipt recovery and independent verification.

Requires Python 3 and Foundry cast. RPC credentials are read from RPC, never saved.
"""
import decimal
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'script/Config.sol'
TEXT = CONFIG.read_text()
ADDRESSES = dict(re.findall(r'address constant (\w+) = (0x[0-9a-fA-F]{40});', TEXT))
NUMBERS = {k: int(decimal.Decimal(v.replace('_', ''))) for k, v in re.findall(r'uint256 constant (\w+) = ([0-9_e.]+);', TEXT)}
RPC = os.environ['RPC']
DEPLOYER = os.environ['DEPLOYER'].lower()
DIRECTORY = Path(os.environ['DEPLOYMENT_DIR'])
MANIFEST = DIRECTORY / 'USDS-PT-sUSDS-27MAY2027.json'
BROADCAST = Path(os.environ['FOUNDRY_BROADCAST'])
STEPS = ['1_DeployPtOracle.s.sol', '2_DeployMorphoOracle.s.sol', '3_CreateMarket.s.sol', '4_SeedMarket.s.sol']


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def rpc(method, params):
    data = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}).encode()
    req = urllib.request.Request(RPC, data=data, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            answer = json.load(response)
    except Exception:
        raise RuntimeError('RPC transport failed; endpoint omitted') from None
    require('error' not in answer, 'RPC call failed: ' + method)
    return answer['result']


def cast(*args):
    return subprocess.check_output(['cast', *args], text=True).strip()


def word(value):
    return (hex(value)[2:] if isinstance(value, int) else value.removeprefix('0x')).zfill(64)


def words(value):
    return [int(value[i:i + 64], 16) for i in range(2, len(value), 64)]


def call(address, signature, arguments='', block='latest'):
    return rpc('eth_call', [{'to': address, 'data': cast('sig', signature) + arguments}, block])


def val(address, signature, arguments='', block='latest'):
    return words(call(address, signature, arguments, block))[0]


def save(manifest):
    DIRECTORY.mkdir(parents=True, exist_ok=True)
    temp = MANIFEST.with_suffix('.tmp')
    temp.write_text(json.dumps(manifest, indent=2) + '\n')
    temp.replace(MANIFEST)


def load():
    data = json.loads(MANIFEST.read_text())
    require(data['configHash'] == hashlib.sha256(CONFIG.read_bytes()).hexdigest(), 'Configuration changed since deployment started')
    require(data['deployer'].lower() == DEPLOYER, 'Manifest deployer mismatch')
    require(data['simulationOnly'] == (os.environ.get('LOCAL_FORK') == '1'), 'Manifest network mode mismatch')
    return data


def preflight():
    require(rpc('eth_chainId', []) == '0x1', 'Expected Ethereum chain ID 1')
    if os.environ.get('LOCAL_FORK') != '1':
        require('anvil' not in rpc('web3_clientVersion', []).lower(), 'Production RPC must not be Anvil')
    block = rpc('eth_getBlockByNumber', ['latest', False])
    tag = block['number']
    require(int(block['timestamp'], 16) < NUMBERS['EXPIRY'], 'PT already matured')
    for key, address in ADDRESSES.items():
        if key != 'DEAD':
            require(rpc('eth_getCode', [address, tag]) != '0x', key + ' has no bytecode')
    a = ADDRESSES
    require(words(call(a['PENDLE_MARKET'], 'readTokens()', block=tag)) == [int(a[k], 16) for k in ['SY_SUSDS', 'PT_SUSDS', 'YT_SUSDS']], 'Pendle token graph mismatch')
    for key in ['PENDLE_MARKET', 'PT_SUSDS', 'YT_SUSDS']:
        require(val(a[key], 'expiry()', block=tag) == NUMBERS['EXPIRY'], key + ' expiry mismatch')
    for key, getter, expected in [('PT_SUSDS', 'SY()', 'SY_SUSDS'), ('PT_SUSDS', 'YT()', 'YT_SUSDS'), ('YT_SUSDS', 'PT()', 'PT_SUSDS'), ('YT_SUSDS', 'SY()', 'SY_SUSDS')]:
        require(val(a[key], getter, block=tag) == int(a[expected], 16), key + '.' + getter + ' mismatch')
    for key in ['PT_SUSDS', 'USDS']:
        require(val(a[key], 'decimals()', block=tag) == 18, key + ' decimals mismatch')
    require(words(call(a['SY_SUSDS'], 'assetInfo()', block=tag)) == [0, int(a['USDS'], 16), 18], 'SY accounting unit mismatch')
    require(val(a['SY_SUSDS'], 'paused()', block=tag) == 0, 'SY paused')
    require(val(a['MORPHO'], 'isIrmEnabled(address)', word(a['ADAPTIVE_CURVE_IRM']), tag) == 1, 'IRM disabled')
    require(val(a['MORPHO'], 'isLltvEnabled(uint256)', word(NUMBERS['LLTV']), tag) == 1, 'LLTV disabled')
    balances = {'ethWei': int(rpc('eth_getBalance', [DEPLOYER, tag]), 16), 'usdsBaseUnits': val(a['USDS'], 'balanceOf(address)', word(DEPLOYER), tag)}
    require(balances['ethWei'] > 0, 'Deployer has no ETH')
    if MANIFEST.exists():
        data = load()
    else:
        require(balances['usdsBaseUnits'] >= 1000, 'Deployer has insufficient USDS for fresh seed')
        data = {'chainId': 1, 'marketLabel': 'USDS / PT-sUSDS-27MAY2027', 'simulationOnly': os.environ.get('LOCAL_FORK') == '1', 'deployer': DEPLOYER, 'configHash': hashlib.sha256(CONFIG.read_bytes()).hexdigest(), 'sourceCommit': cast_git_head(), 'addresses': a, 'parameters': NUMBERS, 'steps': {}, 'initialBalances': balances, 'allocationCeilingStatus': 'planned, not enforced', 'vaultOnboarding': 'not performed'}
    data['preflightBlock'] = {k: block[k] for k in ['number', 'hash', 'timestamp']}
    save(data)
    print('Preflight passed at block', int(tag, 16), '; balances:', json.dumps(balances))


def cast_git_head():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()


def recover(step):
    data = load()
    path = BROADCAST / step / '1/run-latest.json'
    require(path.exists(), 'No receipt bundle; inspect intent before retrying')
    bundle = json.loads(path.read_text())
    receipts = []
    for tx in bundle['transactions']:
        require(tx.get('hash'), 'Unsigned or unsubmitted transaction remains; manual reconciliation required')
        receipt = rpc('eth_getTransactionReceipt', [tx['hash']])
        require(receipt is not None, 'Transaction is not mined; do not resubmit')
        receipts.append(receipt)
    data['steps'][step] = {'receipts': receipts, 'status': 'receipts recovered'}
    save(data)  # Preserve mined results before verification that might fail.
    for receipt in receipts:
        require(receipt['status'] == '0x1', 'Mined transaction reverted; inspect before retrying')
        require(receipt['from'].lower() == DEPLOYER, 'Receipt sender mismatch')
        canonical = rpc('eth_getBlockByNumber', [receipt['blockNumber'], False])
        require(canonical['hash'] == receipt['blockHash'], 'Receipt is not canonical')
    if step in STEPS[:2]:
        factory = ADDRESSES['SPARK_LINEAR_DISCOUNT_ORACLE_FACTORY' if step == STEPS[0] else 'MORPHO_CHAINLINK_ORACLE_V2_FACTORY']
        signature = 'OracleCreated(address,uint256,address)' if step == STEPS[0] else 'CreateMorphoChainlinkOracleV2(address,address)'
        topic = cast('keccak', signature)
        logs = [log for r in receipts for log in r['logs'] if log['address'].lower() == factory.lower() and log['topics'][0] == topic]
        require(len(logs) == 1, 'Expected exactly one matching factory event')
        log = logs[0]
        decoded = words(log['data'])
        require(len(decoded) == 2, 'Unexpected factory event encoding')
        if step == STEPS[0]:
            require(int(log['topics'][1], 16) == int(ADDRESSES['PT_SUSDS'], 16), 'Factory event PT mismatch')
            require(decoded[0] == NUMBERS['BASE_DISCOUNT_PER_YEAR'], 'Factory event slope mismatch')
        else:
            require(decoded[0] == int(DEPLOYER, 16), 'Wrapper factory caller mismatch')
        address = '0x' + word(decoded[1])[-40:]
        data['ptOracle' if step == STEPS[0] else 'morphoOracle'] = address
    data['steps'][step]['status'] = 'mined'
    save(data)


def verify(stage):
    data = load()
    block = rpc('eth_getBlockByNumber', ['latest', False])
    tag = block['number']
    a = ADDRESSES
    pt = data['ptOracle']
    for getter, expected in [('PT()', int(a['PT_SUSDS'], 16)), ('maturity()', NUMBERS['EXPIRY']), ('baseDiscountPerYear()', NUMBERS['BASE_DISCOUNT_PER_YEAR']), ('decimals()', 18)]:
        require(val(pt, getter, block=tag) == expected, 'PT oracle mismatch: ' + getter)
    expected = 10**18 - max(NUMBERS['EXPIRY'] - int(block['timestamp'], 16), 0) * NUMBERS['BASE_DISCOUNT_PER_YEAR'] // 31536000
    require(words(call(pt, 'latestRoundData()', block=tag))[1] == expected, 'PT price mismatch')
    observed = {'ptPrice': expected}
    if stage >= 2:
        oracle = data['morphoOracle']
        wiring = {'BASE_VAULT': 0, 'BASE_VAULT_CONVERSION_SAMPLE': 1, 'QUOTE_VAULT': 0, 'QUOTE_VAULT_CONVERSION_SAMPLE': 1, 'BASE_FEED_1': int(pt, 16), 'BASE_FEED_2': 0, 'QUOTE_FEED_1': 0, 'QUOTE_FEED_2': 0, 'SCALE_FACTOR': 10**18}
        for getter, value in wiring.items():
            require(val(oracle, getter + '()', block=tag) == value, 'Wrapper mismatch: ' + getter)
        require(val(oracle, 'price()', block=tag) == expected * 10**18, 'Morpho price mismatch')
        observed['morphoPrice'] = expected * 10**18
        params = [a['USDS'], a['PT_SUSDS'], oracle, a['ADAPTIVE_CURVE_IRM'], NUMBERS['LLTV']]
        encoded = ''.join(word(x) for x in params)
        market_id = cast('keccak', '0x' + encoded)
        data['marketId'] = market_id
        data['marketParams'] = dict(zip(['loanToken', 'collateralToken', 'oracle', 'irm', 'lltv'], params))
    if stage >= 3:
        require(call(a['MORPHO'], 'idToMarketParams(bytes32)', word(market_id), tag)[2:].lower() == encoded.lower(), 'Stored market tuple mismatch')
        market = words(call(a['MORPHO'], 'market(bytes32)', word(market_id), tag))
        require(market[4] > 0, 'Market not initialized')
        observed['marketState'] = market
    if stage >= 4:
        position = words(call(a['MORPHO'], 'position(bytes32,address)', word(market_id) + word(a['DEAD']), tag))
        require(position[0] >= NUMBERS['DEAD_SUPPLY_SHARES'], 'Dead shares below target')
        require(val(a['USDS'], 'allowance(address,address)', word(DEPLOYER) + word(a['MORPHO']), tag) == 0, 'Residual approval remains')
        observed['deadPosition'] = position
        observed['finalBalances'] = {'ethWei': int(rpc('eth_getBalance', [DEPLOYER, tag]), 16), 'usdsBaseUnits': val(a['USDS'], 'balanceOf(address)', word(DEPLOYER), tag)}
        data['status'] = 'deployed and seeded; independent review and onboarding pending'
    data['verification'] = {'stage': stage, 'block': {k: block[k] for k in ['number', 'hash', 'timestamp']}, 'observed': observed}
    for key in ['ptOracle', 'morphoOracle']:
        if key in data:
            data.setdefault('runtimeCodeHashes', {})[key] = cast('keccak', rpc('eth_getCode', [data[key], tag]))
    save(data)
    print('Independent verification passed for stage', stage, 'at block', int(tag, 16))


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'preflight':
            preflight()
        elif sys.argv[1] == 'recover':
            recover(sys.argv[2])
        elif sys.argv[1] == 'verify':
            verify(int(sys.argv[2]))
        elif sys.argv[1] == 'get':
            print(load()[sys.argv[2]])
        else:
            raise RuntimeError('Unknown action')
    except Exception as error:
        # Never include RPC credentials in errors or logs.
        print(str(error).replace(RPC, '[RPC REDACTED]'), file=sys.stderr)
        sys.exit(1)
