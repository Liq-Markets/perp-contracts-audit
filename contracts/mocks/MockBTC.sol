
// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import "../libraries/token/ERC20.sol";

contract MockBTC is ERC20 {
    constructor() ERC20("MockBTC", "BTC",8) public {
        _mint(msg.sender, 100000000000000000000000000);
    }
}