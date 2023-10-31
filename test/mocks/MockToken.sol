// SPDX-License-Identifier: WTFPL
pragma solidity ^0.8.20;

import "lib/solmate/src/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) ERC20(name, symbol, 8) {
        _mint(msg.sender, supply);
    }
}
