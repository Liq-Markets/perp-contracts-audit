// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IPriceFeed {
    function latestAnswer(bool _maximise) external view returns (int256);
    function latestRound() external view returns (uint80);
    function getRoundData(uint80 roundId) external view returns (uint80, int256, uint256, uint256, uint80);
    function latestRoundData(bool _maximise) external view returns (uint80, int256, uint256, uint256, uint80);
}
