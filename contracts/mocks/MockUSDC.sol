
// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import "../libraries/token/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("MockUSDC", "USDC",6) public {
        _mint(msg.sender, 1000000000000000);
    }
}