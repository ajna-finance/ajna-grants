// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { Funding } from "./Funding.sol";

import { IExtraordinaryFunding } from "../interfaces/IExtraordinaryFunding.sol";

import { Maths } from "../libraries/Maths.sol";

abstract contract ExtraordinaryFunding is Funding, IExtraordinaryFunding {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     * @notice Mapping of extant extraordinary funding proposals.
     * @dev proposalId => ExtraordinaryFundingProposal.
     */
    mapping (uint256 => ExtraordinaryFundingProposal) internal extraordinaryFundingProposals;

    /**
     * @notice The list of extraordinary funding proposalIds that have been executed.
     */
    uint256[] internal fundedExtraordinaryProposals;

    /**
     * @notice The maximum length of a proposal's voting period, in blocks.
     */
    uint256 internal constant MAX_EFM_PROPOSAL_LENGTH = 216_000; // number of blocks in one month

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /// @inheritdoc IExtraordinaryFunding
    function executeExtraordinary(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) external nonReentrant returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, descriptionHash_);

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.executed) {
            revert ExecuteExtraordinaryProposalInvalid();
        }

        // check if the proposal has received more votes than minimumThreshold and tokensRequestedPercentage of all tokens
        if (proposal.votesReceived >= proposal.tokensRequested + getSliceOfNonTreasury(_getMinimumThresholdPercentage())) {
            proposal.succeeded = true;
        } else {
            proposal.succeeded = false;
            revert ExecuteExtraordinaryProposalInvalid();
        }

        fundedExtraordinaryProposals.push(proposal.proposalId);

        super.execute(targets_, values_, calldatas_, descriptionHash_);
        proposal.executed = true;

        // update treasury
        treasury -= proposal.tokensRequested;
    }

    /// @inheritdoc IExtraordinaryFunding
    function proposeExtraordinary(
        uint256 endBlock_,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_) external returns (uint256 proposalId_) {

        proposalId_ = hashProposal(targets_, values_, calldatas_, keccak256(bytes(description_)));

        if (extraordinaryFundingProposals[proposalId_].proposalId != 0) revert ProposalAlreadyExists();

        // check proposal length is within limits of 1 month maximum and it hasn't already been submitted
        if (block.number + MAX_EFM_PROPOSAL_LENGTH < endBlock_ || extraordinaryFundingProposals[proposalId_].proposalId != 0) {
            revert ExtraordinaryFundingProposalInvalid();
        }

        uint256 totalTokensRequested = _validateCallDatas(targets_, values_, calldatas_);

        // check tokens requested is within limits
        if (totalTokensRequested > getSliceOfTreasury(Maths.WAD - _getMinimumThresholdPercentage())) revert ExtraordinaryFundingProposalInvalid();

        // store newly created proposal
        ExtraordinaryFundingProposal storage newProposal = extraordinaryFundingProposals[proposalId_];
        newProposal.proposalId      = proposalId_;
        newProposal.startBlock      = block.number;
        newProposal.endBlock        = endBlock_;
        newProposal.tokensRequested = totalTokensRequested;

        emit ProposalCreated(
            proposalId_,
            msg.sender,
            targets_,
            values_,
            new string[](targets_.length),
            calldatas_,
            block.number,
            endBlock_,
            description_);
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @notice Vote on a proposal for extraordinary funding.
     * @dev    Votes can only be cast affirmatively, or not cast at all.
     * @param  proposalId_ The ID of the current proposal being voted upon.
     * @param  account_    The voting account.
     * @return votes_      The amount of votes cast.
     */
    function _extraordinaryFundingVote(uint256 proposalId_, address account_) internal returns (uint256 votes_) {
        if (hasVotedExtraordinary[proposalId_][account_]) revert AlreadyVoted();

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.startBlock > block.number || proposal.endBlock < block.number || proposal.executed) {
            revert ExtraordinaryFundingProposalInactive();
        }

        // check voting power at snapshot block
        votes_ = _getVotes(account_, block.number, abi.encode(proposalId_));
        proposal.votesReceived += votes_;

        // record that voter has voted on this extraorindary funding proposal
        hasVotedExtraordinary[proposalId_][account_] = true;

        emit VoteCast(account_, proposalId_, 1, votes_, "");
    }

    /**
     * @notice Check if a proposal for extraordinary funding has succeeded.
     * @param  proposalId_ The ID of the proposal being checked.
     * @return             Boolean indicating whether the proposal has succeeded.
     */
    function _extraordinaryFundingVoteSucceeded(uint256 proposalId_) internal view returns (bool) {
        return extraordinaryFundingProposals[proposalId_].succeeded;
    }

    /***********************/
    /*** View Functions ****/
    /***********************/

    function _getMinimumThresholdPercentage() internal view returns (uint256) {
        // default minimum threshold is 50
        if (fundedExtraordinaryProposals.length == 0) {
            return 0.5 * 1e18;
        }
        // minimum threshold increases according to the number of funded EFM proposals
        else {
            return 0.5 * 1e18 + (fundedExtraordinaryProposals.length * (0.05 * 1e18));
        }
    }

    /// @inheritdoc IExtraordinaryFunding
    function getMinimumThresholdPercentage() external view returns (uint256) {
        return _getMinimumThresholdPercentage();
    }

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage_ The percentage of the Non treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getSliceOfNonTreasury(uint256 percentage_) public view returns (uint256) {
        uint256 totalAjnaSupply = IERC20(ajnaTokenAddress).totalSupply();
        return Maths.wmul(totalAjnaSupply - treasury, percentage_);
    }

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage_ The percentage of the treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getSliceOfTreasury(uint256 percentage_) public view returns (uint256) {
        return Maths.wmul(treasury, percentage_);
    }

    /// @inheritdoc IExtraordinaryFunding
    function getExtraordinaryProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, uint256, uint256, bool, bool) {
        ExtraordinaryFundingProposal memory proposal = extraordinaryFundingProposals[proposalId_];
        return (
            proposal.proposalId,
            proposal.tokensRequested,
            proposal.startBlock,
            proposal.endBlock,
            proposal.votesReceived,
            proposal.succeeded,
            proposal.executed
        );
    }

}
