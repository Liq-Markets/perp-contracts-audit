pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./interfaces/IPyth.sol";
import "./interfaces/IPriceFeed.sol";
import "../libraries/math/SafeMath.sol";
contract PythToChainlinkWrapper is IPriceFeed {

    using SafeMath for uint256;
    IPyth public pyth;
    bytes32 public priceId;
    address public token;
    uint256 public pythConfScalingFactor;
    uint256 public maxPythPriceAge;
    uint256 public PYTH_CONF_SCALING_FACTOR_PRECISION = 1e18;
    uint256 public constant PRICE_PRECISION = 10 ** 8;


    constructor(address _pyth, bytes32 _priceId, address _token, uint256 _pythConfScalingFactor, uint256 _maxPythPriceAge) public {
        pyth = IPyth(_pyth);
        priceId = _priceId;
        token = _token;
        pythConfScalingFactor = _pythConfScalingFactor;
        maxPythPriceAge = _maxPythPriceAge;
    }

    function latestRound() external view override returns (uint80) {
        (uint256 _, uint80 roundId) = _getPythPrice(true, true);
        return roundId;
    }

    function latestAnswer() external view override returns (int256) {
        (uint256 price, uint80 _) = _getPythPrice(true, true);
        return int256(price);
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {        
        // Convert Pyth price to Chainlink format
        (uint256 price, uint80 _roundId) = _getPythPrice(true, true);

        
        return (
            _roundId,
            int256(price),
            uint256(block.timestamp),
            uint256(block.timestamp),
            _roundId
        );
    }

    function getRoundData(uint80 _roundId) public override view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, 0, 0, 0, 0);
    }


    function _getPythPrice(bool _ignoreConfidence, bool _maximise) internal view returns (uint256, uint80) {
        PythStructs.Price memory priceData = _getPythPriceData();
        uint256 price;
        uint80 roundId;
        // TODO: Check what factor of the confindence interval we want to use
        if(_ignoreConfidence) {
            price = uint256(uint64(priceData.price));
        } else {
            uint256 scaledConf = uint256(uint64(priceData.conf)).mul(pythConfScalingFactor).div( PYTH_CONF_SCALING_FACTOR_PRECISION);
            price = _maximise ? uint256(uint64(priceData.price)).add(scaledConf) : uint256(uint64(priceData.price)).sub(scaledConf);
        }
        roundId = uint80(priceData.publishTime);
        require(priceData.expo <= 0, "PythToChainlinkWrapper: invalid price exponent");
        uint32 priceExponent = uint32(-priceData.expo);
        return (price.mul( PRICE_PRECISION).div(uint32(10) ** priceExponent), roundId);
    }

    function _getPythPriceData() internal view returns (PythStructs.Price memory) {
        require(address(pyth) != address(0), "PythToChainlinkWrapper: pyth network address is not configured");
        require(priceId != bytes32(0), "PythToChainlinkWrapper: price id not configured for given token");
        PythStructs.Price memory priceData = pyth.getPriceNoOlderThan(priceId, maxPythPriceAge);
        require(priceData.price > 0, "PythToChainlinkWrapper: invalid price");
        return priceData;
    }


    // Implement other IPriceFeed functions as needed
}
