pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Vault} from "../src/vault/Vault.sol";
import {MockERC20} from "../test/mocks/MockToken.sol";
import "lib/solmate/src/tokens/ERC20.sol";

contract DeployVault is Script {
    function run(MockERC20 token) public returns (Vault) {
        vm.startBroadcast();
        Vault vault = new Vault(token);
        vm.stopBroadcast();
        return vault;
    }
}
