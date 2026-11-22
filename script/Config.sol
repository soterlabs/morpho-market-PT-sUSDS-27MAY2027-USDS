// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

interface IPendleMarket {
    function readTokens() external view returns (address sy, address pt, address yt);
}

interface IPrincipalToken {
    function expiry() external view returns (uint256);
}

// Pendle PendleSparkLinearDiscountOracleFactory
// price = 1e18 - timeLeft * baseDiscountPerYear / 365d ; -> 1 USDS at maturity
interface ISparkLinearDiscountOracleFactory {
    function createWithMarket(address market, uint256 baseDiscountPerYear) external returns (address);
}

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

interface IMorphoChainlinkOracleV2Factory {
    function createMorphoChainlinkOracleV2(
        address baseVault,
        uint256 baseVaultConversionSample,
        address baseFeed1,
        address baseFeed2,
        uint256 baseTokenDecimals,
        address quoteVault,
        uint256 quoteVaultConversionSample,
        address quoteFeed1,
        address quoteFeed2,
        uint256 quoteTokenDecimals,
        bytes32 salt
    ) external returns (address);
}

interface IMorphoOracle {
    function price() external view returns (uint256);
}

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

interface IMorpho {
    function createMarket(MarketParams memory marketParams) external;
    function market(bytes32 id)
        external
        view
        returns (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            uint128 lastUpdate,
            uint128 fee
        );
}

/// Shared mainnet addresses and PRD market parameters for the deploy scripts.
contract Config is Script {
    // Pendle (mainnet, from pendle-core-v2-public deployments/1-core.json)
    address constant PENDLE_MARKET = 0x50D24456eD009A1461A159A2B4dcD12aDfE6A60b; // PT-sUSDS-27MAY2027 market
    address constant PT_SUSDS = 0x49080d5e26227B5c98e0662A7498A9Dd60c56b06;
    address constant SPARK_LINEAR_DISCOUNT_ORACLE_FACTORY = 0x34C91651A070664279866E5f3d6B4d5F65cbbFFb;

    // Morpho (mainnet)
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant MORPHO_CHAINLINK_ORACLE_V2_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;
    address constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // PT-sUSDS-27MAY2027 / USDS PRD
    uint256 constant LLTV = 0.915e18; // 91.5%
    uint256 constant BASE_DISCOUNT_PER_YEAR = 0.1e18; // 10% annual valuation discount slope

    uint256 constant EXPIRY = 1811376000;
    uint256 constant ALLOCATION_CEILING = 5_000_000e18; // Planned vault cap; not enforced by market creation.

    function marketParams(address oracle) public pure returns (MarketParams memory) {
        return
            MarketParams({
                loanToken: USDS, collateralToken: PT_SUSDS, oracle: oracle, irm: ADAPTIVE_CURVE_IRM, lltv: LLTV
            });
    }
}
