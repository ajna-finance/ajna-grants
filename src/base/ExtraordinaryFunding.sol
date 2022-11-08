// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/token/ERC20/IERC20.sol";

import "./Funding.sol";

import "../interfaces/IExtraordinaryFunding.sol";

import "../libraries/Maths.sol";

abstract contract ExtraordinaryFunding is Funding, IExtraordinaryFunding {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     * @notice Mapping of extant extraordinary funding proposals.
     * @dev proposalId => ExtraordinaryFundingProposal.
     */
    mapping (uint256 => ExtraordinaryFundingProposal) public extraordinaryFundingProposals;

    /**
     * @notice The list of extraordinary funding proposals that have been executed.
     */
    ExtraordinaryFundingProposal[] public fundedExtraordinaryProposals;

    /**
     * @notice The maximum length of a proposal's voting period, in blocks.
     */
    uint256 public constant MAX_EFM_PROPOSAL_LENGTH = 216_000; // number of blocks in one month

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Execute an extraordinary funding proposal.
     * @param targets_         The addresses of the contracts to call.
     * @param values_          The amounts of ETH to send to each target.
     * @param calldatas_       The calldata to send to each target.
     * @param descriptionHash_ The hash of the proposal's description.
     * @return proposalId_ The ID of the executed proposal.
     */
    function executeExtraordinary(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) public nonReentrant returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, descriptionHash_);

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.executed != false || proposal.succeeded != true) {
            revert ExecuteExtraordinaryProposalInvalid();
        }

        fundedExtraordinaryProposals.push(proposal);

        super.execute(targets_, values_, calldatas_, descriptionHash_);
        proposal.executed = true;
    }

    /**
     * @notice Submit a proposal to the extraordinary funding flow.
     * @param endBlock_            Block number of the end of the extraordinary funding proposal voting period.
     * @param targets_             Array of addresses to send transactions to.
     * @param values_              Array of values to send with transactions.
     * @param calldatas_           Array of calldata to execute in transactions.
     * @param description_         Description of the proposal.
     * @return proposalId_         ID of the newly submitted proposal.
     */
    function proposeExtraordinary(
        uint256 endBlock_,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_) public returns (uint256 proposalId_) {

        proposalId_ = hashProposal(targets_, values_, calldatas_, keccak256(bytes(description_)));

        // check proposal length is within limits of 1 month maximum and it hasn't already been submitted
        if (block.number + MAX_EFM_PROPOSAL_LENGTH < endBlock_ || extraordinaryFundingProposals[proposalId_].proposalId != 0) {
            revert ExtraordinaryFundingProposalInvalid();
        }

        uint256 totalTokensRequested = _validateCallDatas(targets_, values_, calldatas_);

        // check tokens requested is within limits
        if (totalTokensRequested > getSliceOfTreasury(Maths.WAD - getMinimumThresholdPercentage())) revert ExtraordinaryFundingProposalInvalid();

        // store newly created proposal
        ExtraordinaryFundingProposal storage newProposal = extraordinaryFundingProposals[proposalId_];
        newProposal.proposalId = proposalId_;
        newProposal.startBlock = block.number;
        newProposal.endBlock = endBlock_;
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
        if (hasScreened[proposalId_][account_]) revert AlreadyVoted();

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.startBlock > block.number || proposal.endBlock < block.number || proposal.executed == true) {
            revert ExtraordinaryFundingProposalInactive();
        }

        // check voting power at snapshot block
        votes_ = _getVotes(account_, block.number, abi.encode(proposalId_));
        proposal.votesReceived += votes_;

        // check if the proposal has received more votes than minimumThreshold and tokensRequestedPercentage of all tokens
        if (proposal.votesReceived >= proposal.tokensRequested + getSliceOfTreasury(getMinimumThresholdPercentage())) {
            proposal.succeeded = true;
        } else {
            proposal.succeeded = false;
        }

        // record that voter has voted on this extraorindary funding proposal
        hasScreened[proposalId_][account_] = true;

        emit VoteCast(account_, proposalId_, 1, votes_, "");
    }

    function _extraordinaryFundingVoteSucceeded(uint256 proposalId_) internal view returns (bool) {
        return extraordinaryFundingProposals[proposalId_].succeeded;
    }

    /***********************/
    /*** View Functions ****/
    /***********************/

    /**
     * @notice Get the current minimum threshold percentage of Ajna tokens required for a proposal to exceed.
     * @return The minimum threshold percentage, in WAD.
     */
    function getMinimumThresholdPercentage() public view returns (uint256) {
        // default minimum threshold is 50
        if (fundedExtraordinaryProposals.length == 0) {
            return 0.500000000000000000 * 1e18;
        }
        // minimum threshold increases according to the number of funded EFM proposals
        else {
            return 0.500000000000000000 * 1e18 + (fundedExtraordinaryProposals.length * (0.050000000000000000 * 1e18));
        }
    }

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage_ The percentage of the treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getSliceOfTreasury(uint256 percentage_) public view returns (uint256) {
        return Maths.wmul(IERC20(ajnaTokenAddress).balanceOf(address(this)), percentage_);
    }

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
