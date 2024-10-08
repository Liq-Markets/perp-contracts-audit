// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/ILlpManager.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IFeeSharing.sol";
import "../access/Governable.sol";

contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public llp; // Liq Liquidity Provider token
    address public llpManager;
    address public feeLlpTracker;

    address public vault;

    mapping (address => address) public pendingReceivers;

    event StakeLlp(address indexed account, uint256 amount);
    event UnstakeLlp(address indexed account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _llp,
        address _vault,
        address _feeLlpTracker,
        address _llpManager
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;
        llp = _llp;
        vault = _vault;

        feeLlpTracker = _feeLlpTracker;
        llpManager = _llpManager;
        IFeeSharing feeSharing = IFeeSharing(0x8680CEaBcb9b56913c519c069Add6Bc3494B7020); // This address is the address of the SFS contract
        feeSharing.assign(84); //Registers this contract and assigns the NFT to the owner of this contract    
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function mintAndStakeLlp(address _token, uint256 _amount, uint256 _minUsdl, uint256 _minLlp) external nonReentrant returns (uint256) {
        require(_amount != 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        return _mintAndStakeLlp(account, account, _token, _amount, _minUsdl, _minLlp);
    }

    function _mintAndStakeLlp(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdl, uint256 _minLlp) private returns (uint256) {
        
        uint256 llpAmount = ILlpManager(llpManager).addLiquidityForAccount(_fundingAccount, _account, _token, _amount, _minUsdl, _minLlp);
        IRewardTracker(feeLlpTracker).stakeForAccount(_account, _account, llp, llpAmount);

        emit StakeLlp(_account, llpAmount);

        return llpAmount;

    }

    function mintAndStakeLlpETH(uint256 _minUsdl, uint256 _minLlp) external payable nonReentrant returns (uint256) {
        require(msg.value != 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        
        return _mintAndStakeLlpEth(msg.value, _minUsdl, _minLlp);
    }

    function _mintAndStakeLlpEth(uint256 _amount, uint256 _minUsdl, uint256 _minLlp) private returns (uint256) {
        IERC20(weth).approve(llpManager, _amount);
        address account = msg.sender;
        uint256 llpAmount = ILlpManager(llpManager).addLiquidityForAccount(address(this), account, weth, _amount, _minUsdl, _minLlp);

        IRewardTracker(feeLlpTracker).stakeForAccount(account, account, llp, llpAmount);

        emit StakeLlp(account, llpAmount);

        return llpAmount;
    }

    function unstakeAndRedeemLlp(address _tokenOut, uint256 _llpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_llpAmount != 0, "RewardRouter: invalid _llpAmount");

        address account = msg.sender;
        IRewardTracker(feeLlpTracker).unstakeForAccount(account, llp, _llpAmount, account);
        uint256 amountOut = ILlpManager(llpManager).removeLiquidityForAccount(account, _tokenOut, _llpAmount, _minOut, _receiver);

        emit UnstakeLlp(account, _llpAmount);

        return amountOut;
    }

    function unstakeAndRedeemLlpETH(uint256 _llpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_llpAmount != 0, "RewardRouter: invalid _llpAmount");

        address account = msg.sender;
        IRewardTracker(feeLlpTracker).unstakeForAccount(account, llp, _llpAmount, account);
        uint256 amountOut = ILlpManager(llpManager).removeLiquidityForAccount(account, weth, _llpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeLlp(account, _llpAmount);

        return amountOut;
    }

    function claim(address _rewardToken, bool _compound, bool _withdrawETH,  uint256 _minUsdl, uint256 _minLlp) external nonReentrant {
        require(IRewardTracker(feeLlpTracker).allTokens(_rewardToken), "RewardRouter: not _rewardToken"); // TODO check against token if reward token exist
        address account = msg.sender;
        if(_compound && IVault(vault).whitelistedTokens(_rewardToken)) {
            uint256 amount = IRewardTracker(feeLlpTracker).claimForAccount(account, _rewardToken, address(this));
            if (amount > 0) {
                if(_rewardToken == weth) {
                    _mintAndStakeLlpEth(amount, _minUsdl, _minLlp);
                } else {
                    IERC20(_rewardToken).approve(llpManager, amount);
                    _mintAndStakeLlp(address(this), account, _rewardToken, amount, _minUsdl, _minLlp);
                }
            }
        }else if(_withdrawETH && _rewardToken == weth) {
            uint256 amount = IRewardTracker(feeLlpTracker).claimForAccount(account, _rewardToken, address(this));
            if (amount > 0) {
                IWETH(weth).withdraw(amount);
                payable(account).sendValue(amount);
            }
        }else {
            IRewardTracker(feeLlpTracker).claimForAccount(account, _rewardToken, account);
        }
    }

    function handleRewards(
        bool _shouldConvertWethToEth,
        bool _shouldCompound,
        uint256 _minUsdl,
        uint256 _minLlp
    ) external nonReentrant {
        address account = msg.sender;

        if (_shouldConvertWethToEth || _shouldCompound ) {
            (address[] memory tokens,uint256[] memory amounts) = IRewardTracker(feeLlpTracker).claimAllForAccount(account, address(this));
            for (uint256 i = 0; i < tokens.length; i++) {
                address token = tokens[i];
                uint256 amount = amounts[i];
                if(amount > 0){
                    if(_shouldCompound && IVault(vault).whitelistedTokens(token)){ 
                        if(token == weth){
                            _mintAndStakeLlpEth(amount, _minUsdl, _minLlp);
                        }else{
                            IERC20(token).approve(llpManager, amount);
                            _mintAndStakeLlp(address(this),account,token,amount, _minUsdl, _minLlp);
                        }
                    }else if(_shouldConvertWethToEth && token == weth ){
                        IWETH(weth).withdraw(amount);
                        payable(account).sendValue(amount);
                    }else{
                        IERC20(token).safeTransfer(account, amount);
                    }    
                }         
            }    
        } else {
            IRewardTracker(feeLlpTracker).claimAllForAccount(account, account);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        require(
            ILlpManager(llpManager).lastAddedAt(_sender).add(ILlpManager(llpManager).cooldownDuration()) <= block.timestamp,
            "RewardRouter: cooldown duration not yet passed"
        );
        delete pendingReceivers[_sender];
        uint256 llpAmount = IRewardTracker(feeLlpTracker).depositBalances(_sender, llp);
        if (llpAmount > 0) {
            IRewardTracker(feeLlpTracker).unstakeForAccount(_sender, llp, llpAmount, _sender);
            IRewardTracker(feeLlpTracker).stakeForAccount(_sender, receiver, llp, llpAmount);
        }
    }

}
