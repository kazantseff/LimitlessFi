pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "lib/solmate/src/tokens/ERC20.sol";
import {MockERC20} from "../../test/mocks/MockToken.sol";

contract DeployToken is Script {
    function run() external returns (MockERC20) {
        MockERC20 token;
        vm.startBroadcast();
        token = new MockERC20("USDCToken", "USDC", 10000000e18);
        vm.stopBroadcast();
        return token;
    }
}
