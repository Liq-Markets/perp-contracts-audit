// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/token/IERC20.sol";
import "../libraries/math/SafeMath.sol";

import "../staking/interfaces/IRewardTracker.sol";
import "../staking/interfaces/IRewardDistributor.sol";

interface IRewardTrackerExtended is IRewardTracker {
    function distributor() external view returns (address);
}

contract RewardReader {
    using SafeMath for uint256;

    function getDepositBalances(address _account, address[] memory _depositTokens, address[] memory _rewardTrackers) public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](_rewardTrackers.length);
        for (uint256 i = 0; i < _rewardTrackers.length; i++) {
            IRewardTracker rewardTracker = IRewardTracker(_rewardTrackers[i]);
            amounts[i] = rewardTracker.depositBalances(_account, _depositTokens[i]);
        }
        return amounts;
    }

    function getStakingInfo(address _account, address[] memory _rewardTrackers) public view returns (uint256[] memory, address[] memory) {
        uint256 propsLength = 5;
        uint256 totalPropsLength = 0;
        
        for (uint256 i = 0; i < _rewardTrackers.length; i++) {
            address rewardDistributor = IRewardTrackerExtended(_rewardTrackers[i]).distributor();
            totalPropsLength = totalPropsLength +( IRewardDistributor(rewardDistributor).allRewardTokensLength()*  propsLength);
        }
        address[] memory rewardTokenAddresses = new address[](totalPropsLength/propsLength);
        uint256[] memory amounts = new uint256[](totalPropsLength);
        for (uint256 i = 0; i < _rewardTrackers.length; i++) {
            IRewardTracker rewardTracker = IRewardTracker(_rewardTrackers[i]);
            address[] memory rewardTokens = IRewardTracker(_rewardTrackers[i]).getAllRewardTokens();
            uint256 offset = 0;

           for (uint256 j = 0; j < rewardTokens.length; j++) {
            
               address rewardToken = rewardTokens[j];
               rewardTokenAddresses[i*rewardTokens.length + j] = rewardToken;
               amounts[offset + j * propsLength] = rewardTracker.claimable(_account, rewardToken);
               amounts[offset + j * propsLength + 1] = rewardTracker.tokensPerInterval(rewardToken);
               amounts[offset + j * propsLength + 2] = rewardTracker.averageStakedAmounts(_account);
               amounts[offset + j * propsLength + 3] = rewardTracker.cumulativeRewards(_account, rewardToken);
               amounts[offset + j * propsLength + 4] = IERC20(rewardToken).totalSupply();

               if (j == rewardTokens.length - 1) offset += j * propsLength + 4;
           }
       }
        return (amounts,rewardTokenAddresses);
    }
}

