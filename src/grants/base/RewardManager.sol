// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IERC20 }          from "@oz/token/ERC20/IERC20.sol";
import { SafeCast }        from "@oz/utils/math/SafeCast.sol";
import { SafeERC20 }       from "@oz/token/ERC20/utils/SafeERC20.sol";

import { Storage } from "./Storage.sol";

import { IGrantFundActions } from "../interfaces/IGrantFundActions.sol";

import { Maths } from "../libraries/Maths.sol";

abstract contract RewardManager is Storage {

    using SafeERC20 for IERC20;

    /*********************************************/
    /*** Delegation Rewards Functions External ***/
    /*********************************************/

    /// @inheritdoc IGrantFundActions
    function claimDelegateReward(
        uint24 distributionId_
    ) external override returns(uint256 rewardClaimed_) {
        // Revert if delegatee didn't vote in screening stage
        if(screeningVotesCast[distributionId_][msg.sender] == 0) revert DelegateRewardInvalid();

        DistributionPeriod memory currentDistribution = _distributions[distributionId_];

        // Check if the distribution period is still active
        if(block.number <= currentDistribution.endBlock) revert DistributionPeriodStillActive();

        // check rewards haven't already been claimed
        if(hasClaimedReward[distributionId_][msg.sender]) revert RewardAlreadyClaimed();

        QuadraticVoter memory voter = _quadraticVoters[distributionId_][msg.sender];

        // calculate rewards earned for voting
        rewardClaimed_ = _getDelegateReward(currentDistribution, voter);

        hasClaimedReward[distributionId_][msg.sender] = true;

        emit DelegateRewardClaimed(
            msg.sender,
            distributionId_,
            rewardClaimed_
        );

        // transfer rewards to delegatee
        if (rewardClaimed_ != 0) IERC20(ajnaTokenAddress).safeTransfer(msg.sender, rewardClaimed_);
    }

    /*********************************************/
    /*** Delegation Rewards Functions Internal ***/
    /*********************************************/

    /**
     * @notice Calculate the delegate rewards that have accrued to a given voter, in a given distribution period.
     * @dev    Voter must have voted in both the screening and funding stages, and is proportional to their share of votes across the stages.
     * @param  currentDistribution_ Struct of the distribution period to calculate rewards for.
     * @param  voter_               Struct of the funding stages voter.
     * @return rewards_             The delegate rewards accrued to the voter.
     */
    function _getDelegateReward(
        DistributionPeriod memory currentDistribution_,
        QuadraticVoter memory voter_
    ) internal pure returns (uint256 rewards_) {
        // calculate the total voting power available to the voter that was allocated in the funding stage
        uint256 votingPowerAllocatedByDelegatee = voter_.votingPower - voter_.remainingVotingPower;

        // if none of the voter's voting power was allocated, they receive no rewards
        if (votingPowerAllocatedByDelegatee != 0) {
            // calculate reward
            // delegateeReward = 10 % of GBC distributed as per delegatee Voting power allocated
            rewards_ = Maths.wdiv(
                Maths.wmul(
                    currentDistribution_.fundsAvailable,
                    votingPowerAllocatedByDelegatee
                ),
                currentDistribution_.fundingVotePowerCast
            ) / 10;
        }
    }

}
