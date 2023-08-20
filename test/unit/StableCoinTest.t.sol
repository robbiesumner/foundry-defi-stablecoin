// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {StableCoin} from "../../src/StableCoin.sol";

contract StableCoinTest is Test {
    StableCoin stbl;

    address DEPLOYER = makeAddr("engine");
    uint256 constant AMOUNT = 100;

    function setUp() external {
        vm.prank(DEPLOYER);
        stbl = new StableCoin();
    }

    /* Metadata */

    function testNameAndSymbol() external {
        assertEq(stbl.name(), "Stable Coin");
        assertEq(stbl.symbol(), "STBL");
    }

    function testDecimals() external {
        assertEq(stbl.decimals(), 18);
    }

    function testDeployerIsOwner() external {
        assertEq(stbl.owner(), DEPLOYER);
    }

    /* Mint */

    function testOwnerMint() external {
        vm.prank(DEPLOYER);
        stbl.mint(DEPLOYER, AMOUNT);
        assertEq(stbl.balanceOf(DEPLOYER), AMOUNT);
    }

    function testNotOwnerMintReverts() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(makeAddr("not owner"));
        stbl.mint(DEPLOYER, AMOUNT);
    }

    function testMintToZeroAddressReverts() external {
        vm.prank(DEPLOYER);
        vm.expectRevert(StableCoin.StableCoin__MintToZeroAddress.selector);
        stbl.mint(address(0), AMOUNT);
    }

    function testMintZeroAmountReverts() external {
        vm.prank(DEPLOYER);
        vm.expectRevert(StableCoin.StableCoin__AmountZero.selector);
        stbl.mint(DEPLOYER, 0);
    }

    /* Burn */

    function testOwnerBurn() external {
        vm.startPrank(DEPLOYER);
        stbl.mint(DEPLOYER, AMOUNT);
        stbl.burn(AMOUNT);
        vm.stopPrank();

        assertEq(stbl.balanceOf(DEPLOYER), 0);
    }

    function testNotOwnerBurnReverts() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(makeAddr("not owner"));
        stbl.burn(AMOUNT);
    }

    function testBurnZeroAmountReverts() external {
        vm.prank(DEPLOYER);
        vm.expectRevert(StableCoin.StableCoin__AmountZero.selector);
        stbl.burn(0);
    }
}
