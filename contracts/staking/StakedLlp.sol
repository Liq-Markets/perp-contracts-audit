// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/ILlpManager.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardTracker.sol";

// provide a way to transfer staked LLP tokens by unstaking from the sender
// and staking for the receiver
// tests in RewardRouterV2.js
contract StakedLlp {
    using SafeMath for uint256;

    string public constant name = "StakedLlp";
    string public constant symbol = "sLLP";
    uint8 public constant decimals = 18;

    address public llp;
    ILlpManager public llpManager;
    address public stakedLlpTracker;
    address public feeLlpTracker;

    mapping (address => mapping (address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address _llp,
        ILlpManager _llpManager,
        address _stakedLlpTracker,
        address _feeLlpTracker
    ) public {
        llp = _llp;
        llpManager = _llpManager;
        stakedLlpTracker = _stakedLlpTracker;
        feeLlpTracker = _feeLlpTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "StakedLlp: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return IRewardTracker(feeLlpTracker).depositBalances(_account, llp);
    }

    function totalSupply() external view returns (uint256) {
        return IERC20(stakedLlpTracker).totalSupply();
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "StakedLlp: approve from the zero address");
        require(_spender != address(0), "StakedLlp: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "StakedLlp: transfer from the zero address");
        require(_recipient != address(0), "StakedLlp: transfer to the zero address");

        require(
            llpManager.lastAddedAt(_sender).add(llpManager.cooldownDuration()) <= block.timestamp,
            "StakedLlp: cooldown duration not yet passed"
        );

        IRewardTracker(stakedLlpTracker).unstakeForAccount(_sender, feeLlpTracker, _amount, _sender);
        IRewardTracker(feeLlpTracker).unstakeForAccount(_sender, llp, _amount, _sender);

        IRewardTracker(feeLlpTracker).stakeForAccount(_sender, _recipient, llp, _amount);
        IRewardTracker(stakedLlpTracker).stakeForAccount(_recipient, _recipient, feeLlpTracker, _amount);
    }
}
