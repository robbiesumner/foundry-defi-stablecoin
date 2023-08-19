// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {StableCoin} from "../src/StableCoin.sol";

contract StableCoinTest is Test {
    StableCoin STBL;

    address DEPLOYER = makeAddr("engine");
    uint256 constant AMOUNT = 100;

    function setUp() external {
        vm.prank(DEPLOYER);
        STBL = new StableCoin();
    }

    /* Metadata */

    function testNameAndSymbol() external {
        assertEq(STBL.name(), "Stable Coin");
        assertEq(STBL.symbol(), "STBL");
    }

    function testDecimals() external {
        assertEq(STBL.decimals(), 18);
    }

    function testDeployerIsOwner() external {
        assertEq(STBL.owner(), DEPLOYER);
    }

    /* Mint */

    function testOwnerMint() external {
        vm.prank(DEPLOYER);
        STBL.mint(DEPLOYER, AMOUNT);
        assertEq(STBL.balanceOf(DEPLOYER), AMOUNT);
    }

    function testNotOwnerMintReverts() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(makeAddr("not owner"));
        STBL.mint(DEPLOYER, AMOUNT);
    }

    function testMintToZeroAddressReverts() external {
        vm.prank(DEPLOYER);
        vm.expectRevert(StableCoin.StableCoin__MintToZeroAddress.selector);
        STBL.mint(address(0), AMOUNT);
    }

    function testMintZeroAmountReverts() external {
        vm.prank(DEPLOYER);
        vm.expectRevert(StableCoin.StableCoin__AmountZero.selector);
        STBL.mint(DEPLOYER, 0);
    }

    /* Burn */

    function testOwnerBurn() external {
        vm.startPrank(DEPLOYER);
        STBL.mint(DEPLOYER, AMOUNT);
        STBL.burn(AMOUNT);
        vm.stopPrank();

        assertEq(STBL.balanceOf(DEPLOYER), 0);
    }

    function testNotOwnerBurnReverts() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(makeAddr("not owner"));
        STBL.burn(AMOUNT);
    }

    function testBurnZeroAmountReverts() external {
        vm.prank(DEPLOYER);
        vm.expectRevert(StableCoin.StableCoin__AmountZero.selector);
        STBL.burn(0);
    }
}
