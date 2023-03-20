// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IERC20 }   from "@oz/token/ERC20/IERC20.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

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
     * @notice Mapping checking if a voter has voted on a given proposal.
     * @dev proposalId => address => bool.
     */
    mapping(uint256 => mapping(address => bool)) public hasVotedExtraordinary;

    /**
     * @notice The maximum length of a proposal's voting period, in blocks.
     */
    uint256 internal constant MAX_EFM_PROPOSAL_LENGTH = 216_000; // number of blocks in one month

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /// @inheritdoc IExtraordinaryFunding
    function executeExtraordinary(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external nonReentrant override returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, descriptionHash_);

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        // since we are casting from uint128 to uint256, we can safely assume that the value will not overflow
        uint256 tokensRequested = uint256(proposal.tokensRequested);

        // check the proposal succeeded, or already executed
        // revert otherwise
        if (proposal.executed || !_extraordinaryProposalSucceeded(proposalId_, tokensRequested)) revert ExecuteExtraordinaryProposalInvalid();

        fundedExtraordinaryProposals.push(proposalId_);

        _execute(proposalId_, targets_, values_, calldatas_);

        proposal.executed = true;

        // update treasury
        treasury -= tokensRequested;
    }

    /// @inheritdoc IExtraordinaryFunding
    function proposeExtraordinary(
        uint256 endBlock_,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_) external override returns (uint256 proposalId_) {

        proposalId_ = hashProposal(targets_, values_, calldatas_, keccak256(bytes(description_)));

        ExtraordinaryFundingProposal storage newProposal = extraordinaryFundingProposals[proposalId_];

        // check if proposal already exists (proposal id not 0)
        if (newProposal.proposalId != 0) revert ProposalAlreadyExists();

        // check proposal length is within limits of 1 month maximum
        if (block.number + MAX_EFM_PROPOSAL_LENGTH < endBlock_) revert InvalidProposal();

        uint128 totalTokensRequested = _validateCallDatas(targets_, values_, calldatas_);

        // check tokens requested are available for claiming from the treasury
        if (uint256(totalTokensRequested) > _getSliceOfTreasury(Maths.WAD - _getMinimumThresholdPercentage())) revert InvalidProposal();

        // store newly created proposal
        newProposal.proposalId      = proposalId_;
        newProposal.startBlock      = SafeCast.toUint128(block.number);
        newProposal.endBlock        = SafeCast.toUint128(endBlock_);
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
            description_
        );
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    function voteExtraordinary(
        address account_,
        uint256 proposalId_
    ) external returns (uint256 votesCast_) {
        votesCast_ = _extraordinaryFundingVote(proposalId_, account_);
    }

    /**
     * @notice Vote on a proposal for extraordinary funding.
     * @dev    Votes can only be cast affirmatively, or not cast at all.
     * @param  proposalId_ The ID of the current proposal being voted upon.
     * @param  account_    The voting account.
     * @return votes_      The amount of votes cast.
     */
    function _extraordinaryFundingVote(
        uint256 proposalId_,
        address account_
    ) internal returns (uint256 votes_) {
        if (hasVotedExtraordinary[proposalId_][account_]) revert AlreadyVoted();

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.startBlock > block.number || proposal.endBlock < block.number || proposal.executed) {
            revert ExtraordinaryFundingProposalInactive();
        }

        // check voting power at snapshot block
        votes_ = _getVotesExtraordinary(account_, proposalId_);
        proposal.votesReceived += SafeCast.toUint120(votes_);

        // record that voter has voted on this extraorindary funding proposal
        hasVotedExtraordinary[proposalId_][account_] = true;

        emit VoteCast(
            account_,
            proposalId_,
            1,
            votes_,
            ""
        );
    }

    /**
     * @notice Check if a proposal for extraordinary funding has succeeded.
     * @param  proposalId_ The ID of the proposal being checked.
     * @return             Boolean indicating whether the proposal has succeeded.
     */
    function _extraordinaryProposalSucceeded(
        uint256 proposalId_,
        uint256 tokensRequested_
    ) internal view returns (bool) {
        ExtraordinaryFundingProposal memory proposal = extraordinaryFundingProposals[proposalId_];

        bool isInvalid = false;

        // check proposal's votes received exceeds the minimum threshold required
        if (uint256(proposal.votesReceived) < tokensRequested_ + _getSliceOfNonTreasury(_getMinimumThresholdPercentage())) {
            isInvalid = true;
        }

        // check tokens requested are available for claiming from the treasury
        if (tokensRequested_ > _getSliceOfTreasury(Maths.WAD - _getMinimumThresholdPercentage())) {
            isInvalid = true;
        }

        return isInvalid ? false : true;
    }

    /********************************/
    /*** Internal View Functions ****/
    /********************************/

    function _getExtraordinaryProposalState(uint256 proposalId_) internal view returns (ProposalState) {
        ExtraordinaryFundingProposal memory proposal = extraordinaryFundingProposals[proposalId_];

        bool voteSucceeded = _extraordinaryProposalSucceeded(proposalId_, uint256(proposal.tokensRequested));

        if (proposal.executed)                                        return ProposalState.Executed;
        else if (proposal.endBlock >= block.number && !voteSucceeded) return ProposalState.Active;
        else if (voteSucceeded)                                       return ProposalState.Succeeded;
        else                                                          return ProposalState.Defeated;
    }

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

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage_ The percentage of the Non treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function _getSliceOfNonTreasury(
        uint256 percentage_
    ) internal view returns (uint256) {
        uint256 totalAjnaSupply = IERC20(ajnaTokenAddress).totalSupply();
        return Maths.wmul(totalAjnaSupply - treasury, percentage_);
    }

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage_ The percentage of the treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function _getSliceOfTreasury(
        uint256 percentage_
    ) internal view returns (uint256) {
        return Maths.wmul(treasury, percentage_);
    }

    function _getVotesExtraordinary(address account_, uint256 proposalId_) internal view returns (uint256 votes_) {
        // one token one vote for extraordinary funding
        if (proposalId_ != 0) {
            // get the number of votes available to voters at the start of the proposal, and 33 blocks before the start of the proposal
            uint256 startBlock = extraordinaryFundingProposals[proposalId_].startBlock;

            votes_ = _getVotesAtSnapshotBlocks(
                account_,
                startBlock - VOTING_POWER_SNAPSHOT_DELAY,
                startBlock
            );
        } else {
            revert ExtraordinaryFundingProposalInactive();
        }
    }

    /********************************/
    /*** External View Functions ****/
    /********************************/

    /// @inheritdoc IExtraordinaryFunding
    function getMinimumThresholdPercentage() external view returns (uint256) {
        return _getMinimumThresholdPercentage();
    }

    /// @inheritdoc IExtraordinaryFunding
    function getSliceOfNonTreasury(
        uint256 percentage_
    ) external view override returns (uint256) {
        return _getSliceOfNonTreasury(percentage_);
    }

    /// @inheritdoc IExtraordinaryFunding
    function getSliceOfTreasury(
        uint256 percentage_
    ) external view override returns (uint256) {
        return _getSliceOfTreasury(percentage_);
    }

    /// @inheritdoc IExtraordinaryFunding
    function getExtraordinaryProposalInfo(
        uint256 proposalId_
    ) external view override returns (uint256, uint128, uint128, uint128, uint120, bool) {
        return (
            extraordinaryFundingProposals[proposalId_].proposalId,
            extraordinaryFundingProposals[proposalId_].startBlock,
            extraordinaryFundingProposals[proposalId_].endBlock,
            extraordinaryFundingProposals[proposalId_].tokensRequested,
            extraordinaryFundingProposals[proposalId_].votesReceived,
            extraordinaryFundingProposals[proposalId_].executed
        );
    }

    function getExtraordinaryProposalSucceeded(uint256 proposalId_) external view returns (bool) {
        // since we are casting from uint128 to uint256, we can safely assume that the value will not overflow
        uint256 tokensRequested = uint256(extraordinaryFundingProposals[proposalId_].tokensRequested);

        return _extraordinaryProposalSucceeded(proposalId_, tokensRequested);
    }

    function getVotesExtraordinary(address account_, uint256 proposalId_) external view returns (uint256 votes_) {
        votes_ = _getVotesExtraordinary(account_, proposalId_);
    }

}
