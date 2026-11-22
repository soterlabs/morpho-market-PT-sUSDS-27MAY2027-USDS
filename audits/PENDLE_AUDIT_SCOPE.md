# Pendle audit applicability

Reviewed 22 November 2026 for the Ethereum sUSDS 27MAY2027 deployment. Reports are implementation reviews, not approval of this Morpho market or its parameters.

## Selected reports

| Report | Relevance and limits |
|---|---|
| [ChainSecurity, 2024](Pendle-Core-ChainSecurity-2024.pdf) | Historical core baseline: PT/YT, V1 market, shared libraries and base SY. Derived SY implementations are outside scope. The deployed PT/YT sources differ from its public initial audit commit; this is not proof of coverage of their complete deployed versions. |
| [Spearbit, 2024](Pendle-Core-Spearbit-2024.pdf) | Core follow-up evidence, including YT post-expiry rewards, interest/reward accounting and market math. Does not establish coverage of V7 or the new sUSDS SY. |
| [HickupHH3, MarketV7](Pendle-MarketV7-HickupHH3.pdf) | January 2026 review of V6-to-V7 changes, market factory and gauge controller; audit commit `134b10def50c893afd850afa928b9ee0c037eba1`. |
| [WatchPug, MarketV7](Pendle-MarketV7-WatchPug.pdf) | January 2026 MarketV7 review; audit commit `e23126085ff1c971024fb535ff1f69f91c752f86`. Two findings: unnecessary errors acknowledged; unused gauge imports fixed. |
| [HickupHH3, sUSDS SY](Pendle_sUSDSSY_hickuphh3.pdf) | November 2026 supply cap and rate-limiter hooks review. Audit commit printed as `c3151a173737...`. One informational finding acknowledged: preview-deposit overflow can precede the cap check. |
| [WatchPug, sUSDS SY](Pendle_sUSDSSY_Watchpug.pdf) | November 2026 supply-cap review at `c3151a1737376bacba94a0298484b55953d8bc37`. One informational finding acknowledged: recommendation to use the ERC4626 V2 exchange-rate implementation. |

All 14 reports in the supplied main-codebase folder were inspected. The older 2022 Part 1/follow-up reports provide historical tokenization/trading evidence; Part 2 reports address historical liquidity mining and reward/gauge dependencies. They were not duplicated here: the selected 2024 core reports and dedicated V7 reviews are the more relevant review set, without implying that they subsume every older finding. V7 reports came from the sibling `audits/marketV7` folder because the main-codebase folder alone misses that version-specific scope.

## Deployment checks

Verified source was retrieved from Sourcify and cross-checked against Blockscout contract identities:

| Token | Ethereum address | Verified contract |
|---|---|---|
| PT | `0x49080d5e26227b5c98e0662a7498a9dd60c56b06` | PendlePrincipalToken (VERSION 6) |
| YT | `0xc2de924d686ff2d69a14c85aecb81a33240b7e23` | PendleYieldToken |
| SY | `0x5e4cecc6676ef448f20822d2449bc1bde1432eb4` | PendleSUSDSSY |
| LP | `0x50d24456ed009a1461a159a2b4dcd12adfe6a60b` | PendleMarketV7 |

Sourcify evidence is available at `https://sourcify.dev/server/v2/contract/1/<address>?fields=all`; PT returned `exact_match`, and YT/SY/LP returned `match` rather than metadata-exact matches.

Five verified SY source files exactly match [Pendle-SY-Public commit c3151a1](https://github.com/pendle-finance/Pendle-SY-Public/tree/c3151a1737376bacba94a0298484b55953d8bc37): `PendleSUSDSSY.sol`, `SYBase.sol`, `TokenWithRateLimit.sol`, `IPRateLimiter.sol`, and `PendleERC4626SY.sol`. This comparison covers those files, not every dependency, compiler behavior, configuration or the external rate-limiter implementation. The HickupHH3 report's abbreviated commit agrees with WatchPug's full commit prefix.

The verified `PendleMarketV7.sol` exactly matches the public repository snapshot below. Neither V7 audit commit was retrievable from that public repository (HTTP 404), so audit-commit equivalence remains unconfirmed. ChainSecurity's public initial commit `979d55419b65b2565964021f50da25b36acd6d32` differs from the deployed PT, YT and market sources; its report explicitly scopes V1 markets. No complete audit-to-deployment equivalence is claimed for the PT/YT/LP stack.

## Provenance

Upstream PDFs were downloaded without modification from [Pendle public snapshot 82e69f0](https://github.com/pendle-finance/pendle-core-v2-public/tree/82e69f0b2279c85f250a87cb0fe16a2b432ebb72/audits), using these paths:

- `main codebase/ChainSecurity-2024/ChainSecurity.pdf`
- `main codebase/Spearbit-2024/Spearbit.pdf`
- `marketV7/HickupHH3.pdf`
- `marketV7/WatchPug.pdf`

Their Git blob hashes matched the upstream tree. The two `Pendle_sUSDSSY_*.pdf` files were copied byte-for-byte from the supplied local files; their publication origin was not independently established.

SHA-256 checksums:

```text
63e08e69377b1713593b390783d2ec74c21b727eaffe5538bf9e0b684fb48903  Pendle-Core-ChainSecurity-2024.pdf
c5d6b7c78b4892260323590c607527412001747aee81ccd94633b7c5918418f3  Pendle-Core-Spearbit-2024.pdf
d8cc5b023d116ba7fb07cd4641eb6c0f43a731e5cabe98eac93d6cabb8948920  Pendle-MarketV7-HickupHH3.pdf
7ff40bbb79c89c5472898b9a9242b4fbfdab6e5a83d59946ab9d180db87677a5  Pendle-MarketV7-WatchPug.pdf
035311e266d2830c2cab40cd90e6e0704ed1ba3e74b4012e3fe2ca8522d393f3  Pendle_sUSDSSY_hickuphh3.pdf
7371c169fd2eb985441359644d4e14f317156d2e1921747419e029fdebbe9e8b  Pendle_sUSDSSY_Watchpug.pdf
```
