// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";

import "./interfaces/IFeeSharing.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";
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

    // Identifier of the Sequencer offline flag on the Flags contract
    address constant private FLAG_ARBITRUM_SEQ_OFFLINE = address(bytes20(bytes32(uint256(keccak256("chainlink.flags.chain-seq-offline")) - 1)));

    address public gov;

    bool public isSecondaryPriceEnabled = true;
    uint256 public maxStrictPriceDeviation = 0;
    address public secondaryPriceFeed;


    mapping (address => address) public priceFeeds;
    mapping (address => uint256) public priceDecimals;
    mapping (address => uint256) public spreadBasisPoints;
    // Chainlink can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping (address => bool) public strictStableTokens;

    mapping (address => uint256) public override adjustmentBasisPoints;
    mapping (address => bool) public override isAdjustmentAdditive;
    mapping (address => uint256) public lastAdjustmentTimings;
    address public chainlinkFlags;

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

    function setChainlinkFlags(address _chainlinkFlags) external onlyGov {
        chainlinkFlags = _chainlinkFlags;
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

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external override onlyGov {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external override onlyGov {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
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

    function getPrimaryPrice(address _token, bool _maximise) public override view returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

        if (chainlinkFlags != address(0)) {
            bool isRaised = IChainlinkFlags(chainlinkFlags).getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
            if (isRaised) {
                    // If flag is raised we shouldn't perform any critical operations
                revert("Oracle feeds are not being updated");
            }
        }

        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        int256 price = priceFeed.latestAnswer(_maximise);
        

        require(price > 0, "VaultPriceFeed: could not fetch price");
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token];
        return uint256(price).mul(PRICE_PRECISION).div(10 ** _priceDecimals);
    }
    function getSecondaryPrice(address _token, uint256 _referencePrice, bool _maximise) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) { return _referencePrice; }
        return ISecondaryPriceFeed(secondaryPriceFeed).getPrice(_token, _referencePrice, _maximise);
    }
}
