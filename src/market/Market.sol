// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MarketStorage.sol";
import "./utils/MarketUtils.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Vault} from "../vault/Vault.sol";

contract LimitlessMarket is Ownable, MarketStorage, MarketUtils {
    using SafeCast for int;
    using Math for uint;
    using SafeTransferLib for ERC20;

    constructor(
        address _collateralToken,
        address _oracle,
        address _vault
    ) Ownable(msg.sender) {
        collateralToken = _collateralToken;
        oracle = EthUsdOracle(_oracle);
        vault = Vault(_vault);
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
        position.entryPrice = price;
        position.isLong = isLong;

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

        if (addSize > 0) {
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
        }

        // #TODO: Calcualte average entry price

        userPosition[msg.sender] = position;

        require(_ensureLiquidityReserves(), "Not enough liquidity");

        emit PositionIncreased(msg.sender, addSize, addCollateral);
    }

    // Close position

    // Liquidate

    function setMinimumPositionSize(uint256 size) external onlyOwner {
        minimumPositionSize = size;
    }

    function setMaxLeverage(uint256 _maxLeverage) external onlyOwner {
        maxLeverage = _maxLeverage;
    }
}
