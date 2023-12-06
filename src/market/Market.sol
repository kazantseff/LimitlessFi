// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** @notice Math Libraries */
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeMath} from "../lib/SafeMath.sol";

/** @notice OpenZeppelin Utils */
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/** @notice Solmate ERC20, SafeTransferLib */
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/** @notice LimitlessFi related imports */
import {MarketUtils} from "./utils/MarketUtils.sol";
import {LimitlessVault} from "../vault/Vault.sol";
import "./MarketStorage.sol";

contract LimitlessMarket is Ownable, MarketStorage, MarketUtils {
    using SafeCast for int;
    using SafeMath for uint;
    using SignedMath for int;
    using SafeTransferLib for ERC20;

    /** @notice Initializes collateral token, oracle and vault */
    constructor(
        address _collateralToken,
        address _oracle,
        address _vault,
        address _owner
    ) Ownable(_owner) {
        collateralToken = _collateralToken;
        oracle = EthUsdOracle(_oracle);
        vault = LimitlessVault(_vault);
    }

    /** @notice Opens a position for msg.sender
     * @param collateral amount of collateral in USDC
     * @param size Size of the position in index token
     * @param isLong Type of the position
     */
    function openPosition(
        uint256 size,
        uint256 collateral,
        bool isLong
    ) external {
        if (size < minimumPositionSize) revert InvalidPositionSize();

        uint256 scaledCollateral = _convertDecimals(
            ERC20(collateralToken).decimals(),
            BASE_DECIMALS,
            collateral
        );
        if (!_checkLeverage(size, scaledCollateral))
            revert PositionExceedsMaxLeverage();

        Position memory position = userPosition[msg.sender];
        require(position.size == 0, "Position is already open");

        uint256 price = oracle.getPrice().toUint256();
        if (isLong) {
            openInterestUSDLong += (size * price) / SCALE_FACTOR;
            openInterstInUnderlyingLong += size;
        } else {
            openInterestUSDShort += (size * price) / SCALE_FACTOR;
            openInterstInUnderlyingShort += size;
        }

        position.size = size;
        position.collateral = scaledCollateral;
        position.averagePrice = price;
        position.isLong = isLong;
        position.lastTimestampAccrued = block.timestamp;

        userPosition[msg.sender] = position;

        ERC20(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateral
        );
        if (!_ensureLiquidityReserves()) revert NotEnoughLiquidity();

        emit PositionOpened(msg.sender, size, collateral, isLong);
    }

    /** @notice Increases size and/or collateral of the position
     * @param addSize Amount of size to add
     * @param addCollateral Amount of collateral to add
     */
    function increasePosition(uint256 addSize, uint256 addCollateral) external {
        Position memory position = userPosition[msg.sender];
        if (position.size == 0 || position.collateral == 0)
            revert PositionNotOpen();

        position = _accrueInterest(position);

        uint256 price = oracle.getPrice().toUint256();
        if (addCollateral > 0) {
            ERC20(collateralToken).safeTransferFrom(
                msg.sender,
                address(this),
                addCollateral
            );

            uint256 scaledCollateral = _convertDecimals(
                ERC20(collateralToken).decimals(),
                BASE_DECIMALS,
                addCollateral
            );
            position.collateral += scaledCollateral;
        }

        if (addSize > 0) {
            uint256 oldSize = position.size;
            position.size += addSize;
            if (!_checkLeverage(position.size, position.collateral))
                revert PositionExceedsMaxLeverage();

            if (position.isLong) {
                openInterstInUnderlyingLong += addSize;
                openInterestUSDLong += (addSize * price) / SCALE_FACTOR;
            } else {
                openInterstInUnderlyingShort += addSize;
                openInterestUSDShort += (addSize * price) / SCALE_FACTOR;
            }

            uint256 totalCostEntry1 = (position.averagePrice * oldSize) /
                SCALE_FACTOR;
            uint256 totalCostEntry2 = (price * addSize) / SCALE_FACTOR;
            uint256 averagePrice = (totalCostEntry1 + totalCostEntry2).div(
                oldSize + addSize
            ) * SCALE_FACTOR;
            position.averagePrice = averagePrice;
        }

        userPosition[msg.sender] = position;

        if (!_ensureLiquidityReserves()) revert NotEnoughLiquidity();

        emit PositionIncreased(msg.sender, addSize, addCollateral);
    }

    /** @notice Decreases size and/or collateral of the position
     * @param removeSize Amount of size to remove
     * @param removeCollateral Amount of collateral to remove
     */
    function decreasePosition(
        uint256 removeSize,
        uint256 removeCollateral
    ) external {
        Position memory position = userPosition[msg.sender];
        if (position.size == 0 || position.collateral == 0)
            revert PositionNotOpen();

        position = _accrueInterest(position);

        if (removeSize > 0) {
            // Remove size and realize pnl
            (position, ) = _removeSize(position, msg.sender, removeSize, false);
            userPosition[msg.sender] = position;
            // It is possible to close a position by removing all of the size => thus this check
            if (position.collateral == 0 && position.size == 0) {
                emit PositionClosed(msg.sender);
                return;
            }
        }

        if (removeCollateral > 0) {
            uint256 scaledCollateral = _convertDecimals(
                ERC20(collateralToken).decimals(),
                BASE_DECIMALS,
                removeCollateral
            );
            position.collateral -= scaledCollateral;
            ERC20(collateralToken).safeTransfer(msg.sender, removeCollateral);
            // To avoid divison by zero in _checkLeverage, handle the case where collateral is decreased to 0
            if (position.collateral == 0) {
                revert PositionExceedsMaxLeverage();
            } else {
                if (!_checkLeverage(position.size, position.collateral))
                    revert PositionExceedsMaxLeverage();
            }
            userPosition[msg.sender] = position;
        }

        emit PositionDecreased(msg.sender, removeSize, removeCollateral);
    }

    /** @notice Liquidates a user, implies a liquidation fee based on the collateral of the position
     * @param user User to liquidate
     */
    function liquidate(address user) external {
        Position memory position = userPosition[user];
        uint256 liquidationFee;
        if (!_isLiquidatable(user)) revert PositionNotLiquidatable();
        position = _accrueInterest(position);

        uint256 removeSize = position.size;

        (position, liquidationFee) = _removeSize(
            position,
            user,
            removeSize,
            true
        );
        uint256 scaledFee = _convertDecimals(
            BASE_DECIMALS,
            ERC20(collateralToken).decimals(),
            liquidationFee
        );
        userPosition[user] = position;
        // Transfer liquidation fee to liquidator
        ERC20(collateralToken).safeTransfer(msg.sender, scaledFee);

        emit PositionLiquidated(user);
    }

    /** @notice Minimum position size in index token */
    function setMinimumPositionSize(uint256 size) external onlyOwner {
        minimumPositionSize = size;
    }

    /** @notice maxLeverage is used without decimals */
    function setMaxLeverage(uint256 _maxLeverage) external onlyOwner {
        maxLeverage = _maxLeverage;
    }

    /** @notice Denominated in BPS */
    function setLiquidationFeePercentage(
        uint256 _feePercentage
    ) external onlyOwner {
        require(_feePercentage <= 100, "Fee is too high");
        liquidationFeePercentage = _feePercentage;
    }
}
