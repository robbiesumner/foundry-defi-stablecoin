// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeploySTBL} from "../../script/DeploySTBL.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {STBLEngine} from "../../src/STBLEngine.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";

contract STBLEngineTest is Test {
    /* Events */
    event CollateralDeposit(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawal(address indexed from, address indexed to, address indexed token, uint256 amount);

    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;
    address unallowedToken;

    StableCoin stbl;
    STBLEngine stblEngine;

    address USER = makeAddr("user");
    address LIQUIDATOR = makeAddr("liquidator");
    uint256 constant STARTING_BALANCE = 100e18;
    uint256 constant ETH_DEPOSIT = 10e18;
    uint256 constant STBL_MINT = 10000e18;
    int256 constant WORSE_PRICE = 1000e8;

    function setUp() external {
        DeploySTBL deployer = new DeploySTBL();

        HelperConfig helperConfig;
        (stbl, stblEngine, helperConfig) = deployer.run();
        (wethPriceFeed, wbtcPriceFeed, weth, wbtc,) = helperConfig.activeConfig();

        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
        unallowedToken = address(new ERC20Mock());
    }

    /* Constructor */

    address[] private tokens;
    address[] private priceFeeds;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeedLength() external {
        tokens.push(weth);
        priceFeeds.push(wethPriceFeed);
        priceFeeds.push(wbtcPriceFeed);
        vm.expectRevert(STBLEngine.STBLEngine__LengthOfTokensAndPriceFeedsDoNotMatch.selector);
        new STBLEngine(tokens, priceFeeds);
    }

    /* Price Feed */

    function testGetUsdValue() external {
        uint256 ethAmount = 15 ether;

        uint256 expectedUsd = 30000e18;
        uint256 usd = stblEngine.getUsdValue(weth, ethAmount);
        assertEq(usd, expectedUsd);
    }

    function testGetTokenValue() external {
        uint256 usdAmount = 30000 ether;

        uint256 expectedEth = 15 ether;
        uint256 eth = stblEngine.getTokenValue(weth, usdAmount);
        assertEq(eth, expectedEth);
    }

    function testGetCollateralValue() external collateralDeposited {
        uint256 expectedUsd = 20000e18;
        uint256 usd = stblEngine.getCollateralValue(USER);
        assertEq(usd, expectedUsd);
    }

    /* Deposit And Mint */
    function testDepositCollateralAndMintStbl() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), ETH_DEPOSIT);
        stblEngine.depositCollateralAndMintStbl(weth, ETH_DEPOSIT, STBL_MINT);
        vm.stopPrank();

        assertEq(stblEngine.getCollateralAmount(USER, weth), ETH_DEPOSIT);
        assertEq(IERC20(address(stbl)).balanceOf(USER), STBL_MINT);
    }

    /* Burn And Withdraw */
    function testBurnStblAndWithdrawCollateral() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), ETH_DEPOSIT);
        stblEngine.depositCollateralAndMintStbl(weth, ETH_DEPOSIT, STBL_MINT);
        vm.stopPrank();

        vm.startPrank(USER);
        stbl.approve(address(stblEngine), STBL_MINT);
        stblEngine.burnStblAndWithdrawCollateral(weth, STBL_MINT, ETH_DEPOSIT);
        vm.stopPrank();

        assertEq(stblEngine.getCollateralAmount(USER, weth), 0);
        assertEq(IERC20(address(stbl)).balanceOf(USER), 0);
    }

    /* Deposit */
    function testUserCannotDepositZeroCollateral() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), ETH_DEPOSIT);
        vm.expectRevert(STBLEngine.STBLEngine__AmountZero.selector);
        stblEngine.deposit(weth, 0);
    }

    function testUserCannotDepositUnallowedTokens() external {
        vm.expectRevert(abi.encodeWithSelector(STBLEngine.STBLEngine__TokenNotAllowed.selector, unallowedToken));
        vm.prank(USER);
        stblEngine.deposit(unallowedToken, ETH_DEPOSIT);
    }

    function testDepositEmitsEvent() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), ETH_DEPOSIT);
        vm.expectEmit(true, true, false, true, address(stblEngine));
        emit CollateralDeposit(USER, weth, ETH_DEPOSIT);
        stblEngine.deposit(weth, ETH_DEPOSIT);
        vm.stopPrank();
    }

    function testDepositTransfersERC20Token() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), ETH_DEPOSIT);
        stblEngine.deposit(weth, ETH_DEPOSIT);
        vm.stopPrank();

        assertEq(IERC20(weth).balanceOf(USER), STARTING_BALANCE - ETH_DEPOSIT);
        assertEq(IERC20(weth).balanceOf(address(stblEngine)), ETH_DEPOSIT);
    }

    function testDepositRevertsOnERC20TransferFail() external {
        vm.expectRevert();
        vm.prank(USER);
        // IERC20(weth).approve(address(stblEngine), DEPOSIT); // without this the erc20 transfer will fail
        stblEngine.deposit(weth, ETH_DEPOSIT);
    }

    modifier collateralDeposited() {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), ETH_DEPOSIT);
        stblEngine.deposit(weth, ETH_DEPOSIT);
        vm.stopPrank();
        _;
    }

    /* Mint */
    function testUserCannotMintZeroStbl() external collateralDeposited {
        vm.expectRevert(STBLEngine.STBLEngine__AmountZero.selector);
        vm.prank(USER);
        stblEngine.mintStbl(0);
    }

    function testMintTransfersStbl() external collateralDeposited {
        vm.prank(USER);
        stblEngine.mintStbl(STBL_MINT);

        assertEq(IERC20(address(stbl)).balanceOf(USER), STBL_MINT);
    }

    function testMintRevertsWhenNoDeposit() external {
        vm.expectRevert(STBLEngine.STBLEngine__BadHealthFactor.selector);
        vm.prank(USER);
        stblEngine.mintStbl(STBL_MINT);
    }

    modifier stblMinted() {
        vm.startPrank(USER);
        stblEngine.mintStbl(STBL_MINT);
        vm.stopPrank();
        _;
    }

    /* Withdraw */
    function testWithdrawRevertsWhenNoDeposit() external {
        vm.expectRevert();
        vm.prank(USER);
        stblEngine.withdraw(weth, ETH_DEPOSIT);
    }

    function testWithdrawZeroCollateralReverts() external collateralDeposited {
        vm.expectRevert(STBLEngine.STBLEngine__AmountZero.selector);
        vm.prank(USER);
        stblEngine.withdraw(weth, 0);
    }

    function testWithdrawRevertsOnBadHealthFactor() external collateralDeposited stblMinted {
        // arrrange: set new pricefeed value
        MockV3Aggregator(wethPriceFeed).updateAnswer(WORSE_PRICE);

        vm.expectRevert();
        vm.prank(USER);
        stblEngine.withdraw(weth, ETH_DEPOSIT);
    }

    function testWithdrawTransfersERC20Token() external collateralDeposited {
        vm.startPrank(USER);
        stblEngine.withdraw(weth, ETH_DEPOSIT);
        vm.stopPrank();

        assertEq(IERC20(weth).balanceOf(USER), STARTING_BALANCE);
    }

    function testWithdrawEmitsEvent() external collateralDeposited {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true, address(stblEngine));
        emit CollateralWithdrawal(USER, USER, weth, ETH_DEPOSIT);
        stblEngine.withdraw(weth, ETH_DEPOSIT);
        vm.stopPrank();
    }

    /* Burn */
    function testUserCannotBurnZeroStbl() external collateralDeposited stblMinted {
        vm.expectRevert(STBLEngine.STBLEngine__AmountZero.selector);
        vm.prank(USER);
        stblEngine.burnStbl(0);
    }

    function testBurnTransfersStbl() external collateralDeposited stblMinted {
        vm.startPrank(USER);
        stbl.approve(address(stblEngine), STBL_MINT);
        stblEngine.burnStbl(STBL_MINT);
        vm.stopPrank();

        assertEq(IERC20(address(stbl)).balanceOf(USER), 0);
    }

    /* Liquidate */
    modifier liquidatable() {
        // set bad price
        MockV3Aggregator(wethPriceFeed).updateAnswer(WORSE_PRICE);
        _;
    }

    function testLiquidateRevertsOnZero() external collateralDeposited stblMinted {
        vm.expectRevert(STBLEngine.STBLEngine__AmountZero.selector);
        vm.prank(LIQUIDATOR);
        stblEngine.liquidate(USER, weth, 0);
    }

    function testLiquidateRevertsOnGoodHealthFactor() external collateralDeposited stblMinted {
        vm.expectRevert(STBLEngine.STBLEngine__GoodHealthFactor.selector);
        vm.prank(LIQUIDATOR);
        stblEngine.liquidate(USER, weth, STBL_MINT);
    }

    function testLiquidateRevertsIfHealthFactorHasNotImproved() external collateralDeposited stblMinted liquidatable {
        uint256 collateralToCover = STARTING_BALANCE;
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(stblEngine), collateralToCover);
        uint256 debtToCover = 10 ether;
        stblEngine.depositCollateralAndMintStbl(weth, collateralToCover, STBL_MINT);
        stbl.approve(address(stblEngine), debtToCover);
        // Act
        MockV3Aggregator(wethPriceFeed).updateAnswer(WORSE_PRICE);
        // Act/Assert
        vm.expectRevert(STBLEngine.STBLEngine__HealthFactorNotImproved.selector);
        stblEngine.liquidate(USER, weth, debtToCover);
        vm.stopPrank();

        assertEq(IERC20(address(stbl)).balanceOf(LIQUIDATOR), STBL_MINT);
    }
}
