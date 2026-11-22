// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMorpho, MarketParams} from "../script/Config.sol";
import {DeployPtOracle} from "../script/1_DeployPtOracle.s.sol";
import {DeployMorphoOracle} from "../script/2_DeployMorphoOracle.s.sol";
import {CreateMarket} from "../script/3_CreateMarket.s.sol";
import {SeedMarket} from "../script/4_SeedMarket.s.sol";

interface ITestToken {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

interface IBorrowMorpho {
    function supplyCollateral(MarketParams memory, uint256, address, bytes calldata) external;
    function borrow(MarketParams memory, uint256, uint256, address, address) external returns (uint256, uint256);
}

contract SeedTest is Test {
    address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    SeedMarket seed;
    MarketParams params;
    bytes32 id;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 26471676);
        address ptOracle = new DeployPtOracle().execute();
        address oracle = new DeployMorphoOracle().execute(ptOracle);
        CreateMarket creator = new CreateMarket();
        params = creator.marketParams(oracle);
        creator.execute(params);
        id = keccak256(abi.encode(params));
        seed = new SeedMarket();
        deal(USDS, address(seed), 1e18);
    }

    function test_freshDepositAndRepeat() public {
        uint256 beforeBalance = ITestToken(USDS).balanceOf(address(seed));
        (uint256 assets, uint256 shares) = seed.execute(params, 1000);
        assertEq(assets, 1000);
        assertEq(shares, 1e9);
        assertEq(beforeBalance - ITestToken(USDS).balanceOf(address(seed)), assets);
        (uint256 deadShares,,) = IMorpho(MORPHO).position(id, DEAD);
        assertEq(deadShares, 1e9);
        assertEq(ITestToken(USDS).allowance(address(seed), MORPHO), 0);
        (assets, shares) = seed.execute(params, 0);
        assertEq(assets, 0);
        assertEq(shares, 0);
        assertEq(ITestToken(USDS).balanceOf(address(seed)), beforeBalance - 1000);
    }

    function test_partialSeedOnlyTopsUp() public {
        deal(USDS, address(this), 1000);
        ITestToken(USDS).approve(MORPHO, 1000);
        IMorpho(MORPHO).supply(params, 0, 400_000_000, DEAD, "");
        (uint256 assets, uint256 shares) = seed.execute(params, 1000);
        assertEq(assets, 600);
        assertEq(shares, 600_000_000);
        seed.check(params);
    }

    function test_assetLimitRejectsBeforeSupply() public {
        vm.expectRevert("seed exceeds asset limit");
        seed.execute(params, 999);
        (uint256 shares,,) = IMorpho(MORPHO).position(id, DEAD);
        assertEq(shares, 0);
        assertEq(ITestToken(USDS).allowance(address(seed), MORPHO), 0);
    }

    function test_populatedMarketAccruesAndRoundsUp() public {
        deal(USDS, address(this), 100e18);
        ITestToken(USDS).approve(MORPHO, 100e18);
        IMorpho(MORPHO).supply(params, 100e18, 0, address(this), "");
        deal(params.collateralToken, address(this), 100e18);
        ITestToken(params.collateralToken).approve(MORPHO, 100e18);
        IBorrowMorpho(MORPHO).supplyCollateral(params, 100e18, address(this), "");
        IBorrowMorpho(MORPHO).borrow(params, 50e18, 0, address(this), address(this));
        vm.warp(block.timestamp + 30 days);
        (uint256 assets, uint256 shares) = seed.execute(params, 1e18);
        assertGt(assets, 1000, "must account for interest accrued on existing supply");
        assertEq(shares, 1e9);
        (uint128 totalAssets, uint128 totalShares,,,,) = IMorpho(MORPHO).market(id);
        uint256 numerator = 1e9 * (uint256(totalAssets) - assets + 1);
        uint256 denominator = uint256(totalShares) - shares + 1e6;
        assertEq(assets, (numerator + denominator - 1) / denominator);
        seed.check(params);
    }

    function test_rejectWrongLoanToken() public {
        params.loanToken = address(1);
        vm.expectRevert("unexpected market params");
        seed.execute(params, 1000);
    }

    function test_rejectUncreatedMarket() public {
        params.oracle = address(1);
        vm.expectRevert("market not created");
        seed.execute(params, 1000);
    }
}
