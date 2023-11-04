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

    LimitlessMarket private market;
    uint256 public maxUtilizationPercentage;
    uint256 public totalLiquidityDeposited;

    // Underlying will be USDC
    constructor(
        ERC20 _underlying
    ) ERC4626(_underlying, "LimitlessToken", "LMTLS") {}

    function totalAssets() public view override returns (uint256) {
        int256 balanceOfVault = totalLiquidityDeposited.toInt256();
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
        totalLiquidityDeposited += assets;
        shares = super.deposit(assets, receiver);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        assets = super.redeem(shares, receiver, owner);
        totalLiquidityDeposited -= assets;
        // This check enusures that after withdrawal (totalOpenInterest < (depositedLiquidity * utilizationPercentage))
        require(
            market._ensureLiquidityReserves(),
            "Cannot withdraw liquidity reserved for positions"
        );
    }

    function setUtilizationPercentage(uint256 utilizationRate) external {
        maxUtilizationPercentage = utilizationRate;
    }

    function setMarket(address _market) external {
        market = LimitlessMarket(_market);
    }
}
