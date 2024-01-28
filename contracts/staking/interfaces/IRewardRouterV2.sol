// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardRouterV2 {
    function feeLlpTracker() external view returns (address);
    function stakedLlpTracker() external view returns (address);
}
