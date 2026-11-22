// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

interface IPendleMarket {
    function expiry() external view returns (uint256);
    function readTokens() external view returns (address sy, address pt, address yt);
}

interface IPrincipalToken {
    function expiry() external view returns (uint256);
    function SY() external view returns (address);
    function YT() external view returns (address);
}

interface IYieldToken {
    function expiry() external view returns (uint256);
    function SY() external view returns (address);
    function PT() external view returns (address);
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
    function accrueInterest(MarketParams memory marketParams) external;
    function position(bytes32 id, address account)
        external
        view
        returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral);
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory);
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);
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
    // May 27, 2027 Pendle deployment from the PRD; verified against Ethereum.
    address constant PENDLE_MARKET = 0x50D24456eD009A1461A159A2B4dcD12aDfE6A60b; // PT-sUSDS-27MAY2027 market
    address constant PT_SUSDS = 0x49080d5e26227B5c98e0662A7498A9Dd60c56b06;
    address constant SY_SUSDS = 0x5E4CEcc6676Ef448f20822D2449bC1bdE1432Eb4;
    address constant YT_SUSDS = 0xC2de924D686Ff2D69a14c85aECB81A33240B7e23;

    // Shared infrastructure: factory address does not change with PT maturity.
    address constant SPARK_LINEAR_DISCOUNT_ORACLE_FACTORY = 0x34C91651A070664279866E5f3d6B4d5F65cbbFFb;

    // Morpho (mainnet)
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant MORPHO_CHAINLINK_ORACLE_V2_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;
    address constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // PT-sUSDS-27MAY2027 / USDS PRD
    uint256 constant LLTV = 0.915e18; // 91.5%
    uint256 constant BASE_DISCOUNT_PER_YEAR = 0.1e18; // 10% annual valuation discount slope

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 constant DEAD_SUPPLY_SHARES = 1e9;

    uint256 constant EXPIRY = 1811376000;
    uint256 constant ALLOCATION_CEILING = 5_000_000e18; // Planned vault cap; not enforced by market creation.

    function checkPendleDeployment() public view {
        require(block.chainid == 1, "expected Ethereum mainnet");
        (address sy, address pt, address yt) = IPendleMarket(PENDLE_MARKET).readTokens();
        require(pt == PT_SUSDS, "unexpected PT token");
        require(sy == SY_SUSDS, "unexpected SY token");
        require(yt == YT_SUSDS, "unexpected YT token");
        require(IPendleMarket(PENDLE_MARKET).expiry() == EXPIRY, "unexpected LP expiry");
        require(IPrincipalToken(PT_SUSDS).expiry() == EXPIRY, "unexpected PT expiry");
        require(IYieldToken(YT_SUSDS).expiry() == EXPIRY, "unexpected YT expiry");
        require(IPrincipalToken(PT_SUSDS).SY() == SY_SUSDS, "unexpected PT.SY");
        require(IPrincipalToken(PT_SUSDS).YT() == YT_SUSDS, "unexpected PT.YT");
        require(IYieldToken(YT_SUSDS).PT() == PT_SUSDS, "unexpected YT.PT");
        require(IYieldToken(YT_SUSDS).SY() == SY_SUSDS, "unexpected YT.SY");
    }

    function marketParams(address oracle) public pure returns (MarketParams memory) {
        return
            MarketParams({
                loanToken: USDS, collateralToken: PT_SUSDS, oracle: oracle, irm: ADAPTIVE_CURVE_IRM, lltv: LLTV
            });
    }
}
