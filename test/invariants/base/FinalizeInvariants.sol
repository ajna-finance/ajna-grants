// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";
import { Math }     from "@oz/utils/math/Math.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { GrantFund }  from "../../../src/grants/GrantFund.sol";
import { IGrantFund } from "../../../src/grants/interfaces/IGrantFund.sol";
import { Maths }      from "../../../src/grants/libraries/Maths.sol";

import { TestBase }        from "./TestBase.sol";
import { StandardHandler } from "../handlers/StandardHandler.sol";

abstract contract FinalizeInvariants is TestBase {

    function _invariant_CS1_CS2_CS3_CS4_CS5_CS6(GrantFund grantFund_, StandardHandler standardHandler_) view internal {
        uint24 distributionId = grantFund_.getDistributionId();

        (, , uint256 endBlock, uint128 fundsAvailable, , bytes32 topSlateHash) = grantFund_.getDistributionPeriodInfo(distributionId);

        uint256[] memory topSlateProposalIds = grantFund_.getFundedProposalSlate(topSlateHash);

        uint256[] memory topTenScreenedProposalIds = grantFund_.getTopTenProposals(distributionId);

        require(
            topSlateProposalIds.length <= 10,
            "invariant CS2: top slate should have 10 or less proposals"
        );

        // check proposal state of the constituents of the top slate
        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < topSlateProposalIds.length; ++i) {
            uint256 proposalId = topSlateProposalIds[i];
            (, , , uint128 tokensRequested, int128 fundingVotesReceived, ) = grantFund_.getProposalInfo(proposalId);
            totalTokensRequested += tokensRequested;

            require(
                fundingVotesReceived >= 0,
                "invariant CS3: Proposal slate should never contain a proposal with negative funding votes received"
            );

            require(
                _findProposalIndex(proposalId, topTenScreenedProposalIds) != -1,
                "invariant CS4: Proposal slate should never contain a proposal that wasn't in the top ten in the funding stage."
            );
        }

        require(
            totalTokensRequested <= uint256(fundsAvailable) * 9 / 10,
            "invariant CS1: total tokens requested should be <= 90% of fundsAvailable"
        );

        require(
            !standardHandler_.hasDuplicates(topSlateProposalIds),
            "invariant CS5: proposal slate should never contain duplicate proposals"
        );

        // check DistributionState for top slate updates
        StandardHandler.DistributionState memory state = standardHandler_.getDistributionState(distributionId);
        for (uint i = 0; i < state.topSlates.length; ++i) {
            StandardHandler.Slate memory slate = state.topSlates[i];

            require(
                slate.updateBlock <= endBlock && slate.updateBlock >= grantFund_.getChallengeStageStartBlock(endBlock),
                "invariant CS6: Funded proposal slate's can only be updated during a distribution period's challenge stage"
            );
        }
    }

    function _invariant_ES1_ES2_ES3(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        uint24 distributionId = grantFund_.getDistributionId();
        (, , , , , bytes32 topSlateHash) = grantFund_.getDistributionPeriodInfo(distributionId);

        uint256[] memory topSlateProposalIds = grantFund_.getFundedProposalSlate(topSlateHash);

        // calculate the total tokens requested by the proposals in the top slate
        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < topSlateProposalIds.length; ++i) {
            uint256 proposalId = topSlateProposalIds[i];
            (, , , uint128 tokensRequested, , ) = grantFund_.getProposalInfo(proposalId);
            totalTokensRequested += tokensRequested;
        }

        uint256[] memory standardFundingProposals = standardHandler_.getStandardFundingProposals(distributionId);

        // check the state of every proposal submitted in this distribution period
        for (uint256 i = 0; i < standardFundingProposals.length; ++i) {
            uint256 proposalId = standardFundingProposals[i];
            (, uint24 proposalDistributionId, , , , bool executed) = grantFund_.getProposalInfo(proposalId);
            int256 proposalIndex = _findProposalIndex(proposalId, topSlateProposalIds);
            // invariant ES1: A proposal can only be executed if it's listed in the final funded proposal slate at the end of the challenge round.
            if (proposalIndex == -1) {
                assertFalse(executed);
            }

            // invariant ES2: A proposal can only be executed if it's listed in the final funded proposal slate at the end of the challenge round.
            assertEq(distributionId, proposalDistributionId);
            if (executed) {
                (, , uint48 endBlock, , , ) = grantFund_.getDistributionPeriodInfo(proposalDistributionId);
                // TODO: store and check proposal execution time
                require(
                    currentBlock > endBlock,
                    "invariant ES2: A proposal can only be executed after the challenge stage is complete."
                );
            }
        }

        require(
            !standardHandler_.hasDuplicates(standardHandler_.getProposalsExecuted()),
            "invariant ES3: A proposal can only be executed once."
        );
    }

    function _invariant_DR1_DR2_DR3_DR5(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        uint24 distributionId = grantFund_.getDistributionId();
        (, , , uint128 fundsAvailable, uint256 fundingVotePowerCast, ) = grantFund_.getDistributionPeriodInfo(distributionId);

        uint256 totalRewardsClaimed;

        for (uint256 i = 0; i < standardHandler_.getActorsCount(); ++i) {
            address actor = standardHandler_.actors(i);

            // get the initial funding stage voting power of the actor
            (uint128 votingPower, uint128 remainingVotingPower, ) = grantFund_.getVoterInfo(distributionId, actor);

            // get actor info from standard handler
            (
                IGrantFund.FundingVoteParams[] memory fundingVoteParams,
                IGrantFund.ScreeningVoteParams[] memory screeningVoteParams,
                uint256 delegationRewardsClaimed
            ) = standardHandler_.getVotingActorsInfo(actor, distributionId);

            totalRewardsClaimed += delegationRewardsClaimed;

            if (delegationRewardsClaimed != 0) {
                // check that delegation rewards are greater tahn 0 if they did vote in both stages
                assertTrue(delegationRewardsClaimed >= 0);

                uint256 votingPowerAllocatedByDelegatee = votingPower - remainingVotingPower;
                uint256 rootVotingPowerAllocatedByDelegatee = Math.sqrt(votingPowerAllocatedByDelegatee * 1e18);

                require(
                    fundingVoteParams.length > 0 && screeningVoteParams.length > 0,
                    "invariant DR2: Delegation rewards are 0 if voter didn't vote in both stages."
                );

                uint256 rewards;
                if (votingPowerAllocatedByDelegatee > 0) {
                    rewards = Math.mulDiv(
                        fundsAvailable,
                        rootVotingPowerAllocatedByDelegatee,
                        10 * fundingVotePowerCast
                    );
                }

                require(
                    delegationRewardsClaimed == rewards,
                    "invariant DR3: Delegation rewards are proportional to voters funding power allocated in the funding stage."
                );
            }
        }

        require(
            totalRewardsClaimed <= fundsAvailable * 1 / 10,
            "invariant DR1: Cumulative delegation rewards should be <= 10% of a distribution periods GBC"
        );

        // check state after all possible delegation rewards have been claimed
        if (standardHandler_.numberOfCalls('SFH.claimDelegateReward.success') == standardHandler_.getActorsCount()) {
            require(
                totalRewardsClaimed >= Maths.wmul(fundsAvailable * 1 / 10, 0.9999 * 1e18),
                "invariant DR5: Cumulative rewards claimed should be within 99.99% -or- 0.01 AJNA tokens of all available delegation rewards"
            );
            assertEq(totalRewardsClaimed, fundsAvailable * 1 / 10);
        }
    }

}
