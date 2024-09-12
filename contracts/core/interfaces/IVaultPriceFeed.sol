// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IVaultPriceFeed {
    function adjustmentBasisPoints(address _token) external view returns (uint256);
    function isAdjustmentAdditive(address _token) external view returns (bool);
    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external;
    function setIsSecondaryPriceEnabled(bool _isEnabled) external;
    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external;
    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external;
    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external;
    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external;
    function getPrice(address _token, bool _maximise) external view returns (uint256);
    function getLatestPrimaryPrice(address _token) external view returns (uint256);
    function getPrimaryPrice(address _token, bool _maximise) external view returns (uint256);
    function setTokenConfig(
        address _token,
        bool _isStrictStable,
        bytes32 _pythPriceId,
        uint256 _pythConfScalingFactor
    ) external;
}
