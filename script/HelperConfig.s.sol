// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint8 private constant WETH_DECIMALS = 8;
    uint8 private constant WBTC_DECIMALS = 8;
    int256 private constant WETH_INITIAL_PRICE = int256(2000 * 10 ** WETH_DECIMALS);
    int256 private constant WBTC_INITIAL_PRICE = int256(30000 * 10 ** WBTC_DECIMALS);

    uint256 private constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeConfig;

    error HelperConfig__UnsupportedNetwork();

    constructor() {
        if (block.chainid == 31337) {
            activeConfig = createAndGetAnvilConfig();
        } else if (block.chainid == 11155111) {
            activeConfig = getSepoliaConfig();
        } else {
            revert HelperConfig__UnsupportedNetwork();
        }
    }

    function getSepoliaConfig() internal view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function createAndGetAnvilConfig() internal returns (NetworkConfig memory) {
        if (activeConfig.deployerKey != 0) {
            return activeConfig;
        }

        vm.startBroadcast(ANVIL_DEFAULT_KEY);
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(WETH_DECIMALS, WETH_INITIAL_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(WBTC_DECIMALS, WBTC_INITIAL_PRICE);
        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerKey: ANVIL_DEFAULT_KEY
        });
    }
}
