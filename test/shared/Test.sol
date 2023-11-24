// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {console, console2, StdAssertions, StdChains, StdCheats, stdError, StdInvariant, stdJson, stdMath, StdStorage, stdStorage, StdUtils, Vm, StdStyle, DSTest, Test as ForgeTest} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {LimitlessVault} from "../../src/vault/Vault.sol";
import {LimitlessMarket} from "../../src/market/Market.sol";
import {MockERC20} from "../mocks/MockToken.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

// This is going to be the base contract for testing purposes
// Each test contract will be inheriting from this one, so there is no need to rewrite functions that are used multiple times
contract Test is ForgeTest {
    address internal owner = makeAddr("owner");
    MockERC20 internal usdc;
    MockV3Aggregator internal priceOracle;
    LimitlessVault internal vault;
    LimitlessMarket internal market;
    uint8 internal constant DECIMALS = 8;

    modifier asSelf() {
        vm.startPrank(address(this));
        _;
        vm.stopPrank();
    }

    constructor() {
        usdc = new MockERC20();
        // Deploy price oracle for ETH with 8 decimals, and 2000 as initial answer
        priceOracle = new MockV3Aggregator(DECIMALS, 2000e18);
    }

    function deployVault() internal asSelf {
        vault = new LimitlessVault(ERC20(usdc), owner);
    }

    function deployMarket() internal asSelf {
        market = new LimitlessMarket(
            address(usdc),
            address(priceOracle),
            address(vault),
            owner
        );
    }

    // Deploys vault with market, set market as a `market` in vault
    function deployVaultAndMarket() internal asSelf {
        deployVault();
        deployMarket();
        vm.prank(owner);
        vault.setMarket(address(market));
    }
}
