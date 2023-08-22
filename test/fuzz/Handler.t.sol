// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {STBLEngine} from "../../src/STBLEngine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    STBLEngine stblEngine;
    StableCoin stbl;

    address USER = makeAddr("user");
    uint256 constant STARTING_BALANCE = type(uint256).max;

    uint256 constant UPPER_BOUND = type(uint96).max;

    address[] tokens;

    constructor(STBLEngine _stblEngine, StableCoin _stbl) {
        stblEngine = _stblEngine;
        stbl = _stbl;

        tokens = stblEngine.getValidCollateralTokens();

        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20Mock(tokens[i]).mint(USER, STARTING_BALANCE);
        }
    }

    function deposit(uint256 collateralSeed, uint256 amountCollateral) external {
        address validCollateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, UPPER_BOUND); // not be zero

        vm.startPrank(USER);
        IERC20(validCollateral).approve(address(stblEngine), amountCollateral);
        stblEngine.deposit(validCollateral, amountCollateral);
        vm.stopPrank();
    }

    function withdraw(uint256 collateralSeed, uint256 amountCollateral) external {
        address validCollateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxAmountToWithdraw = stblEngine.getCollateralAmount(USER, validCollateral);
        if (maxAmountToWithdraw == 0) return; // nothing to withdraw

        amountCollateral = bound(amountCollateral, 1, maxAmountToWithdraw); // not be zero, but only withdraw what you have

        vm.startPrank(USER);
        stblEngine.withdraw(validCollateral, amountCollateral);
        vm.stopPrank();
    }

    function mint(uint256 amountStbl) external {
        amountStbl = bound(amountStbl, 1, UPPER_BOUND); // not be zero

        vm.startPrank(USER);
        stbl.mint(USER, amountStbl);
        vm.stopPrank();
    }

    /* Helper */
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (address) {
        uint256 index = collateralSeed % tokens.length;
        return tokens[index];
    }
}
