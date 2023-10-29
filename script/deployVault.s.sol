pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Vault} from "../src/vault/Vault.sol";
import "lib/solmate/src/tokens/ERC20.sol";

contract DeployVault is Script {
    address token = makeAddr("token");

    function run() public {
        vm.startBroadcast();
        new Vault(ERC20(token));
        vm.stopBroadcast();
    }
}
