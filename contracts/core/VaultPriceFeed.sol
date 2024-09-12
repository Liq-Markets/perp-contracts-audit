// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "../libraries/math/SafeMath.sol";

import "./interfaces/IFeeSharing.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../oracle/interfaces/IPyth.sol";
import "../oracle/interfaces/ISecondaryPriceFeed.sol";
import "../oracle/interfaces/IChainlinkFlags.sol";


contract VaultPriceFeed is IVaultPriceFeed {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;
    uint256 public constant PYTH_CONF_SCALING_FACTOR_PRECISION = 10 ** 18;

    address public gov;

    bool public isSecondaryPriceEnabled = true;
    bool public favorPrimaryPrice = false;
    uint256 public maxStrictPriceDeviation = 0;
    address public secondaryPriceFeed;
    uint256 public spreadThresholdBasisPoints = 30;

    IPyth public pythNetwork;
    uint public maxPythPriceAge;

    mapping (address => uint256) public spreadBasisPoints;
    mapping (address => bytes32) public pythPriceIds;
    mapping (address => uint256) public pythConfScalingFactors;
    // Pyth can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping (address => bool) public strictStableTokens;

    mapping (address => uint256) public override adjustmentBasisPoints;
    mapping (address => bool) public override isAdjustmentAdditive;
    mapping (address => uint256) public lastAdjustmentTimings;

    modifier onlyGov() {
        require(msg.sender == gov, "VaultPriceFeed: forbidden");
        _;
    }

    constructor() public {
        gov = msg.sender;
        IFeeSharing feeSharing = IFeeSharing(0x8680CEaBcb9b56913c519c069Add6Bc3494B7020); // This address is the address of the SFS contract
        feeSharing.assign(84); //Registers this contract and assigns the NFT to the owner of this contract
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external override onlyGov {
        require(
            lastAdjustmentTimings[_token].add(MAX_ADJUSTMENT_INTERVAL) < block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    function setMaxPythPriceAge(uint _maxPythPriceAge) external onlyGov {
        maxPythPriceAge = _maxPythPriceAge;
    }

    function setPythNetwork(IPyth _pythNetwork) external onlyGov {
        pythNetwork = _pythNetwork;
    }

    function setPythPriceId(address _token, bytes32 _priceId) external onlyGov {
        pythPriceIds[_token] = _priceId;
    }

    function setIsSecondaryPriceEnabled(bool _isEnabled) external override onlyGov {
        isSecondaryPriceEnabled = _isEnabled;
    }

    function setSecondaryPriceFeed(address _secondaryPriceFeed) external onlyGov {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external override onlyGov {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external override onlyGov {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external override onlyGov {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external override onlyGov {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    function setTokenConfig(
        address _token,
        bool _isStrictStable,
        bytes32 _pythPriceId,
        uint256 _pythConfScalingFactor
    ) external override onlyGov {
        strictStableTokens[_token] = _isStrictStable;
        pythPriceIds[_token] = _pythPriceId;
        pythConfScalingFactors[_token] = _pythConfScalingFactor;
    }

    function getPrice(address _token, bool _maximise) public override view returns (uint256) {
        uint256 price = getPriceV1(_token, _maximise);

        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price = price.mul(BASIS_POINTS_DIVISOR.add(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            } else {
                price = price.mul(BASIS_POINTS_DIVISOR.sub(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            }
        }

        return price;
    }

    function getPriceV1(address _token, bool _maximise) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price.sub(ONE_USD) : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
        }

        return price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
    }

    function getLatestPrimaryPrice(address _token) public override view returns (uint256) {
        return _getPythPrice(_token, true, false);
    }

    function getPrimaryPrice(address _token, bool _maximise) public override view returns (uint256) {
        return _getPythPrice(_token, false, _maximise);
    }

    function _getPythPrice(address _token, bool _ignoreConfidence, bool _maximise) internal view returns (uint256) {
        PythStructs.Price memory priceData = _getPythPriceData(_token);
        uint256 price;
        // TODO: Check what factor of the confindence interval we want to use
        if(_ignoreConfidence) {
            price = uint256(uint64(priceData.price));
        } else {
            uint256 scaledConf = uint256(uint64(priceData.conf)).mul(pythConfScalingFactors[_token]).div( PYTH_CONF_SCALING_FACTOR_PRECISION);
            price = _maximise ? uint256(uint64(priceData.price)).add(scaledConf) : uint256(uint64(priceData.price)).sub(scaledConf);
        }
        require(priceData.expo <= 0, "VaultPriceFeed: invalid price exponent");
        uint32 priceExponent = uint32(-priceData.expo);
        return price.mul( PRICE_PRECISION).div(uint32(10) ** priceExponent);
    }

    function _getPythPriceData(address _token) internal view returns (PythStructs.Price memory) {
        require(address(pythNetwork) != address(0), "VaultPriceFeed: pyth network address is not configured");
        bytes32 id = pythPriceIds[_token];
        require(id != bytes32(0), "VaultPriceFeed: price id not configured for given token");
        PythStructs.Price memory priceData = pythNetwork.getPriceNoOlderThan(id, maxPythPriceAge);
        require(priceData.price > 0, "VaultPriceFeed: invalid price");
        return priceData;
    }
    function getSecondaryPrice(address _token, uint256 _referencePrice, bool _maximise) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) { return _referencePrice; }
        return ISecondaryPriceFeed(secondaryPriceFeed).getPrice(_token, _referencePrice, _maximise);
    }
}
