// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../MarketStorage.sol";
import "solmate/tokens/ERC20.sol";

contract MarketUtils is MarketStorage {
    using SafeCast for int;
    using SafeCast for uint;
    using Math for uint;

    function _calculateLeverage(
        uint256 size,
        uint256 collateral
    ) internal view returns (uint256) {
        int256 price = oracle.getPrice();
        // Get the price from oracle
        uint256 leverage = price.toUint256().mulDiv(
            size,
            collateral *
                1e10 /* collateral is usdc so we need to scale up decimals */
        );
        return leverage;
    }

    function _checkLeverage(
        uint256 size,
        uint256 collateral
    ) internal view returns (bool) {
        uint256 leverage = _calculateLeverage(size, collateral);
        return leverage < maxLeverage;
    }

    /** @notice Calculates total Pnl of the protocol
     * @return Can return negative value, which means liquidity providers are losing money
     */
    function _calculateProtocolPnl() external view returns (int256) {
        int256 price = oracle.getPrice();
        //Calculating pnl of longs
        int256 pnlLongs = (price * openInterstInUnderlyingLong.toInt256()) -
            openInterestUSDLong.toInt256();
        // Calculating pnl of shorts
        int256 pnlShorts = openInterestUSDShort.toInt256() -
            (price * openInterstInUnderlyingShort.toInt256());

        return pnlLongs + pnlShorts;
    }

    function _calculateUserPnl(address _user) internal view returns (int256) {
        // It depends if the position is long or short
        Position memory position = userPosition[_user];
        uint256 price = oracle.getPrice().toUint256();
        int256 currentValue = price * position.size;
        int256 entryValue = position.averagePrice * position.size;
        if (position.isLong) {
            // For long
            // CurrentValue - EntryValue
            return currentValue - entryValue;
        } else {
            // For short
            // EntryValue - CurrentValue
            return entryValue - currentValue;
        }
    }

    /** @notice Function to remove size of the position and realize the pnl
     * @param _position The position to operate on
     * @param _user User whose position is being decreased
     * @param _removeSize the amount of size to remove
     * @param isLiquidation flag to see if this is the liquidation
     */
    function _removeSize(
        Position memory _position,
        address _user,
        uint256 _removeSize,
        bool isLiquidating
    ) internal returns (Position memory) {
        int256 pnl = _calculateUserPnl(_user);
        int256 realizedPnl = pnl.mulDiv(_removeSize, _position.size);
        // If realizedPnl is negative, deduct it from the collateral
        if (realizedPnl < 0) {
            uint256 absolutePnl = realizedPnl.abs();
            // No need to check leverage as the amount of collateral decreased is proportional to amount of size decreased
            _position.collateral -= absoultePnl;
        } else {
            ERC20(collateralToken).safeTransfer(msg.sender, realizedPnl);
        }
        _position.size -= _removeSize;
        // If size is decreased to 0, tclose the position
        if (_position.size == 0) {
            // Deduct the liquidation fee if needed
            if (isLiquidating) {
                _position.collateral -= liquidationFee;
            }
            ERC20(collateralToken).safeTransfer(
                msg.sender,
                _position.collateral
            );
            _position.collateral = 0;
        }
        return _position;
    }

    // Liquidity reserves are calculated (depositedLiquidity * maxUtilizationPercentage)
    function _calculateLiquidityReserves() internal view returns (uint256) {
        uint256 depositedLiquidity = vault.totalLiquidityDeposited();
        uint256 reserves = depositedLiquidity *
            vault.maxUtilizationPercentage();
        return reserves;
    }

    // shortOpenInterstUSD + (longOpenInterestTokens * price) < (depositedLiquidity * utilizationPercentage)
    function _ensureLiquidityReserves() public view returns (bool) {
        uint256 price = oracle.getPrice().toUint256();
        if (
            openInterestUSDShort + (openInterstInUnderlyingLong * price) <
            _calculateLiquidityReserves()
        ) {
            return true;
        } else {
            return false;
        }
    }
}
