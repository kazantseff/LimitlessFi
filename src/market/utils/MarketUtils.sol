// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** @notice Math libraries */
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "../../lib/SafeMath.sol";

/** @notice Solmate ERC20, SafeTransferLib */
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/** @notice OpenZeppelin Utils */
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/** @notice Storage contract of market */
import "../MarketStorage.sol";

contract MarketUtils is MarketStorage {
    using SafeCast for int;
    using SafeCast for uint;
    using Math for uint;
    using SafeMath for uint;
    using SignedMath for int;
    using SafeTransferLib for ERC20;

    /** @notice Returns totalOpenInterest in the market */
    function _totalOpenInterest() public view returns (uint256) {
        uint256 price = oracle.getPrice().toUint256();
        return
            openInterestUSDShort +
            (openInterstInUnderlyingLong * price) /
            SCALE_FACTOR;
    }

    /** @notice Checks if open interest does not exceed liquidity reserves
     * @return True if it does not exceeds reserves, false otherwise
     */
    function _ensureLiquidityReserves() public view returns (bool) {
        if (_totalOpenInterest() < _calculateLiquidityReserves()) {
            return true;
        } else {
            return false;
        }
        /** @notice Calculates total PnL of all traders
         * @return PnL Positive if traders are making money or negative if traders are losing money
         */
    }

    function _calculateTradersPnl() external view returns (int256) {
        int256 price = oracle.getPrice();
        int256 pnlLongs = ((price * openInterstInUnderlyingLong.toInt256()) /
            int256(SCALE_FACTOR)) - openInterestUSDLong.toInt256();
        int256 pnlShorts = openInterestUSDShort.toInt256() -
            ((price * openInterstInUnderlyingShort.toInt256()) /
                int256(SCALE_FACTOR));
        return pnlLongs + pnlShorts;
    }

    /** @notice Calculates user PnL
     * @param _user User whose profit to calculate
     * @return PnL Positive if user is making money or negative if user is losing money
     */
    function _calculateUserPnl(address _user) public view returns (int256) {
        Position memory position = userPosition[_user];

        int256 price = oracle.getPrice();
        int256 currentValue = (price * position.size.toInt256()) /
            int256(SCALE_FACTOR);
        int256 entryValue = (position.averagePrice.toInt256() *
            position.size.toInt256()) / int256(SCALE_FACTOR);

        if (position.isLong) {
            return currentValue - entryValue;
        } else {
            return entryValue - currentValue;
        }
    }

    /** @notice Converts a uint256 from one fixed point decimal basis to another
     * @param amountToConvert The amount being converted
     * @param decimalsFrom The fixed decimals basis of amountToConvert
     * @param decimalsTo The fixed decimal basis of the returned convertedAmount
     * @return convertedAmount The amount after conversion
     */
    function _convertDecimals(
        uint8 decimalsFrom,
        uint8 decimalsTo,
        uint256 amountToConvert
    ) internal pure returns (uint256 convertedAmount) {
        if (decimalsFrom == decimalsTo) {
            convertedAmount = amountToConvert;
        } else if (decimalsFrom < decimalsTo) {
            uint256 shift = 10 ** (uint256(decimalsTo - decimalsFrom));
            convertedAmount = amountToConvert * shift;
        } else {
            uint256 shift = 10 ** (uint256(decimalsFrom - decimalsTo));
            convertedAmount = amountToConvert / shift;
        }
    }

    /** @notice Calculates leverage of the position with given size and collateral
     * @param size The size of the position
     * @param collateral The collateral of the position
     * @return Leverage of the position
     */
    function _calculateLeverage(
        uint256 size,
        uint256 collateral
    ) internal view returns (uint256) {
        // Get the price from oracle
        int256 price = oracle.getPrice();
        uint256 leverage = price.toUint256().mulDiv(size, collateral);
        return leverage / SCALE_FACTOR;
    }

    /** @notice Checks if leverage of the position exceeds max allowed leverage
     * @param size The size of the position
     * @param collateral The size of the collateral
     * @return True if position does not exceed maxLeverage and False if position exceeds maxLeverage
     */
    function _checkLeverage(
        uint256 size,
        uint256 collateral
    ) internal view returns (bool) {
        uint256 leverage = _calculateLeverage(size, collateral);
        return leverage <= maxLeverage;
    }

    /** @notice Determines if a user can be liquidated
     * @param user User whose positions is being checked
     * @return True if a user can be liquidated, false otherwise
     */
    function _isLiquidatable(address user) internal view returns (bool) {
        Position memory position = userPosition[user];
        int256 userPnl = _calculateUserPnl(user);

        if (userPnl < 0) {
            position.collateral -= userPnl.abs();
            return !_checkLeverage(position.size, position.collateral);
        } else {
            position.collateral += userPnl.toUint256();
            return !_checkLeverage(position.size, position.collateral);
        }
    }

    /** @notice Removes size of the position and realizes PnL
     * @param _position Position to operate on
     * @param _user User whose position is being decreased
     * @param removeSize Amount of size to remove
     * @param isLiquidating Flag to see if this is liquidation
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
        int256 realizedPnl = (pnl * removeSize.toInt256()) /
            _position.size.toInt256();
        // If realizedPnl is negative, deduct it from the collateral
        // @audit-issue When realizing PNL it should go to LP's?
        // @audit-issue It's definetely should be accounted for somehow, rn it's unaccounted for
        if (realizedPnl < 0) {
            // Collateral is in 8 decimals of precisions
            uint256 absolutePnl = realizedPnl.abs();
            // No need to check leverage as the amount of collateral decreased is proportional to amount of size decreased
            _position.collateral -= absolutePnl;
        } else {
            // @audit-issue Here also, the transfer should be from Vault, as it's where the LP's money are sitting
            // @audit Maybe it's fine, just add a check if there is not enough tokens in market, request additional tokens from vault
            uint256 scaledPnl = _convertDecimals(
                18,
                ERC20(collateralToken).decimals(),
                realizedPnl.toUint256()
            );

            ERC20(collateralToken).safeTransfer(_user, scaledPnl);
        }
        _position.size -= removeSize;

        // Decrease open interest
        if (_position.isLong) {
            openInterstInUnderlyingLong -= removeSize;
            openInterestUSDLong -= (removeSize * price) / SCALE_FACTOR;
        } else {
            openInterstInUnderlyingShort -= removeSize;
            openInterestUSDShort -= (removeSize * price) / SCALE_FACTOR;
        }

        // If size is decreased to 0, close the position
        if (_position.size == 0) {
            // Deduct the liquidation fee if needed
            if (isLiquidating) {
                fee = _getLiquidationFee(_position.collateral);
                _position.collateral -= fee;
            }
            uint256 scaledCollateral = _convertDecimals(
                18,
                ERC20(collateralToken).decimals(),
                _position.collateral
            );
            ERC20(collateralToken).safeTransfer(_user, scaledCollateral);
            _position.collateral = 0;
        }

        return (_position, fee);
    }

    /** @notice Calculates the liquidation fee
     * @param _collateral Collateral of the position
     * @return Liquidation fee
     */
    function _getLiquidationFee(
        uint256 _collateral
    ) internal view returns (uint256) {
        return (_collateral * liquidationFeePercentage) / (MAXIMUM_BPS);
    }

    /** @notice Calculates interest on the position of the trader until block.timestamp
     * @dev borrowingFee = positionSize * secondsSincePositionLastUpdate * feesPerSharePerSecond
     * @dev Since feesPerSharePerSecond is scaled with SCALE_FACTORT, we need to divied final result by SCALE_FACTOR
     * @param size Size of the position
     * @param lastAccruedTimeStamp Timestamp of last accrual of the interest
     * @return borrowingFee in index token
     */
    function _calculateInterest(
        uint256 size,
        uint256 lastAccruedTimeStamp
    ) internal view returns (uint256) {
        uint256 deltaTime = block.timestamp - lastAccruedTimeStamp;
        uint256 borrowingFee = (size *
            deltaTime *
            _getBorrowingPerSharePerSecond()) / SCALE_FACTOR;
        return borrowingFee;
    }

    /** @notice Accrues interest on position based on the size
     * @notice Transfers fee to the Vault
     * @param _position Position to accrue interest on
     * @return Position with updated collateral
     */
    function _accrueInterest(
        Position memory _position
    ) internal returns (Position memory) {
        uint256 borrowingFee = _calculateInterest(
            _position.size,
            _position.lastTimestampAccrued
        );
        uint256 price = oracle.getPrice().toUint256();
        uint256 borrowingFeesInCollateral = (borrowingFee * price) /
            SCALE_FACTOR;
        uint256 borrowingFeesScaled = _convertDecimals(
            18,
            ERC20(collateralToken).decimals(),
            borrowingFeesInCollateral
        );

        _position.lastTimestampAccrued = block.timestamp;
        _position.collateral -= borrowingFeesInCollateral;

        ERC20(collateralToken).approve(address(vault), borrowingFeesScaled);
        vault.depositBorrowingFees(borrowingFeesScaled);
        return _position;
    }

    /** @notice Return borrowingFeePerSharePerSecond
     * @notice Gives approximately 10% interest over the course of the year
     * @return 1e18 / 315_360_000
     */
    function _getBorrowingPerSharePerSecond() internal pure returns (uint256) {
        return SCALE_FACTOR / (SECONDS_IN_YEAR * 10);
    }

    /** @notice Calculates liquidity reserves of the protocol
     * @return Liquidity reserves in 18 decimals of precision
     */
    function _calculateLiquidityReserves() internal view returns (uint256) {
        uint256 depositedLiquidity = vault.totalUnderlyingDeposited();
        uint256 reserves = (depositedLiquidity *
            vault.maxUtilizationPercentage()) / MAXIMUM_BPS;
        uint256 scaledReserves = _convertDecimals(
            ERC20(collateralToken).decimals(),
            18,
            reserves
        );
        return scaledReserves;
    }
}
