// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/Script.sol";
import {Config, IPrincipalToken, ISparkLinearDiscountOracleFactory, IAggregatorV3} from "./Config.sol";

/// Step 1: deploy the linear-discount PT-sUSDS/USDS oracle via Pendle's factory, then check it.
contract DeployPtOracle is Config {
    function run() external returns (address ptOracle) {
        vm.startBroadcast();
        ptOracle = execute();
        vm.stopBroadcast();

        check(ptOracle);
        // run.sh reads the real deployed address from the mined OracleCreated event, not this log
        // (forge's dry-run predicts a different CREATE address than the broadcast for this factory).
        console.log("ptOracle:", ptOracle);
    }

    function execute() public returns (address) {
        checkPendleDeployment();
        return ISparkLinearDiscountOracleFactory(SPARK_LINEAR_DISCOUNT_ORACLE_FACTORY)
            .createWithMarket(PENDLE_MARKET, BASE_DISCOUNT_PER_YEAR);
    }

    // check: 18-dec feed whose price is exactly the linear discount off par for our
    // configured rate — catches a wrong/zero discount, not just an in-band value.
    function check(address ptOracle) public view {
        require(ptOracle != address(0), "oracle not deployed");
        require(IAggregatorV3(ptOracle).decimals() == 18, "expected 18 decimals");

        uint256 maturity = IPrincipalToken(PT_SUSDS).expiry();
        uint256 timeLeft = maturity > block.timestamp ? maturity - block.timestamp : 0;
        uint256 expected = 1e18 - (timeLeft * BASE_DISCOUNT_PER_YEAR) / 365 days; // mirrors the oracle

        (, int256 answer,,,) = IAggregatorV3(ptOracle).latestRoundData();
        require(uint256(answer) == expected, "PT price != configured linear discount");
        require(answer > 0 && answer <= 1e18, "PT price outside (0, par]");
    }
}
