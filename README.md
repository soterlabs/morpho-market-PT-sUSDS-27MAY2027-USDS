# USDS / PT-sUSDS-27MAY2027

May-market adaptation of the November deployment baseline. `run.sh` supports local fork rehearsals and explicit mainnet deployment using an encrypted Foundry keystore. It records mined receipts, verifies each stage independently and reuses verified completed steps on rerun. Independent deployment review and vault onboarding remain separate milestones.

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

`0x34C91651A070664279866E5f3d6B4d5F65cbbFFb` is the shared PendleSparkLinearDiscountOracleFactory, not a PT token or a November-specific feed. `createWithMarket(PENDLE_MARKET, BASE_DISCOUNT_PER_YEAR)` creates the new market-specific oracle. The receipt verifier reads this factory address from Config.sol to locate its exact creation event; it also reads the shared Morpho wrapper factory there. USDS, Morpho Blue, AdaptiveCurveIRM and both factories remain the PRD's shared mainnet infrastructure. No old PT oracle is reused.
