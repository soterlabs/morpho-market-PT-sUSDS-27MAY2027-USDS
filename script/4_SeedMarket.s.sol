// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/Script.sol";
import {Config, IMorpho, MarketParams} from "./Config.sol";

interface ISeedToken {
    function approve(address spender, uint256 assets) external returns (bool);
}

/// USDS / PT-sUSDS-27MAY2027: initialize the dead position, without borrowing.
contract SeedMarket is Config {
    function run() external {
        MarketParams memory params = marketParams(vm.envAddress("MORPHO_ORACLE"));
        // Native USDS units, not whole tokens. Fresh market: 1e9 shares costs 1000 units.
        uint256 maxAssets = vm.envOr("SEED_MAX_ASSETS", uint256(1000));
        vm.startBroadcast();
        (uint256 assets, uint256 shares) = execute(params, maxAssets);
        vm.stopBroadcast();
        check(params);
        console.log("Dead deposit USDS base units spent:", assets);
        console.log("Dead deposit shares added:", shares);
    }

    function execute(MarketParams memory params, uint256 maxAssets) public returns (uint256 assets, uint256 shares) {
        checkPendleDeployment();
        require(params.oracle != address(0), "oracle unset");
        require(
            keccak256(abi.encode(params)) == keccak256(abi.encode(marketParams(params.oracle))),
            "unexpected market params"
        );
        bytes32 id = keccak256(abi.encode(params));
        (,,,, uint128 lastUpdate,) = IMorpho(MORPHO).market(id);
        require(lastUpdate != 0, "market not created");
        require(keccak256(abi.encode(IMorpho(MORPHO).idToMarketParams(id))) == id, "stored market mismatch");
        (uint256 existing,,) = IMorpho(MORPHO).position(id, DEAD);
        if (existing >= DEAD_SUPPLY_SHARES) return (0, 0);

        shares = DEAD_SUPPLY_SHARES - existing;
        IMorpho(MORPHO).accrueInterest(params);
        (uint128 totalAssets, uint128 totalShares,,,,) = IMorpho(MORPHO).market(id);
        // Morpho SharesMathLib.toAssetsUp: VIRTUAL_ASSETS=1; VIRTUAL_SHARES=1e6.
        // shares <= 1e9 and totals are uint128, so this multiplication cannot overflow.
        uint256 denominator = uint256(totalShares) + 1e6;
        uint256 requiredAssets = (shares * (uint256(totalAssets) + 1) + denominator - 1) / denominator;
        require(requiredAssets <= maxAssets, "seed exceeds asset limit");
        // Exact approval also bounds spending if the ratio changes before the supply is mined.
        require(ISeedToken(USDS).approve(MORPHO, requiredAssets), "seed approval failed");
        (assets, shares) = IMorpho(MORPHO).supply(params, 0, shares, DEAD, "");
        require(assets <= maxAssets, "seed exceeds asset limit");
        require(ISeedToken(USDS).approve(MORPHO, 0), "seed approval cleanup failed");
        check(params);
    }

    function check(MarketParams memory params) public view {
        (uint256 shares,,) = IMorpho(MORPHO).position(keccak256(abi.encode(params)), DEAD);
        require(shares >= DEAD_SUPPLY_SHARES, "dead supply below minimum");
    }
}
