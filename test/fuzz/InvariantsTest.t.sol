// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {DeploySTBL} from "../../script/DeploySTBL.s.sol";
import {STBLEngine} from "../../src/STBLEngine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantsTest is StdInvariant, Test {
    STBLEngine stblEngine;
    StableCoin stbl;
    HelperConfig config;

    address weth;
    address wbtc;

    function setUp() external {
        DeploySTBL deployer = new DeploySTBL();
        (stbl, stblEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeConfig();

        Handler handler = new Handler(stblEngine, stbl);
        targetContract(address(handler));
    }

    function invariant_contractMustHaveMoreValueThanTotalSupply() external {
        uint256 totalWethLocked = IERC20(weth).balanceOf(address(stblEngine));
        uint256 totalWbtcLocked = IERC20(wbtc).balanceOf(address(stblEngine));

        uint256 wethValue = stblEngine.getUsdValue(weth, totalWethLocked);
        uint256 wbtcValue = stblEngine.getUsdValue(wbtc, totalWbtcLocked);

        uint256 totalValueLocked = wethValue + wbtcValue;
        uint256 totalSupply = stbl.totalSupply();

        assertGe(totalValueLocked, totalSupply);
    }
}
