// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EthUsdOracle} from "../oracle/ethUsdOracle.sol";
import {LimitlessVault} from "../vault/Vault.sol";

error InvalidPositionSize();
error PositionExceedsMaxLeverage();
error PositionNotLiquidatable();
error PositionNotOpen();
error PositionCannotBeDecreased();
error CannotClosePosition();
error NotEnoughLiquidity();

contract MarketStorage {
    event PositionOpened(
        address indexed user,
        uint256 indexed size,
        uint256 indexed collateral,
        bool isLong
    );

    event PositionIncreased(
        address indexed user,
        uint256 indexed addSize,
        uint256 indexed addCollateral
    );

    event PositionDecreased(
        address indexed user,
        uint256 indexed removeSize,
        uint256 indexed removeCollateral
    );

    event PositionClosed(address indexed user);

    event PositionLiquidated(address indexed user);

    struct Position {
        uint256 collateral;
        uint256 size;
        uint256 averagePrice;
        bool isLong;
        uint256 lastTimestampAccrued;
    }

    mapping(address => Position position) public userPosition;

    LimitlessVault public vault;
    EthUsdOracle public oracle;
    address collateralToken;
    uint256 internal constant SCALE_FACTOR = 1e18;
    uint256 internal constant MAXIMUM_BPS = 10_000;
    uint256 internal constant SECONDS_IN_YEAR = 31_536_000;
    /** @notice Denominated in BPS */
    uint256 internal liquidationFeePercentage;
    uint256 internal maxLeverage;
    uint256 internal minimumPositionSize;
    /** @notice Measured in USD value, incremented by the dollar value of the position */
    uint256 public openInterestUSDLong;
    /** @notice Measured in index tokens, incremented by the "size" in index tokens" */
    uint256 public openInterstInUnderlyingLong;
    /** @notice Measured in USD value, incremented by the dollar value of the position */
    uint256 public openInterestUSDShort;
    /** @notice Measured in index tokens, incremented by the "size" in index tokens" */
    uint256 public openInterstInUnderlyingShort;
}
