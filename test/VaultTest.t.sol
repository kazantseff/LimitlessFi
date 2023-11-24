// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "./shared/Test.sol";

contract VaultTest is Test {
    function setUp() public {
        deployVaultAndMarket();
        vm.prank(owner);
        vault.setUtilizationPercentage(8000);
    }

    function testDeposit() public {}
}
