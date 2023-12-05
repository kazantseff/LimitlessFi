// SPDX-License-Identifier: WTFPL
pragma solidity ^0.8.20;

import "lib/solmate/src/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockERC20", "MERC", 6) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
