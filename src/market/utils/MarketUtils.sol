// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../../lib/SafeMath.sol";
import "solmate/tokens/ERC20.sol";
import "../MarketStorage.sol";

contract MarketUtils is MarketStorage {
    using SafeCast for int;
    using SafeCast for uint;
    using Math for uint;
    using SafeMath for uint;
    using SignedMath for int;
    using SafeTransferLib for ERC20;

    function _calculateLeverage(
        uint256 size,
        uint256 collateral
    ) internal view returns (uint256) {
        // Get the price from oracle
        int256 price = oracle.getPrice();
        uint256 leverage = price.toUint256().mulDiv(
            size,
            collateral *
                1e10 /* collateral is usdc so we need to scale up decimals */
        );
        return leverage / 1e18;
    }

    function _checkLeverage(
        uint256 size,
        uint256 collateral
    ) internal view returns (bool) {
        uint256 leverage = _calculateLeverage(size, collateral);
        return leverage < maxLeverage;
    }

    /** @notice Calculates total Pnl of the protocol
     * @return Will return positive value if the traders are in profit
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
        int256 price = oracle.getPrice();
        int256 currentValue = price * position.size.toInt256();
        int256 entryValue = position.averagePrice.toInt256() *
            position.size.toInt256();
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
     * @param removeSize the amount of size to remove
     * @param isLiquidating flag to see if this is the liquidation
     */
    function _removeSize(
        Position memory _position,
        address _user,
        uint256 removeSize,
        bool isLiquidating
    ) internal returns (Position memory, uint256) {
        uint256 fee;
        uint256 price = oracle.getPrice().toUint256();
        int256 pnl = _calculateUserPnl(_user);
        // #TODO: Check precision loss
        int256 realizedPnl = (pnl * removeSize.toInt256()) /
            _position.size.toInt256();
        // If realizedPnl is negative, deduct it from the collateral
        if (realizedPnl < 0) {
            uint256 absolutePnl = realizedPnl.abs();
            // No need to check leverage as the amount of collateral decreased is proportional to amount of size decreased
            _position.collateral -= absolutePnl;
        } else {
            ERC20(collateralToken).safeTransfer(
                msg.sender,
                // Conversion here is safe, as realizedPnl is greater than 0
                realizedPnl.toUint256()
            );
        }
        _position.size -= removeSize;

        // Decrease open interest
        if (_position.isLong) {
            openInterstInUnderlyingLong -= removeSize;
            openInterestUSDLong += removeSize * price;
        } else {
            openInterstInUnderlyingShort -= removeSize;
            openInterestUSDShort -= removeSize * price;
        }

        // If size is decreased to 0, tclose the position
        if (_position.size == 0) {
            // Deduct the liquidation fee if needed
            if (isLiquidating) {
                fee = _getLiquidationFee(_position.collateral);
                _position.collateral -= fee;
            }
            ERC20(collateralToken).safeTransfer(
                msg.sender,
                _position.collateral
            );
            _position.collateral = 0;
        }

        return (_position, fee);
    }

    /** @notice Function to calculate the liquidation fee */
    function _getLiquidationFee(
        uint256 _collateral
    ) internal view returns (uint256) {
        return (_collateral * liquidationFeePercentage).div(MAXIMUM_BPS);
    }

    /** @notice Calculates interest on the position of the trader until block.timestamp
     * @return borrowingFee in index token (ETH)
     */
    function _calculateInterest(
        uint256 size,
        uint256 lastAccruedTimeStamp
    ) internal view returns (uint256) {
        // BorrowingFee = positionSize * secondsSincePositionUpdated * feesPerSharePerSecond
        // feePerSharePerSecond = 1 / 315_360_000
        uint256 deltaTime = block.timestamp - lastAccruedTimeStamp;
        // Because feePerSharePerSecond was multiplied by 1e18, we need to divide final result by 1e18
        uint256 borrowingFee = (size *
            deltaTime *
            _getBorrowingPerSharePerSecond()) / SCALE_FACTOR;
        return borrowingFee;
    }

    /** @notice Function that accrues interest on position and transfers fees to the vault */
    function _accrueInterest(
        Position memory _position
    ) internal returns (Position memory) {
        // calculate outstanding fees of the position in indexToken
        uint256 borrowingFee = _calculateInterest(
            _position.size,
            _position.lastTimestampAccrued
        );
        uint256 price = oracle.getPrice().toUint256();
        // As borrowingFee is in indexToken, there is a need to convert it to USDC
        uint256 borrowingFeesInCollateralScaled = (borrowingFee * price) / 1e10;
        _position.lastTimestampAccrued = block.timestamp;
        _position.collateral -= borrowingFeesInCollateralScaled * 1e10;
        // Approve vault
        ERC20(collateralToken).approve(
            address(vault),
            borrowingFeesInCollateralScaled
        );
        // Deposit fees into vault
        vault.depositBorrowingFees(borrowingFeesInCollateralScaled);
        return _position;
    }

    /** @notice Return borrowingFeePerSharePerSecond */
    // feePerSharePerSecond is 1 / 315_360_000
    // So we multiply by 1e18 => 1e18 / 315_360_000
    function _getBorrowingPerSharePerSecond() internal pure returns (uint256) {
        // Approximately 3.17e9
        // It give 10% rate per year
        return SCALE_FACTOR / (SECONDS_IN_YEAR * 10);
    }

    // Liquidity reserves are calculated (depositedLiquidity * maxUtilizationPercentage)
    function _calculateLiquidityReserves() internal view returns (uint256) {
        // Liquidity is in 1e8 precisions, need to scale it up
        uint256 depositedLiquidity = vault.totalUnderlyingDeposited();
        // utilizationPercentage is denominated in BPS
        uint256 reserves = (depositedLiquidity *
            vault.maxUtilizationPercentage()) / MAXIMUM_BPS;
        return reserves * 1e10;
    }

    // shortOpenInterstUSD + (longOpenInterestTokens * price) < (depositedLiquidity * utilizationPercentage)
    function _ensureLiquidityReserves() public view returns (bool) {
        uint256 price = oracle.getPrice().toUint256();
        if (
            openInterestUSDShort +
                ((openInterstInUnderlyingLong * price) / SCALE_FACTOR) <
            _calculateLiquidityReserves()
        ) {
            return true;
        } else {
            return false;
        }
    }
}
