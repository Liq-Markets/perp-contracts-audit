
// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import "../libraries/token/ERC20.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("MockUSDT", "USDT",6) public {
        _mint(msg.sender, 1000000000000000);
    }
}