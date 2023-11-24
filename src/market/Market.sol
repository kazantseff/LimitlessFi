// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MarketStorage.sol";
import "./utils/MarketUtils.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "../lib/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {LimitlessVault} from "../vault/Vault.sol";

contract LimitlessMarket is Ownable, MarketStorage, MarketUtils {
    using SafeCast for int;
    using SafeMath for uint;
    using SignedMath for int;
    using SafeTransferLib for ERC20;

    constructor(
        address _collateralToken,
        address _oracle,
        address _vault
    ) Ownable(msg.sender) {
        collateralToken = _collateralToken;
        oracle = EthUsdOracle(_oracle);
        vault = LimitlessVault(_vault);
    }

    /** @notice Function to open position
     * @param collateral amount of collateral in USDC
     * @param size Size of the position in index token
     * @param isLong Type of the position: Long or Short
     */
    function openPosition(
        uint256 size,
        uint256 collateral,
        bool isLong
    ) external {
        require(size >= minimumPositionSize, "Position size below minimum");
        require(
            _checkLeverage(size, collateral),
            "Position exceeds maxLeverage"
        );
        Position memory position = userPosition[msg.sender];
        require(position.size == 0, "Position is already open");

        // Account for open interest
        uint256 price = oracle.getPrice().toUint256();
        if (isLong) {
            openInterestUSDLong += size * price;
            openInterstInUnderlyingLong += size;
        } else {
            openInterestUSDShort += size * price;
            openInterstInUnderlyingShort += size;
        }

        position.size = size;
        position.collateral = collateral;
        position.averagePrice = price;
        position.isLong = isLong;
        // Initialize time of lastAccrual with block.timestamp
        position.lastTimestampAccrued = block.timestamp;

        userPosition[msg.sender] = position;

        // Transfer collateral from user
        ERC20(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateral
        );

        require(_ensureLiquidityReserves(), "Not enough liquidity");

        emit PositionOpened(msg.sender, size, collateral, isLong);
    }

    /** @notice Function to increase size and/or collateral of position
     * @param addSize if 0, means user only increases collateral
     * @param addCollateral if 0, means user only increases size
     */
    function increasePosition(uint256 addSize, uint256 addCollateral) external {
        Position memory position = userPosition[msg.sender];
        if (position.size == 0 || position.collateral == 0)
            revert PositionNotOpen();
        // Do not allow closing of the position
        if (addSize == 0 && addCollateral == 0) revert CannotClosePosition();

        position = _accrueInterest(position);

        uint256 price = oracle.getPrice().toUint256();
        // First add collateral, so later if user also wants to increase the size
        // Checks will be made on new amount of collateral
        if (addCollateral > 0) {
            ERC20(collateralToken).safeTransferFrom(
                msg.sender,
                address(this),
                addCollateral
            );
            position.collateral += addCollateral;
            // There is no need to check leverage here, as by increasing collateral, user can only decrease leverage
        }

        // We only need to re-calculate the average entry price, if a user bought more
        // If he added size to the position
        if (addSize > 0) {
            uint256 oldSize = position.size;
            position.size += addSize;
            require(
                _checkLeverage(position.size, position.collateral),
                "Position exceeds maxLeverage"
            );

            // Increase the open interest
            if (position.isLong) {
                openInterstInUnderlyingLong += addSize;
                openInterestUSDLong += addSize * price;
            } else {
                openInterstInUnderlyingShort += addSize;
                openInterestUSDShort += addSize * price;
            }

            // Formula to calculate average price
            // (totalCostEntry1 + totalCostEntry2) / (totalQuantityEntry1 + totalQuantityEntry2)
            // totalCost = price * amount
            uint256 totalCostEntry1 = position.averagePrice * oldSize;
            uint256 totalCostEntry2 = price * addSize;
            uint256 averagePrice = (totalCostEntry1 + totalCostEntry2).div(
                oldSize + addSize
            );
            position.averagePrice = averagePrice;
        }

        userPosition[msg.sender] = position;

        require(_ensureLiquidityReserves(), "Not enough liquidity");

        emit PositionIncreased(msg.sender, addSize, addCollateral);
    }

    /** @notice Function to decrease size and/or collateral of the position
     * @param removeSize if 0 => user only removes collateral
     * @param removeCollateral if 0 => user only removes size
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
            (position /*fee */, ) = _removeSize(
                position,
                msg.sender,
                removeSize,
                false
            );
        }

        if (removeCollateral > 0) {
            position.collateral -= removeCollateral;
            ERC20(collateralToken).safeTransfer(msg.sender, removeCollateral);
            require(
                _checkLeverage(position.size, position.collateral),
                "Position exceeds maxLeverage"
            );
        }

        userPosition[msg.sender] = position;

        emit PositionDecreased(msg.sender, removeSize, removeCollateral);
    }

    /** @notice Function to liquidate a user, i.e reduce the size of the position to 0
     * @param user User to liquidity
     */
    function liquidate(address user) external {
        Position memory position = userPosition[user];
        uint256 liquidationFee;
        require(
            !_checkLeverage(position.size, position.collateral),
            "Position is not liquiditable."
        );
        position = _accrueInterest(position);

        uint256 removeSize = position.size;
        // Remove the size, realize the pnl, transfer the collateral
        (position, liquidationFee) = _removeSize(
            position,
            user,
            removeSize,
            true
        );
        userPosition[user] = position;
        ERC20(collateralToken).safeTransfer(msg.sender, liquidationFee);

        emit PositionLiquidated(user);
    }

    function setMinimumPositionSize(uint256 size) external onlyOwner {
        minimumPositionSize = size;
    }

    function setMaxLeverage(uint256 _maxLeverage) external onlyOwner {
        maxLeverage = _maxLeverage;
    }

    // Denominated in BIPS
    function setLiquidationFeePercentage(
        uint256 _feePercentage
    ) external onlyOwner {
        require(_feePercentage < 100, "Fee is too high");
        liquidationFeePercentage = _feePercentage;
    }
}
