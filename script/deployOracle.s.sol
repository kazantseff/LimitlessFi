pragma solidity ^0.8.20;

import {EthUsdOracle} from "../src/oracle/ethUsdOracle.sol";
import {Script} from "forge-std/Script.sol";
import {DeployMockV3Aggregator} from "./mocks/deployMockV3Aggregator.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract DeployOracle is Script {
    function run() external returns (EthUsdOracle) {
        DeployMockV3Aggregator mockDeployer = new DeployMockV3Aggregator();
        MockV3Aggregator priceFeed = mockDeployer.run();

        EthUsdOracle oracle;
        vm.startBroadcast();
        oracle = new EthUsdOracle(priceFeed);
        vm.stopBroadcast();
        return oracle;
    }
}
