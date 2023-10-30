// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "lib/solmate/src/mixins/ERC4626.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LimitlessMarket} from "../market/Market.sol";

error ProtocolInsolvent();

// #TODO: Need to implement access control

contract Vault is ERC4626 {
    using SafeTransferLib for ERC20;
    using SafeCast for uint;
    using SafeCast for int;

    LimitlessMarket private immutable market;
    uint256 public maxUtilizationPercentage;

    // Underlying will be USDC
    constructor(
        ERC20 _underlying,
        address _market
    ) ERC4626(_underlying, "LimitlessToken", "LMTLS") {
        market = LimitlessMarket(_market);
    }

    function totalAssets() public view override returns (uint256) {
        int256 balanceOfVault = ERC20(asset)
            .balanceOf(address(this))
            .toInt256();
        // Pnl can be negative, but totalAssets should be at least 0
        int256 _totalAssets = balanceOfVault - market._calculateProtocolPnl();
        if (_totalAssets < 0) revert ProtocolInsolvent();
        return _totalAssets.toUint256();
    }

    // Deposit
    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");
        // Calculate totalOpenInterest
        uint256 totalOpenInterest = market.openInterestUSDShort() +
            market.openInterestUSDLong();
        // Liquidity withdrawn cannot be greater than liquidity that is used for positions
        require(
            assets < totalOpenInterest,
            "Cannot withdraw liquidity that is reserved for positions"
        );

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function setUtilizationPercentage(uint256 utilizationRate) external {
        maxUtilizationPercentage = utilizationRate;
    }
}
