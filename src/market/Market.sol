// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MarketStorage.sol";
import "./utils/MarketUtils.sol";

contract LimitlessMarket is MarketStorage, MarketUtils {
    /** @notice Function to open position
     * @param collateral amount of collateral in USDC
     * @param size Size of the position in index token
     * @param positionType Type of the position: Long or Short
     */
    function openPosition(
        uint256 size,
        uint256 collateral,
        PositionType positionType
    ) external {
        Position memory position = userPosition[msg.sender];
        require(position.size == 0, "Position is already open");

        // To calculate leverage used =>
        // (price of token * size) / collateral
        uint256 leverage = _calculateLeverage(size, collateral);
        require(leverage < maxLeverage);

        position.size = size;
        position.collateral = collateral;
        position.positionType = positionType;

        userPosition[msg.sender] = position;
    }

    // Close position

    // Liquidate
}
