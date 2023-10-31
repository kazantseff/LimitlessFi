pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Vault} from "../src/vault/Vault.sol";
import {LimitlessMarket} from "../src/market/Market.sol";
import {EthUsdOracle} from "../src/oracle/ethUsdOracle.sol";
import {MockERC20} from "../test/mocks/MockToken.sol";
import {DeployOracle} from "./deployOracle.s.sol";
import {DeployVault} from "./deployVault.s.sol";
import {DeployToken} from "./mocks/deployTokenMock.s.sol";

contract DeployMarket is Script {
    function run()
        external
        returns (LimitlessMarket, Vault, MockERC20, EthUsdOracle)
    {
        DeployToken tokenDeployer = new DeployToken();
        DeployOracle oracleDeployer = new DeployOracle();
        DeployVault vaultDeployer = new DeployVault();

        MockERC20 token = tokenDeployer.run();
        Vault vault = vaultDeployer.run(token);
        EthUsdOracle oracle = oracleDeployer.run();

        vm.startBroadcast();
        LimitlessMarket market = new LimitlessMarket(
            address(token),
            address(oracle),
            address(vault)
        );
        vm.stopBroadcast();

        return (market, vault, token, oracle);
    }
}
