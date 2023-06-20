// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console } from "@std/console.sol";
import { Math }    from "@oz/utils/math/Math.sol";

import { GrantFund }       from "../../../src/grants/GrantFund.sol";
import { IGrantFundState } from "../../../src/grants/interfaces/IGrantFundState.sol";
import { Maths }           from "../../../src/grants/libraries/Maths.sol";

import { StandardHandler } from "../handlers/StandardHandler.sol";

import { IAjnaToken } from "../../utils/IAjnaToken.sol";
import { ITestBase }  from "../base/ITestBase.sol";

contract Logger {

    IAjnaToken      internal _ajna;
    GrantFund       internal _grantFund;
    ITestBase       internal testContract;
    StandardHandler internal _standardHandler;

    constructor(address grantFund_, address standardHandler_, address testContract_) {
        _ajna = IAjnaToken(GrantFund(grantFund_).ajnaTokenAddress());
        _grantFund = GrantFund(grantFund_);
        _standardHandler = StandardHandler(standardHandler_);
        testContract = ITestBase(testContract_);
    }

    /**************************/
    /*** Logging Functions ****/
    /**************************/

    function logActorSummary(uint24 distributionId_, bool funding_, bool screening_) external view {
        console.log("\nActor Summary\n");

        console.log("------------------");
        console.log("Number of Actors", _standardHandler.getActorsCount());

        // sum proposal votes of each actor
        for (uint256 i = 0; i < _standardHandler.getActorsCount(); ++i) {
            address actor = _standardHandler.actors(i);

            // get actor info
            (
                IGrantFundState.FundingVoteParams[] memory fundingVoteParams,
                IGrantFundState.ScreeningVoteParams[] memory screeningVoteParams,
                uint256 delegationRewardsClaimed
            ) = _standardHandler.getVotingActorsInfo(actor, distributionId_);

            console.log("Actor:                    ", actor);
            console.log("Delegate:                 ", _ajna.delegates(actor));
            console.log("delegationRewardsClaimed: ", delegationRewardsClaimed);
            console.log("\n");

            // log funding info
            if (funding_) {
                console.log("--Funding----------");
                console.log("Funding proposals voted for:     ", fundingVoteParams.length);
                console.log("Sum of squares of fvc:           ", _standardHandler.sumSquareOfVotesCast(fundingVoteParams));
                console.log("Funding Votes Cast:              ", uint256(_standardHandler.sumFundingVotes(fundingVoteParams)));
                console.log("Negative Funding Votes Cast:     ", _standardHandler.countNegativeFundingVotes(fundingVoteParams));
                console.log("------------------");
                console.log("\n");
            }

            if (screening_) {
                console.log("--Screening----------");
                console.log("Screening Voting Power:          ", _grantFund.getVotesScreening(distributionId_, actor));
                console.log("Screening Votes Cast:            ", _standardHandler.sumVoterScreeningVotes(actor, distributionId_));
                console.log("Screening proposals voted for:   ", screeningVoteParams.length);
                console.log("------------------");
                console.log("\n");
            }
        }
    }

    function logActorDelegationRewards(uint24 distributionId_) external view {
        console.log("\nActor Delegation Rewards\n");

        console.log("------------------");
        console.log("Number of Actors", _standardHandler.getActorsCount());
        console.log("------------------");
        console.log("\n");

        uint256 totalDelegationRewardsClaimed = 0;

        // get voter info
        for (uint256 i = 0; i < _standardHandler.getActorsCount(); ++i) {
            address actor = _standardHandler.actors(i);

            // get actor info
            (
                IGrantFundState.FundingVoteParams[] memory fundingVoteParams,
                IGrantFundState.ScreeningVoteParams[] memory screeningVoteParams,
                uint256 delegationRewardsClaimed
            ) = _standardHandler.getVotingActorsInfo(actor, distributionId_);

            totalDelegationRewardsClaimed += delegationRewardsClaimed;

            console.log("Actor:                               ", actor);
            console.log("Delegate:                            ", _ajna.delegates(actor));
            console.log("delegationRewardsClaimed:            ", delegationRewardsClaimed);

            (uint256 votingPower, uint256 remainingVotingPower, uint256 votesCast) = _grantFund.getVoterInfo(distributionId_, actor);

            uint256 votingPowerAllocatedByDelegatee = votingPower - remainingVotingPower;
            uint256 rootVotingPowerAllocatedByDelegatee = Math.sqrt(votingPowerAllocatedByDelegatee * 1e18);
            console.log("votingPower:                         ", votingPower);
            console.log("remainingVotingPower:                ", remainingVotingPower);
            console.log("votingPowerAllocatedByDelegatee:     ", votingPowerAllocatedByDelegatee);
            console.log("rootVotingPowerAllocatedByDelegatee: ", rootVotingPowerAllocatedByDelegatee);

            if (votingPowerAllocatedByDelegatee > 0 && rootVotingPowerAllocatedByDelegatee == 0) {
                console.log("ACTOR ROUNDED TO 0 REWARDS: ", actor);
            }
            console.log("------------------");
            console.log("\n");

        }
        console.log("totalDelegationRewardsClaimed: ", totalDelegationRewardsClaimed);
    }

    function logCallSummary() external view {
        console.log("\nCall Summary\n");
        console.log("--SFM----------");
        console.log("SFH.startNewDistributionPeriod ",  _standardHandler.numberOfCalls("SFH.startNewDistributionPeriod"));
        console.log("SFH.propose                    ",  _standardHandler.numberOfCalls("SFH.propose"));
        console.log("SFH.screeningVote              ",  _standardHandler.numberOfCalls("SFH.screeningVote"));
        console.log("SFH.fundingVote                ",  _standardHandler.numberOfCalls("SFH.fundingVote"));
        console.log("SFH.updateSlate                ",  _standardHandler.numberOfCalls("SFH.updateSlate"));
        console.log("SFH.execute                    ",  _standardHandler.numberOfCalls("SFH.execute"));
        console.log("SFH.claimDelegateReward        ",  _standardHandler.numberOfCalls("SFH.claimDelegateReward"));
        console.log("roll                           ",  _standardHandler.numberOfCalls("roll"));
        console.log("------------------");
        console.log(
            "Total Calls:",
            _standardHandler.numberOfCalls("SFH.startNewDistributionPeriod") +
            _standardHandler.numberOfCalls("SFH.propose") +
            _standardHandler.numberOfCalls("SFH.screeningVote") +
            _standardHandler.numberOfCalls("SFH.fundingVote") +
            _standardHandler.numberOfCalls("SFH.updateSlate") +
            _standardHandler.numberOfCalls("SFH.execute") +
            _standardHandler.numberOfCalls("SFH.claimDelegateReward") +
            _standardHandler.numberOfCalls("roll")
        );
    }

    function logProposalSummary() external view {
        uint24 distributionId = _grantFund.getDistributionId();
        uint256[] memory proposals = _standardHandler.getStandardFundingProposals(distributionId);

        console.log("\nProposal Summary\n");
        console.log("Number of Proposals", proposals.length);
        for (uint256 i = 0; i < proposals.length; ++i) {
            console.log("------------------");
            (uint256 proposalId, , uint128 votesReceived, uint128 tokensRequested, int128 fundingVotesReceived, bool executed) = _grantFund.getProposalInfo(proposals[i]);
            console.log("proposalId:              ",  proposalId);
            console.log("distributionId:          ",  distributionId);
            console.log("executed:                ",  executed);
            console.log("screening votesReceived: ",  votesReceived);
            console.log("tokensRequested:         ",  tokensRequested);
            if (fundingVotesReceived < 0) {
                console.log("Negative fundingVotesReceived: ",  uint256(Maths.abs(fundingVotesReceived)));
            }
            else {
                console.log("Positive fundingVotesReceived: ",  uint256(int256(fundingVotesReceived)));
            }

            console.log("------------------");
        }
        console.log("\n");
    }

    function logTimeSummary() external view {
        uint24 distributionId = _grantFund.getDistributionId();
        (, uint256 startBlock, uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        console.log("\nTime Summary\n");
        console.log("------------------");
        console.log("Distribution Id:        %s", distributionId);
        console.log("start block:            %s", startBlock);
        console.log("end block:              %s", endBlock);
        console.log("block number:           %s", block.number);
        console.log("current block:          %s", testContract.currentBlock());
        console.log("------------------");
    }


    function logFinalizeSummary(uint24 distributionId_) external view {
        (, , , uint128 fundsAvailable, , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId_);
        uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

        uint256[] memory topTenScreenedProposalIds = _grantFund.getTopTenProposals(distributionId_);

        console.log("\nFinalize Summary\n");
        console.log("------------------");
        console.log("Distribution Id:            ", distributionId_);
        console.log("Funds Available:            ", fundsAvailable);
        // DELEGATION REWARDS LOGS
        console.log("Delegation Rewards Set:     ", _standardHandler.numberOfCalls('delegationRewardSet'));
        console.log("Delegation Rewards Claimed: ", _standardHandler.numberOfCalls('SFH.claimDelegateReward.success'));
        // EXECUTE LOGS
        console.log("Proposal Execute attempt:   ", _standardHandler.numberOfCalls('SFH.execute.attempt'));
        console.log("Proposal Execute Count:     ", _standardHandler.numberOfCalls('SFH.execute.success'));
        console.log("unexecuted proposal:        ", _standardHandler.numberOfCalls('unexecuted.proposal'));
        // UPDATE SLATE LOGS
        console.log("Slate Update Prep:          ", _standardHandler.numberOfCalls('SFH.updateSlate.prep'));
        console.log("Slate Update length:        ", _standardHandler.numberOfCalls('updateSlate.length'));
        console.log("Slate Update Called:        ", _standardHandler.numberOfCalls('SFH.updateSlate.called'));
        console.log("Slate Update Success:       ", _standardHandler.numberOfCalls('SFH.updateSlate.success'));
        console.log("Slate Proposals:            ", _standardHandler.numberOfCalls('proposalsInSlates'));
        console.log("Next Slate length:          ", _standardHandler.numberOfCalls('updateSlate.length'));
        console.log("unused proposal:            ", _standardHandler.numberOfCalls('unused.proposal'));
        console.log("Top Slate Proposal Count:   ", topSlateProposalIds.length);
        console.log("Top Ten Proposal Count:     ", topTenScreenedProposalIds.length);
        console.log("Top slate funds requested:  ", _standardHandler.getTokensRequestedInFundedSlateInvariant(topSlateHash));
        console.log("------------------");
    }


    function logFundingSummary(uint24 distributionId_) external view {
        console.log("\nFunding Summary\n");
        console.log("------------------");
        console.log("number of funding stage starts:         ", _standardHandler.numberOfCalls("SFH.FundingStage"));
        console.log("number of funding stage success votes:  ", _standardHandler.numberOfCalls("SFH.fundingVote.success"));
        console.log("number of proposals receiving funding:  ", _standardHandler.numberOfCalls("SFH.fundingVote.proposal"));
        console.log("number of funding stage negative votes: ", _standardHandler.numberOfCalls("SFH.negativeFundingVote"));
        console.log("distributionId:                         ", distributionId_);
        console.log("SFH.updateSlate.success:                ", _standardHandler.numberOfCalls("SFH.updateSlate.success"));
        (, , , , uint256 fundingPowerCast, ) = _grantFund.getDistributionPeriodInfo(distributionId_);
        console.log("Total Funding Power Cast:               ", fundingPowerCast);
        console.log("------------------");
    }
}


