// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

error StalePriceFeed();

contract EthUsdOracle {
    // ETH/USD Price Feed
    AggregatorV3Interface public immutable baseOracle;

    constructor(AggregatorV3Interface oracle) {
        baseOracle = oracle;
    }

    /** @notice Returns the pricec of ETH in terms of USD in 18 decimals or precision */
    function getPrice() external view returns (int) {
        (, int answer, , uint256 updatedAt, ) = baseOracle.latestRoundData();
        if (updatedAt < block.timestamp - 60 * 60 /* 1 hours */)
            revert StalePriceFeed();
        return answer * 1e10;
    }
}
