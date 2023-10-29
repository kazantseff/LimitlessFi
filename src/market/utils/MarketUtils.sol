// Calculate Open interest
// Calculate protocol PNL
// calculate user pnl
// Calculate reserves

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EthUsdOracle} from "../../oracle/ethUsdOracle.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract MarketUtils {
    using SafeCast for int;
    using Math for uint;
    EthUsdOracle public oracle;

    function _calculateLeverage(
        uint256 size,
        uint256 collateral
    ) internal view returns (uint256) {
        int256 price = oracle.getPrice();
        // Get the price from oracle
        uint256 leverage = price.toUint256().mulDiv(size, collateral);
        return leverage;
    }
}
