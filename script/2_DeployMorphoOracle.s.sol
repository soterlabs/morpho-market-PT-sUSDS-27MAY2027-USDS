// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/Script.sol";
import {Config, IMorphoChainlinkOracleV2Factory, IMorphoOracle, IAggregatorV3} from "./Config.sol";

/// Step 2: wrap the PT oracle in a MorphoChainlinkOracleV2 (1e36 price), then check it.
contract DeployMorphoOracle is Config {
    function run() external returns (address morphoOracle) {
        address ptOracle = vm.envAddress("PT_ORACLE"); // real address from step 1, threaded by run.sh
        vm.startBroadcast();
        morphoOracle = execute(ptOracle);
        vm.stopBroadcast();

        check(ptOracle, morphoOracle);
        console.log("morphoOracle:", morphoOracle);
    }

    function execute(address ptOracle) public returns (address) {
        require(ptOracle != address(0), "ptOracle unset - run step 1 first");
        // both tokens 18 dec, feed 18 dec -> price() scaled to 1e36
        return IMorphoChainlinkOracleV2Factory(MORPHO_CHAINLINK_ORACLE_V2_FACTORY)
            .createMorphoChainlinkOracleV2(
                address(0), 1, ptOracle, address(0), 18, address(0), 1, address(0), address(0), 18, bytes32(0)
            );
    }

    // check: the Morpho oracle actually wraps ptOracle — price() is exactly the feed
    // answer scaled to 1e36 (feed 18 dec, both tokens 18 dec). Catches a stale/wrong ptOracle.
    function check(address ptOracle, address morphoOracle) public view {
        (, int256 answer,,,) = IAggregatorV3(ptOracle).latestRoundData();
        uint256 price = IMorphoOracle(morphoOracle).price();
        require(price == uint256(answer) * 1e18, "morpho price != ptOracle feed (wrong oracle wired)");
        require(price > 0.8e36 && price <= 1e36, "morpho price out of (0.8e36, 1e36]");
    }
}
