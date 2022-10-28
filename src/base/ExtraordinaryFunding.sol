// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/governance/Governor.sol";

abstract contract ExtraordinaryFunding is Governor {

    mapping (uint256 => ExtraordinaryFundingProposal) public extraordinaryFundingProposals;

    ExtraordinaryFundingProposal[] public fundedExtraordinaryProposals;

    uint256 public constant MAX_EFM_PROPOSAL_LENGTH = 216000; // number of blocks in one month

    error ExtraordinaryFundingProposalInvalid();

    /**
     * @notice The current block isn't in the specified range of active blocks.
     */
    error ExtraordinaryFundingProposalInactive();

    error ExecuteExtraordinaryProposalInvalid();

    struct ExtraordinaryFundingProposal {
        uint256 proposalId;
        uint256 percentageRequested; // Percentage of the total treasury of AJNA tokens requested.
        uint256 startBlock;          // Block number of the start of the extraordinary funding proposal voting period.
        uint256 endBlock;
        int256  votesReceived;       // Total votes received for this proposal.
        bool    succeeded;
        bool    executed;
    }

    function extraorindaryFundingProposal(
        uint256 percentageRequested_,
        uint256 endBlock_,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_) public returns (uint256 proposalId_) {

        proposalId_ = super.propose(targets_, values_, calldatas_, description_);

        // check proposal length is within limits of 1 month maximum
        if (block.number + MAX_EFM_PROPOSAL_LENGTH < endBlock_) {
            revert ExtraordinaryFundingProposalInvalid();
        }

        // TODO: check calldatas_ matches percentageRequested_

        ExtraordinaryFundingProposal storage newProposal = extraordinaryFundingProposals[proposalId_];
        newProposal.proposalId = proposalId_;
        newProposal.startBlock = block.number;
        newProposal.endBlock = endBlock_;
        newProposal.percentageRequested = percentageRequested_;

        
    }

    // TODO: finish cleaning up this function
    function executeExtraordinaryFundingProposal(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) public returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, descriptionHash_);

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.executed != false || proposal.succeeded != true) {
            revert ExecuteExtraordinaryProposalInvalid();
        }

        proposal.executed = true;
        fundedExtraordinaryProposals.push(proposal);

        super.execute(targets_, values_, calldatas_, descriptionHash_);
    }

    function getExtraordinaryFundingProposal(uint256 proposalId) public view returns (ExtraordinaryFundingProposal memory) {
        return extraordinaryFundingProposals[proposalId];
    }

    function getMinimumThresholdPercentage() public view returns (uint256) {
        // default minimum threshold is 50
        if (fundedExtraordinaryProposals.length == 0) {
            return 50;
        }
        // minimum threshold increases according to the number of funded EFM proposals
        else {
            return 50 + (fundedExtraordinaryProposals.length * 5);
        }
    }

    // TODO: add this to _castVote()
    // else {
        // if (abi.decode(params_, (string)) == "Extraordinary") {
            // _extraordinaryFundingVote(proposalId, account_, support_);
        // }
    // }

    function _extraordinaryFundingVote(uint256 proposalId_, address account_, uint8 support_) internal {
        // if (hasScreened[account_]) revert AlreadyVoted();

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.startBlock > block.number || proposal.endBlock < block.number || proposal.executed == true) {
            revert ExtraordinaryFundingProposalInactive();
        }

        uint256 votes = _getVotes(account_, block.number, bytes("Extraordinary"));

        if (support_ == 1) {
            proposal.votesReceived += int256(votes);
        } else if (support_ == 0) {
            proposal.votesReceived -= int256(votes);
        }

        // TODO: update this to check amounts in absolute vs percentage terms
        if (proposal.votesReceived >= int256(proposal.percentageRequested + getMinimumThresholdPercentage())) {
            proposal.succeeded = true;
        }
        else {
            proposal.succeeded = false;
        }

        // record that voter has already voted on this extraorindary funding proposal
        // hasScreened[account_] = true;

        emit VoteCast(account_, proposalId_, support_, votes, "");
    }

}
