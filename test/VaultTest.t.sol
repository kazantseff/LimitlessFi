// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "./shared/Test.sol";
import {console2} from "forge-std/Test.sol";

contract VaultTest is Test {
    function setUp() public {
        deployVaultAndMarket();
        vm.prank(owner);
        vault.setUtilizationPercentage(8000);
    }

    function testFirstDeposit() public {
        _depositInVault(aliceDepositor, 10000e6);
        assertEq(10000e6, vault.totalUnderlyingDeposited());
        assertEq(10000e6, vault.totalSupply());
        assertEq(10000e6, vault.balanceOf(aliceDepositor));
        (uint256 userShares, , ) = vault.userToPosition(aliceDepositor);
        assertEq(10000e6, userShares);
        assertEq(10000e6, vault.totalShares());
    }

    function testNonFirstDeposit() public {
        _depositInVault(aliceDepositor, 10000e6);
        _depositInVault(bobDepositor, 3500e6);
        assertEq(13500e6, vault.totalUnderlyingDeposited());
        assertEq(13500e6, vault.totalSupply());
        assertEq(3500e6, vault.balanceOf(bobDepositor));
        (uint256 userShares, , ) = vault.userToPosition(bobDepositor);
        assertEq(3500e6, userShares);
        assertEq(13500e6, vault.totalShares());
    }

    function testRedeemHalfPosition() public {
        _depositInVault(aliceDepositor, 5000e6);
        vm.prank(aliceDepositor);
        vault.redeem(2500e6, aliceDepositor, aliceDepositor);
        assertEq(2500e6, vault.totalUnderlyingDeposited());
        assertEq(2500e6, vault.totalSupply());
        assertEq(2500e6, vault.balanceOf(aliceDepositor));
        (uint256 userShares, , ) = vault.userToPosition(aliceDepositor);
        assertEq(2500e6, userShares);
        assertEq(2500e6, vault.totalShares());
    }
}
