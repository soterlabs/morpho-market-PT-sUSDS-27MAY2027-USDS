# USDS / PT-sUSDS-27MAY2027

Initial May-market adaptation of the November deployment baseline. This repository is not deployment-ready: the full PRD workflow remains to be implemented and reviewed. `run.sh` is disabled until then.

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
- Dead-supply initialization and supply/borrow/repay smoke tests.
- Deployment manifest schema and independent read-only Dewiz verification procedure.
- Optional vault-cap calldata after policy and authority confirmation.

Mainnet deployment, security clearance, review approval and vault onboarding are separate milestones. No deployment addresses or approvals have been recorded for this new Morpho market.
