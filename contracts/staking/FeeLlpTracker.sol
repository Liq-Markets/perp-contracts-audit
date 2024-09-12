// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardTracker.sol";

contract FeeLlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee LLP", "fLLP") {}
}