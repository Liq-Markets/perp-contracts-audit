// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardDistributor.sol";

contract FeeLlpDistributor is RewardDistributor {
    constructor(address _rewardTracker) public RewardDistributor(_rewardTracker) {}
}