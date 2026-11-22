# USDS / PT-sUSDS-27MAY2027

Initial May-market adaptation of the November deployment baseline. This repository is not deployment-ready: the full PRD workflow remains to be implemented and reviewed. `run.sh` permits loopback Anvil fork rehearsals only; production broadcasts remain disabled.

## Provenance

Files copied from [soterlabs/morpho-market-pt-susds](https://github.com/soterlabs/morpho-market-pt-susds/tree/256bb9858cc2b42c2e1fbc556060eeacd6545f29), commit `256bb9858cc2b42c2e1fbc556060eeacd6545f29`. This is a standalone repository with fresh Git history, not a GitHub fork. Historical broadcast receipts are excluded. Audit PDFs are inherited background evidence, not certification of the May deployment or Sky clearance.

## Configuration

- Ethereum mainnet; collateral PT-sUSDS-27MAY2027; loan token USDS.
- Maturity: 27 May 2027, 00:00 UTC (`1811376000`).
- LLTV: 91.5%; interest-rate model: AdaptiveCurveIRM.
- Linear valuation discount: 10% annually, converging to 1 USDS/PT at maturity. This is not the borrow APR.
- Oracle: PT linear feed only, wrapped for Morpho with 18-decimal collateral and loan assets. No USD feeds or ERC-4626 conversion.
- Allocation ceiling: 5,000,000 USDS, planned and not enforced. It is a future vault cap, not a market-wide cap.

Authoritative addresses are in `script/Config.sol`. The LP, PT, SY and YT must match the May deployment; the preflight checks their cross-links and LP/PT/YT expiry.

`0x34C91651A070664279866E5f3d6B4d5F65cbbFFb` is the shared PendleSparkLinearDiscountOracleFactory, not a PT token or a November-specific feed. `createWithMarket(PENDLE_MARKET, BASE_DISCOUNT_PER_YEAR)` creates the new market-specific oracle. The runner reads this factory address from Config.sol to locate its receipt log; it also reads the shared Morpho wrapper factory there. USDS, Morpho Blue, AdaptiveCurveIRM and both factories remain the PRD's shared mainnet infrastructure. No old PT oracle is reused.

## Local verification

Use Foundry v1.8.1 and Solidity 0.8.28. Install the pinned dependency with `git submodule update --init --recursive`.

```sh
forge fmt --check
forge build
ETH_RPC_URL=<ethereum-archive-rpc> forge test -vvv
```

CI requires an `ETH_RPC_URL` repository secret with archive access; no RPC credential is included in this repository.

The existing end-to-end test runs at Ethereum block 26471676 and simulates feed deployment, wrapper deployment and market creation without broadcasting. It does not constitute the full PRD acceptance suite.

## Remaining Step 1 work

- Full Pendle graph, feed immutable and market tuple checks; negative tests and maturity scenarios.
- Restart-safe deployment scripts with receipt reconciliation and immutable configuration snapshots.
- Broader supply/borrow/repay smoke tests and deployment receipt reconciliation for all steps.
- Deployment manifest schema and independent read-only Dewiz verification procedure.
- Optional vault-cap calldata after policy and authority confirmation.

Mainnet deployment, security clearance, review approval and vault onboarding are separate milestones. No deployment addresses or approvals have been recorded for this new Morpho market.

## Dead deposit: step 4

`run.sh` now includes `script/4_SeedMarket.s.sol:SeedMarket` immediately after market creation. Production execution remains disabled pending completion of the deployment workflow above; fork rehearsals include all four steps.

This step supplies USDS on behalf of `0x000000000000000000000000000000000000dEaD` until that position has at least `1e9` supply shares, following [Morpho market dead-deposit guidance](https://docs.morpho.org/curate/tutorials-market-v1/dead-deposit/). These shares are permanently inaccessible. This is separate from Pendle LP liquidity and creates no borrow position.

The script verifies the May token graph and market parameters, accrues interest, reads the existing dead position and market totals, then calculates the missing shares' USDS cost with upward rounding and Morpho's virtual assets/shares. It approves only the calculated assets, supplies by exact shares, clears the approval and checks the resulting position. If already seeded, it sends no seed transactions; partial positions receive only the missing shares.

`SEED_MAX_ASSETS` is an optional spending ceiling in USDS base units, defaulting to `1000` (0.000000000000001 USDS). A fresh market needs exactly 1000 base units to mint `1e9` shares. A populated market may need more; the script rejects an amount above the ceiling. The deployer must hold the required USDS as well as ETH for gas. An approval-bounded supply can revert if the share price increases between simulation and mining; inspect receipts and rerun this seed step against confirmed state, rather than rerunning all deployments.

Once the market has been deployed and verified, the seed step can also be run separately:

```sh
MORPHO_ORACLE=<verified-may-market-oracle> forge script script/4_SeedMarket.s.sol:SeedMarket --rpc-url "$ETH_RPC_URL" --account pendle-may2027-deployer --broadcast
```

The seed tests cover a fresh deposit, repeated execution, partial top-up, asset-limit rejection, a populated market with accrued borrow interest and upward rounding, an uncreated market and a wrong loan token. These are fork tests, not tests of shell orchestration or live transaction sequencing.

## Full runner rehearsal on a current Ethereum fork

The shell runner supports `LOCAL_FORK=1` only. It verifies a loopback HTTP endpoint, Anvil fork metadata and chain ID 1 before submitting transactions. No private key is needed: impersonate the intended deployer on the local Anvil node. The deployer's actual forked ETH and USDS balances must cover the deployment; the runner does not fund it.

Start Anvil using an Ethereum RPC, retaining chain ID 1, and use a separate terminal for the runner:

```sh
anvil --fork-url "$ETH_RPC_URL" --chain-id 1 --host 127.0.0.1 --port 18545 --silent
```

```sh
export DEPLOYER=<deployer-address>
cast rpc --rpc-url http://127.0.0.1:18545 anvil_impersonateAccount "$DEPLOYER"
LOCAL_FORK=1 RPC=http://127.0.0.1:18545 ./run.sh
```

Fork receipts go to a newly created `/tmp/pendle-may2027-broadcast.*` directory, or the explicit `FORK_ARTIFACT_DIR`, keeping simulated chain-1 receipts separate from production artifacts. Start a clean fork for a new full rehearsal; the full runner does not yet resume partial deployments. The seed step independently supports retries.

The runner uses sequential mining and a 300% gas-estimate multiplier. A full rehearsal exposed an out-of-gas revert in interest accrual with Foundry's default multiplier: a later mined block executes more work than same-block simulation. Unused gas allowance is not charged.

Validated against Ethereum block 26473666 (2026-11-22 22:31:59 UTC): all four steps completed in seven local transactions with the requested deployer's unmodified balances. Independent reads checked both oracle configurations, exact prices, full market parameters and the dead position. Repeating seeding produced no transactions. This is local fork evidence, not a mainnet deployment or completion of the remaining PRD review workflow.
