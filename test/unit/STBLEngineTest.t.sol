// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeploySTBL} from "../../script/DeploySTBL.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {STBLEngine} from "../../src/STBLEngine.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract STBLEngineTest is Test {
    /* Events */
    event CollateralDeposit(address indexed user, address indexed token, uint256 amount);

    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;
    address unallowedToken;

    StableCoin stbl;
    STBLEngine stblEngine;

    address USER = makeAddr("user");
    uint256 constant STARTING_BALANCE = 1000;
    uint256 constant DEPOSIT = 100;

    function setUp() external {
        DeploySTBL deployer = new DeploySTBL();

        HelperConfig helperConfig;
        (stbl, stblEngine, helperConfig) = deployer.run();
        (wethPriceFeed, wbtcPriceFeed, weth, wbtc,) = helperConfig.activeConfig();

        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
        unallowedToken = address(new ERC20Mock());
    }

    /* Deposit */

    function testUserCannotDepositZeroCollateral() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), DEPOSIT);
        vm.expectRevert(STBLEngine.STBLEngine__AmountZero.selector);
        stblEngine.deposit(weth, 0);
    }

    function testUserCannotDepositUnallowedTokens() external {
        vm.expectRevert(abi.encodeWithSelector(STBLEngine.STBLEngine__TokenNotAllowed.selector, unallowedToken));
        vm.prank(USER);
        stblEngine.deposit(unallowedToken, DEPOSIT);
    }

    function testDepositEmitsEvent() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), DEPOSIT);
        vm.expectEmit(true, true, false, true, address(stblEngine));
        emit CollateralDeposit(USER, weth, DEPOSIT);
        stblEngine.deposit(weth, DEPOSIT);
        vm.stopPrank();
    }

    function testDepositTransfersERC20Token() external {
        vm.startPrank(USER);
        IERC20(weth).approve(address(stblEngine), DEPOSIT);
        stblEngine.deposit(weth, DEPOSIT);
        vm.stopPrank();

        assertEq(IERC20(weth).balanceOf(USER), STARTING_BALANCE - DEPOSIT);
        assertEq(IERC20(weth).balanceOf(address(stblEngine)), DEPOSIT);
    }

    function testDepositRevertsOnERC20TransferFail() external {
        vm.expectRevert();
        vm.prank(USER);
        // IERC20(weth).approve(address(stblEngine), DEPOSIT); // without this the erc20 transfer will fail
        stblEngine.deposit(weth, DEPOSIT);
    }
}
