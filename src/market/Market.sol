// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MarketStorage.sol";
import "./utils/MarketUtils.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import {Vault} from "../vault/Vault.sol";

contract LimitlessMarket is MarketStorage, MarketUtils {
    using SafeCast for int;
    using Math for uint;
    using SafeTransferLib for ERC20;

    constructor(address _collateralToken, address _oracle, address _vault) {
        collateralToken = _collateralToken;
        oracle = EthUsdOracle(_oracle);
        vault = Vault(_vault);
    }

    modifier checkLeverage(uint256 size, uint256 collateral) {
        uint256 leverage = _calculateLeverage(size, collateral);
        require(leverage < maxLeverage);
        _;
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
    ) external checkLeverage(size, collateral) {
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
        position.isLong = isLong;

        userPosition[msg.sender] = position;

        // Transfer collateral from user
        ERC20(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateral
        );

        require(_ensureLiquidityReserves(), "Not enough liquidity");
    }

    /** @notice Function to increase size and/or collateral of position */
    function increasePosition(
        uint256 newSize,
        uint256 newCollateral
    ) external checkLeverage(newSize, newCollateral) {
        Position memory position = userPosition[msg.sender];
        if (position.size == 0 || position.collateral == 0)
            revert PositionNotOpen();
        if (newSize < position.size || newCollateral < position.collateral)
            revert PositionDecreased();

        // Transfer collateral
        ERC20(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            newCollateral - position.collateral
        );

        position.size = newSize;
        position.collateral = newCollateral;
        userPosition[msg.sender] = position;

        require(_ensureLiquidityReserves(), "Not enough liquidity");
    }

    // Close position

    // Liquidate
}
