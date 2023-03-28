// // SPDX-License-Identifier: MIT

// pragma solidity 0.8.16;


// import { StandardFundingHandler } from "./StandardFundingHandler.sol";

// library StandardFundingLibrary {

//     /*********************/
//     /*** Voting Actor ****/
//     /*********************/

//     function setVotingActor(
//         mapping(address => StandardFundingHandler.VotingActor) storage votingActors,
//         address actor_,
//         int256 fundingVote_,
//         uint256 screeningVote_,
//         uint256 fundingProposalId_,
//         uint256 screeningProposalId_
//     ) external {
//         votingActors[actor_].fundingVotes.push(fundingVote_);
//         votingActors[actor_].screeningVotes.push(screeningVote_);
//         votingActors[actor_].fundingProposalIds.push(fundingProposalId_);
//         votingActors[actor_].screeningProposalIds.push(screeningProposalId_);
//     }

//     function getVotingActorsInfo(
//         mapping(address => StandardFundingHandler.VotingActor) storage votingActors,
//         address actor_,
//         uint256 index_
//     ) external view returns (int256, uint256, uint256, uint256) {
//         return (
//             votingActors[actor_].fundingVotes[index_],
//             votingActors[actor_].screeningVotes[index_],
//             votingActors[actor_].fundingProposalIds[index_],
//             votingActors[actor_].screeningProposalIds[index_]
//         );
//     }

//     /**************************/
//     /*** Utility Functions ****/
//     /**************************/

//     function forEachFundingVote(StandardFundingHandler.VotingActor storage votingActor_, function(int256) external func) internal {
//         int256[] storage fundingVotes = votingActor_.fundingVotes;
//         for (uint256 i; i < fundingVotes.length; ++i) {
//             func(fundingVotes[i]);
//         }
//     }

//     function reduceFundingVote(StandardFundingHandler.VotingActor storage votingActor_, int256 acc_, function(int256,int256) external returns (int256) func)
//         internal
//         returns (int256)
//     {
//         int256[] storage fundingVotes = votingActor_.fundingVotes;
//         for (uint256 i; i < fundingVotes.length; ++i) {
//             acc_ = func(acc_, fundingVotes[i]);
//         }
//         return acc_;
//     }

//     function forEachScreeningVote(StandardFundingHandler.VotingActor storage votingActor_, function(uint256) external func) internal {
//         uint256[] storage screeningVotes = votingActor_.screeningVotes;
//         for (uint256 i; i < screeningVotes.length; ++i) {
//             func(screeningVotes[i]);
//         }
//     }

//     function reduceScreeningVote(StandardFundingHandler.VotingActor storage votingActor_, uint256 acc_, function(uint256,uint256) external returns (uint256) func)
//         internal
//         returns (uint256)
//     {
//         uint256[] storage screeningVotes = votingActor_.screeningVotes;
//         for (uint256 i; i < screeningVotes.length; ++i) {
//             acc_ = func(acc_, screeningVotes[i]);
//         }
//         return acc_;
//     }

// }
