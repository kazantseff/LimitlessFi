pragma solidity ^0.8.20;

import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {Script} from "forge-std/Script.sol";
import "lib/solmate/src/tokens/ERC20.sol";

contract DeployMockV3Aggregator is Script {
    uint8 DECIMALS = 8;
    int256 INITIAL_PRICE = 2000e18;

    function run() external returns (MockV3Aggregator) {
        MockV3Aggregator priceFeed;
        vm.startBroadcast();
        priceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
        vm.stopBroadcast();
        return priceFeed;
    }
}
