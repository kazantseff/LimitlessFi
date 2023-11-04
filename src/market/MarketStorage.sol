// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EthUsdOracle} from "../oracle/ethUsdOracle.sol";
import {Vault} from "../vault/Vault.sol";

error PositionNotOpen();
error PositionDecreased();

contract MarketStorage {
    struct Position {
        uint256 collateral;
        uint256 size;
        bool isLong;
    }

    mapping(address => Position position) public userPosition;

    Vault public vault;
    EthUsdOracle public oracle;
    address collateralToken;
    // Max leverage for a position
    uint256 public maxLeverage;
    // Measured in USD value, incremented by the "size" of the position
    uint256 public openInterestUSDLong;
    // Measured in index tokens, incremented by the "size in index tokens"
    uint256 public openInterstInUnderlyingLong;
    uint256 public openInterestUSDShort;
    uint256 public openInterstInUnderlyingShort;
}
