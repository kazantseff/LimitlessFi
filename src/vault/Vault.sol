// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "lib/solmate/src/mixins/ERC4626.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

// In order to calculate totalAssets we need to substract totalPnlOfTraders from the amount deposited
// Because if PNl is positive, meaning there is less assets in the vault
// Or pnl is negative, meaning there are more assets in the vault (because they are taken from traders)

contract Vault is ERC4626 {
    using SafeTransferLib for ERC20;

    // Underlying will be ETH
    constructor(
        ERC20 _underlying
    ) ERC4626(_underlying, "LimitlessToken", "LMTLS") {}

    // LpValue(totalAssets) = (totalDeposits (of underlying into the vault) - totalPnlOfTraders)

    // To calcultae totalPnl of traders
    // (price of ETH * totalOpenInterestInETH) - totalOpenInterest for LONGS
    // For shorts totalOpenInterest - (price of ETH * totalOpenInterstInETH)
    function totalAssets() public view override returns (uint256) {}

    // Deposit
    // Redeem
}
