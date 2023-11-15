// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EthUsdOracle} from "../oracle/ethUsdOracle.sol";
import {Vault} from "../vault/Vault.sol";

error PositionNotOpen();
error PositionDecreased();
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

    event PositionLiquidated(address indexed user);s

    struct Position {
        uint256 collateral;
        uint256 size;
        uint256 averagePrice;
        bool isLong;
    }

    mapping(address => Position position) public userPosition;

    Vault public vault;
    EthUsdOracle public oracle;
    address collateralToken;
    uint256 public constant DENOMINATOR = 10_000;
    // Denominated in BIPS
    uint256 public liquidationFeePercentage; 
    // Max leverage for a position
    uint256 public maxLeverage;
    uint256 public minimumPositionSize;
    // Measured in USD value, incremented by the "size" of the position
    uint256 public openInterestUSDLong;
    // Measured in index tokens, incremented by the "size in index tokens"
    uint256 public openInterstInUnderlyingLong;
    uint256 public openInterestUSDShort;
    uint256 public openInterstInUnderlyingShort;
}
