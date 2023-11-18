// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EthUsdOracle} from "../oracle/ethUsdOracle.sol";
import {Vault} from "../vault/Vault.sol";

error PositionNotOpen();
error PositionCannotBeDecreased();
error CannotClosePosition();

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

    event PositionLiquidated(address indexed user);

    struct Position {
        uint256 collateral;
        uint256 size;
        uint256 averagePrice;
        bool isLong;
        uint256 lastTimestampAccrued;
    }

    mapping(address => Position position) public userPosition;

    Vault public vault;
    EthUsdOracle public oracle;
    address collateralToken;
    uint256 internal constant SCALE_FACTOR = 1e18;
    uint256 internal constant MAXIMUM_BPS = 10_000;
    uint256 internal constant SECONDS_IN_YEAR = 31_536_000;
    // Denominated in BIPS
    uint256 internal liquidationFeePercentage;
    // Max leverage for a position
    uint256 internal maxLeverage;
    uint256 internal minimumPositionSize;
    // Measured in USD value, incremented by the "size" of the position
    uint256 internal openInterestUSDLong;
    // Measured in index tokens, incremented by the "size in index tokens"
    uint256 internal openInterstInUnderlyingLong;
    uint256 internal openInterestUSDShort;
    uint256 internal openInterstInUnderlyingShort;
}
