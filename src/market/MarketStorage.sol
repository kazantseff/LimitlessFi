// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MarketStorage {
    enum PositionType {
        LONG,
        SHORT
    }

    struct Position {
        uint256 collateral;
        uint256 size;
        PositionType positionType;
    }

    mapping(address => Position position) public userPosition;

    // Max leverage for a position
    uint256 public maxLeverage;
    // Measured in USD value, incremented by the "size" of the position
    uint256 public openInterestUSD;
    // Measured in index tokens, incremented by the "size in index tokens"
    uint256 public openInterstInUnderlying;
}
