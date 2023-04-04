// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

// import { Test }    from "forge-std/Test.sol";
// import { IVotes }  from "@oz/governance/utils/IVotes.sol";
// import { Strings } from "@oz/utils/Strings.sol";

// import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
// import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";

// import { GrantFund }        from "../../../src/grants/GrantFund.sol";
// import { IStandardFunding } from "../../../src/grants/interfaces/IStandardFunding.sol";

abstract contract Log {

//     function _logActorSummary(uint24 distributionId_, bool funding_, bool screening_) internal view {
//         console.log("\nActor Summary\n");

//         console.log("------------------");
//         console.log("Number of Actors", getActorsCount());

//         // sum proposal votes of each actor
//         for (uint256 i = 0; i < getActorsCount(); ++i) {
//             address actor = actors[i];

//             // get actor info
//             (
//                 IStandardFunding.FundingVoteParams[] memory fundingVoteParams,
//                 IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams,
//                 uint256 delegationRewardsClaimed
//             ) = getVotingActorsInfo(actor, distributionId_);

//             console.log("Actor:                    ", actor);
//             console.log("Delegate:                 ", _token.delegates(actor));
//             console.log("delegationRewardsClaimed: ", delegationRewardsClaimed);
//             console.log("\n");

//             // log funding info
//             if (funding_) {
//                 console.log("--Funding----------");
//                 console.log("Funding proposals voted for:     ", fundingVoteParams.length);
//                 console.log("Sum of squares of fvc:           ", sumSquareOfVotesCast(fundingVoteParams));
//                 console.log("Funding Votes Cast:              ", uint256(sumFundingVotes(fundingVoteParams)));
//                 console.log("Negative Funding Votes Cast:     ", countNegativeFundingVotes(fundingVoteParams));
//                 console.log("------------------");
//                 console.log("\n");
//             }

//             if (screening_) {
//                 console.log("--Screening----------");
//                 console.log("Screening Voting Power:          ", _grantFund.getVotesScreening(distributionId_, actor));
//                 console.log("Screening Votes Cast:            ", sumVoterScreeningVotes(actor, distributionId_));
//                 console.log("Screening proposals voted for:   ", screeningVoteParams.length);
//                 console.log("------------------");
//                 console.log("\n");
//             }
//         }
//     }

//     function _logCallSummary(mapping(bytes32 => uint256) memory numberOfCalls) internal view {
//         console.log("\nCall Summary\n");
//         console.log("--SFM----------");
//         console.log("SFH.startNewDistributionPeriod ",  numberOfCalls["SFH.startNewDistributionPeriod"]);
//         console.log("SFH.proposeStandard            ",  numberOfCalls["SFH.proposeStandard"]);
//         console.log("SFH.screeningVote              ",  numberOfCalls["SFH.screeningVote"]);
//         console.log("SFH.fundingVote                ",  numberOfCalls["SFH.fundingVote"]);
//         console.log("SFH.updateSlate                ",  numberOfCalls["SFH.updateSlate"]);
//         console.log("SFH.executeStandard            ",  numberOfCalls["SFH.executeStandard"]);
//         console.log("SFH.claimDelegateReward        ",  numberOfCalls["SFH.claimDelegateReward"]);
//         console.log("roll                           ",  numberOfCalls["roll"]);
//         console.log("------------------");
//         console.log(
//             "Total Calls:",
//             numberOfCalls["SFH.startNewDistributionPeriod"] +
//             numberOfCalls["SFH.proposeStandard"] +
//             numberOfCalls["SFH.screeningVote"] +
//             numberOfCalls["SFH.fundingVote"] +
//             numberOfCalls["SFH.updateSlate"] +
//             numberOfCalls["SFH.executeStandard"] +
//             numberOfCalls["SFH.claimDelegateReward"] +
//             numberOfCalls["roll"]
//         );
//     }

//     function _logProposalSummary() internal view {
//         console.log("\nProposal Summary\n");
//         console.log("Number of Proposals", standardFundingProposalCount);
//         for (uint256 i = 0; i < standardFundingProposalCount; ++i) {
//             console.log("------------------");
//             (uint256 proposalId, uint24 distributionId, uint128 votesReceived, uint128 tokensRequested, int128 fundingVotesReceived, bool executed) = _grantFund.getProposalInfo(standardFundingProposals[i]);
//             console.log("proposalId:           ",  proposalId);
//             console.log("distributionId:       ",  distributionId);
//             console.log("executed:             ",  executed);
//             console.log("votesReceived:        ",  votesReceived);
//             console.log("tokensRequested:      ",  tokensRequested);
//             if (fundingVotesReceived < 0) {
//                 console.log("Negative fundingVotesReceived: ",  uint256(Maths.abs(fundingVotesReceived)));
//             }
//             else {
//                 console.log("Positive fundingVotesReceived: ",  uint256(int256(fundingVotesReceived)));
//             }

//             console.log("------------------");
//         }
//         console.log("\n");
//     }


}
