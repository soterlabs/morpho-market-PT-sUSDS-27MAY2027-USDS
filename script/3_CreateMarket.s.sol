// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/Script.sol";
import {Config, IMorpho, MarketParams} from "./Config.sol";

/// Step 3: create the PT-sUSDS/USDS Morpho market, then check it exists.
contract CreateMarket is Config {
    function run() external returns (bytes32 id) {
        MarketParams memory params = marketParams(vm.envAddress("MORPHO_ORACLE"));
        vm.startBroadcast();
        execute(params);
        vm.stopBroadcast();

        id = check(params);
        console.log("marketId:");
        console.logBytes32(id);
    }

    function execute(MarketParams memory params) public {
        require(params.oracle != address(0), "morphoOracle unset - run step 2 first");
        IMorpho(MORPHO).createMarket(params);
    }

    // check: market now exists on Morpho (lastUpdate set at creation)
    function check(MarketParams memory params) public view returns (bytes32 id) {
        id = keccak256(abi.encode(params));
        (,,,, uint128 lastUpdate,) = IMorpho(MORPHO).market(id);
        require(lastUpdate > 0, "market not created");
    }
}
