// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMorpho, MarketParams} from "../script/Config.sol";
import {DeployPtOracle} from "../script/1_DeployPtOracle.s.sol";
import {DeployMorphoOracle} from "../script/2_DeployMorphoOracle.s.sol";
import {CreateMarket} from "../script/3_CreateMarket.s.sol";

contract DeployTest is Test {
    address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address constant PT_SUSDS = 0x49080d5e26227B5c98e0662A7498A9Dd60c56b06;
    address constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // End-to-end: each step's on-chain action + its own check against a mainnet fork.
    function test_sequence() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 26471676);

        DeployPtOracle s1 = new DeployPtOracle();
        address ptOracle = s1.execute();
        s1.check(ptOracle);

        DeployMorphoOracle s2 = new DeployMorphoOracle();
        address morphoOracle = s2.execute(ptOracle);
        s2.check(ptOracle, morphoOracle);

        CreateMarket s3 = new CreateMarket();
        MarketParams memory params = s3.marketParams(morphoOracle);
        s3.execute(params);
        s3.check(params);

        // Independent verification (not via the code under test): market exists with the BA Labs params.
        bytes32 id = keccak256(abi.encode(params));
        (,,,, uint128 lastUpdate,) = IMorpho(MORPHO).market(id);
        assertGt(lastUpdate, 0, "market not created");
        assertEq(params.loanToken, USDS);
        assertEq(params.collateralToken, PT_SUSDS);
        assertEq(params.oracle, morphoOracle);
        assertEq(params.irm, ADAPTIVE_CURVE_IRM);
        assertEq(params.lltv, 0.915e18);
    }
}
