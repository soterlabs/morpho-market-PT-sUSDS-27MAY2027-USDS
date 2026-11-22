// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMorpho, MarketParams, IPendleMarket, IPrincipalToken} from "../script/Config.sol";
import {DeployPtOracle} from "../script/1_DeployPtOracle.s.sol";
import {DeployMorphoOracle} from "../script/2_DeployMorphoOracle.s.sol";
import {CreateMarket} from "../script/3_CreateMarket.s.sol";

contract DeployTest is Test {
    address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address constant PT_SUSDS = 0x49080d5e26227B5c98e0662A7498A9Dd60c56b06;
    address constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 26471676);
    }

    function test_rejectWrongChain() public {
        DeployPtOracle script = new DeployPtOracle();
        vm.chainId(10);
        vm.expectRevert("expected Ethereum mainnet");
        script.execute();
    }

    function test_rejectWrongExpiry() public {
        DeployPtOracle script = new DeployPtOracle();
        vm.mockCall(
            PT_SUSDS, abi.encodeWithSelector(IPrincipalToken.expiry.selector), abi.encode(uint256(1811376000 - 2 days))
        );
        vm.expectRevert("unexpected PT expiry");
        script.execute();
    }

    function test_rejectWrongSY() public {
        DeployPtOracle script = new DeployPtOracle();
        address market = 0x50D24456eD009A1461A159A2B4dcD12aDfE6A60b;
        (, address pt, address yt) = IPendleMarket(market).readTokens();
        vm.mockCall(market, abi.encodeWithSelector(IPendleMarket.readTokens.selector), abi.encode(address(0), pt, yt));
        vm.expectRevert("unexpected SY token");
        script.execute();
    }

    // End-to-end: each step's on-chain action + its own check against a mainnet fork.
    function test_sequence() public {
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

        // Independent verification (not via the code under test): market exists with the May-market parameters.
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
