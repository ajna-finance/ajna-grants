// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IVotes }    from "@oz/governance/utils/IVotes.sol";
import { SafeCast }  from "@oz/utils/math/SafeCast.sol";

import { Maths } from "./libraries/Maths.sol";

import { ExtraordinaryFunding } from "./base/ExtraordinaryFunding.sol";
import { StandardFunding }      from "./base/StandardFunding.sol";

import { IGrantFund } from "./interfaces/IGrantFund.sol";

contract GrantFund is IGrantFund, ExtraordinaryFunding, StandardFunding {

    IVotes public immutable token;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(IVotes token_, uint256 treasury_)
    {
        ajnaTokenAddress = address(token_);
        token = token_;
        treasury = treasury_;
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Given a proposalId, find if it is a standard or extraordinary proposal.
     * @param proposalId_ The id of the proposal to query the mechanism of.
     * @return FundingMechanism to which the proposal was submitted.
     */
    function findMechanismOfProposal(
        uint256 proposalId_
    ) public view returns (FundingMechanism) {
        if (standardFundingProposals[proposalId_].proposalId != 0)           return FundingMechanism.Standard;
        else if (extraordinaryFundingProposals[proposalId_].proposalId != 0) return FundingMechanism.Extraordinary;
        else revert ProposalNotFound();
    }

    /**
     * @notice Find the status of a given proposal.
     * @dev Check proposal status based upon Grant Fund specific logic.
     * @param proposalId_ The id of the proposal to query the status of.
     * @return ProposalState of the given proposal.
     */
    function state(
        uint256 proposalId_
    ) public view returns (ProposalState) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // standard proposal state checks
        if (mechanism == FundingMechanism.Standard) {
            return _standardProposalState(proposalId_);
        }
        // extraordinary funding proposal state
        else {
            return _getExtraordinaryProposalState(proposalId_);
        }
    }

    /*********************************/
    /*** Voting Functions External ***/
    /*********************************/

    /**
     * @notice Cast an array of funding votes in one transaction.
     * @dev    Calls out to StandardFunding._fundingVote().
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param voteParams_ The array of votes on proposals to cast.
     * @return votesCast_ The total number of votes cast across all of the proposals.
     */
    function fundingVotesMulti(
        FundingVoteParams[] memory voteParams_
    ) external returns (uint256 votesCast_) {
        QuarterlyDistribution storage currentDistribution = distributions[currentDistributionId];
        QuadraticVoter        storage voter               = quadraticVoters[currentDistribution.id][msg.sender];

        uint256 endBlock = currentDistribution.endBlock;

        uint256 screeningStageEndBlock = _getScreeningStageEndBlock(endBlock);

        // check that the funding stage is active
        if (block.number > screeningStageEndBlock && block.number <= endBlock) {

            // this is the first time a voter has attempted to vote this period,
            // set initial voting power and remaining voting power
            if (voter.votingPower == 0) {

                uint128 newVotingPower = SafeCast.toUint128(_getFundingStageVotingPower(msg.sender, screeningStageEndBlock));

                voter.votingPower          = newVotingPower;
                voter.remainingVotingPower = newVotingPower;
            }

            uint256 numVotesCast = voteParams_.length;

            for (uint256 i = 0; i < numVotesCast; ) {
                Proposal storage proposal = standardFundingProposals[voteParams_[i].proposalId];

                // check that the proposal is part of the current distribution period
                if (proposal.distributionId != currentDistribution.id) revert InvalidVote();

                // cast each successive vote
                votesCast_ += _fundingVote(
                    currentDistribution,
                    proposal,
                    msg.sender,
                    voter,
                    voteParams_[i]
                );

                unchecked { ++i; }
            }
        }
    }

    /**
     * @notice Cast an array of screening votes in one transaction.
     * @dev    Calls out to StandardFunding._screeningVote().
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param voteParams_ The array of votes on proposals to cast.
     * @return votesCast_ The total number of votes cast across all of the proposals.
     */
    function screeningVoteMulti(
        ScreeningVoteParams[] memory voteParams_
    ) external returns (uint256 votesCast_) {
        QuarterlyDistribution memory currentDistribution = distributions[currentDistributionId];

        // check screening stage is active
        if (block.number >= currentDistribution.startBlock && block.number <= _getScreeningStageEndBlock(currentDistribution.endBlock)) {

            uint256 numVotesCast = voteParams_.length;

            for (uint256 i = 0; i < numVotesCast; ) {
                Proposal storage proposal = standardFundingProposals[voteParams_[i].proposalId];

                // check that the proposal is part of the current distribution period
                if (proposal.distributionId != currentDistribution.id) revert InvalidVote();

                uint256 votes = voteParams_[i].votes;

                // cast each successive vote
                votesCast_ += votes;
                _screeningVote(msg.sender, proposal, votes);

                unchecked { ++i; }
            }
        }
    }

    function voteExtraordinary(
        address account_,
        uint256 proposalId_
    ) external returns (uint256 votesCast_) {
        votesCast_ = _extraordinaryFundingVote(proposalId_, account_);
    }

    // TODO: remove this function entirely in terms of accessing votes cast
     /**
     * @notice Check whether an account has voted on a proposal.
     * @dev    Votes can only votes once during the screening stage, and only once on proposals in the extraordinary funding round.
               In the funding stage they can vote as long as they have budget.
     * @return hasVoted_ Boolean for whether the account has already voted in the current proposal, and mechanism.
     */
    function hasVoted(
        uint256 proposalId_,
        address account_
    ) public view returns (bool hasVoted_) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // Checks if Proposal is Standard
        if (mechanism == FundingMechanism.Standard) {
            Proposal              memory proposal            = standardFundingProposals[proposalId_]; 
            QuarterlyDistribution memory currentDistribution = distributions[proposal.distributionId];

            uint256 screeningStageEndBlock = _getScreeningStageEndBlock(currentDistribution.endBlock);

            // screening stage
            if (block.number >= currentDistribution.startBlock && block.number <= screeningStageEndBlock) {
                hasVoted_ = screeningVotesCast[proposal.distributionId][account_] != 0;
            }

            // funding stage
            else if (block.number > screeningStageEndBlock && block.number <= currentDistribution.endBlock) {
                hasVoted_ = quadraticVoters[currentDistribution.id][account_].votesCast.length != 0;
            }
        }
        else {
            hasVoted_ = hasVotedExtraordinary[proposalId_][account_];
        }
    }
}
