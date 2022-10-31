// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/token/ERC20/IERC20.sol";

import "./Funding.sol";

import "../interfaces/IExtraordinaryFunding.sol";

import "../libraries/Maths.sol";

import "@std/console.sol";

abstract contract ExtraordinaryFunding is Funding, IExtraordinaryFunding {

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping (uint256 => ExtraordinaryFundingProposal) public extraordinaryFundingProposals;

    ExtraordinaryFundingProposal[] public fundedExtraordinaryProposals;

    uint256 public constant MAX_EFM_PROPOSAL_LENGTH = 216_000; // number of blocks in one month

    uint256 internal immutable extraordinaryFundingBaseQuorum = 50;

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    function proposeExtraordinary(
        uint256 percentageRequested_, // WAD
        uint256 endBlock_,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_) public returns (uint256 proposalId_) {

        proposalId_ = hashProposal(targets_, values_, calldatas_, keccak256(bytes(description_)));

        // check proposal length is within limits of 1 month maximum
        if (block.number + MAX_EFM_PROPOSAL_LENGTH < endBlock_) {
            revert ExtraordinaryFundingProposalInvalid();
        }

        uint256 totalTokensRequested = 0;

        // check proposal attributes are valid
        for (uint256 i = 0; i < targets_.length;) {

            // check  targets and values are valid
            if (targets_[i] != ajnaTokenAddress) revert InvalidTarget();
            if (values_[i] != 0) revert InvalidValues();

            // check calldata function selector is transfer()
            bytes memory selDataWithSig = calldatas_[i];

            bytes4 selector;
            //slither-disable-next-line assembly
            assembly {
                selector := mload(add(selDataWithSig, 0x20))
            }
            if (selector != bytes4(0xa9059cbb)) revert InvalidSignature();

            // https://github.com/ethereum/solidity/issues/9439
            // retrieve tokensRequested from incoming calldata, accounting for selector and recipient address
            uint256 tokensRequested;
            bytes memory tokenDataWithSig = calldatas_[i];
            //slither-disable-next-line assembly
            assembly {
                tokensRequested := mload(add(tokenDataWithSig, 68))
            }

            // update tokens requested for additional calldata
            totalTokensRequested += tokensRequested;

            unchecked {
                ++i;
            }
        }

        // check calldatas_ matches percentageRequested_
        if (totalTokensRequested != getPercentageOfTreasury(percentageRequested_)) revert ExtraordinaryFundingProposalInvalid();

        ExtraordinaryFundingProposal storage newProposal = extraordinaryFundingProposals[proposalId_];
        newProposal.proposalId = proposalId_;
        newProposal.startBlock = block.number;
        newProposal.endBlock = endBlock_;
        newProposal.percentageRequested = percentageRequested_;

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

    // TODO: add reentrancy check
    // TODO: finish cleaning up this function
    function executeExtraordinary(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) public returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, descriptionHash_);

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.executed != false || proposal.succeeded != true) {
            revert ExecuteExtraordinaryProposalInvalid();
        }

        fundedExtraordinaryProposals.push(proposal);

        super.execute(targets_, values_, calldatas_, descriptionHash_);
        proposal.executed = true;
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    function _extraordinaryFundingVote(uint256 proposalId_, address account_, uint8 support_) internal returns (uint256 votes_) {
        if (hasScreened[proposalId_][account_]) revert AlreadyVoted();

        ExtraordinaryFundingProposal storage proposal = extraordinaryFundingProposals[proposalId_];

        if (proposal.startBlock > block.number || proposal.endBlock < block.number || proposal.executed == true) {
            revert ExtraordinaryFundingProposalInactive();
        }

        // check voting power at snapshot block
        votes_ = _getVotes(account_, proposal.startBlock - 33, bytes("Extraordinary"));

        if (support_ == 1) {
            proposal.votesReceived += int256(votes_);
        } else if (support_ == 0) {
            proposal.votesReceived -= int256(votes_);
        }

        // TODO: update this to check amounts in absolute vs percentage terms
        if (uint256(proposal.votesReceived) >= getPercentageOfTreasury(proposal.percentageRequested + getMinimumThresholdPercentage())) {
            proposal.succeeded = true;
        }
        else {
            proposal.succeeded = false;
        }

        // record that voter has voted on this extraorindary funding proposal
        hasScreened[proposalId_][account_] = true;

        emit VoteCast(account_, proposalId_, support_, votes_, "");
    }

    // TODO: finish implementing
    function _extraordinaryFundingVoteSucceeded(uint256 proposalId_) internal view returns (bool) {
        return extraordinaryFundingProposals[proposalId_].succeeded;
    }

    /***********************/
    /*** View Functions ****/
    /***********************/

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

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage_ The percentage of the treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getPercentageOfTreasury(uint256 percentage_) public view returns (uint256) {
        return Maths.wmul(IERC20(ajnaTokenAddress).balanceOf(address(this)), percentage_);
    }

    function getExtraordinaryProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, uint256, int256, bool, bool) {
        ExtraordinaryFundingProposal memory proposal = extraordinaryFundingProposals[proposalId_];
        return (
            proposal.proposalId,
            proposal.percentageRequested,
            proposal.startBlock,
            proposal.endBlock,
            proposal.votesReceived,
            proposal.succeeded,
            proposal.executed
        );
    }

}
