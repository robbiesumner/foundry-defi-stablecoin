// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {STBLEngine} from "../src/STBLEngine.sol";
import {StableCoin} from "../src/StableCoin.sol";

contract DeploySTBL is Script {
    address[] tokens;
    address[] priceFeeds;

    function run() external returns (StableCoin stbl, STBLEngine stblEngine, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeConfig();
        tokens = [weth, wbtc];
        priceFeeds = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        stblEngine = new STBLEngine(tokens, priceFeeds);
        stbl = StableCoin(stblEngine.getStblAddress());
        vm.stopBroadcast();
    }
}
