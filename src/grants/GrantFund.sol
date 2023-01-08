// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Governor }    from "@oz/governance/Governor.sol";
import { IGovernor }   from "@oz/governance/IGovernor.sol";
import { IVotes }      from "@oz/governance/utils/IVotes.sol";
import { Checkpoints } from "@oz/utils/Checkpoints.sol";

import { Maths } from "./libraries/Maths.sol";

import { ExtraordinaryFunding } from "./base/ExtraordinaryFunding.sol";
import { StandardFunding }      from "./base/StandardFunding.sol";

import { IGrantFund } from "./interfaces/IGrantFund.sol";

contract GrantFund is IGrantFund, ExtraordinaryFunding, StandardFunding {

    using Checkpoints for Checkpoints.History;

    IVotes public immutable token;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(IVotes token_, uint256 treasury_)
        Governor("AjnaEcosystemGrantFund")
    {
        ajnaTokenAddress = address(token_);
        token = token_;
        treasury = treasury_;
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Overide the default proposal function to ensure all proposal submission travel through expected mechanisms.
     */
    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) public pure override(Governor) returns (uint256) {
        revert InvalidProposal();
    }

    /**
     * @notice Overriding the default execute function to ensure all proposals travel through expected mechanisms.
     */
    function execute(address[] memory, uint256[] memory, bytes[] memory, bytes32) public payable override(Governor) returns (uint256) {
        revert MethodNotImplemented();
    }

    /**
     * @notice Given a proposalId, find if it is a standard or extraordinary proposal.
     * @param proposalId_ The id of the proposal to query the mechanism of.
     * @return FundingMechanism to which the proposal was submitted.
     */
    function findMechanismOfProposal(uint256 proposalId_) public view returns (FundingMechanism) {
        if (standardFundingProposals[proposalId_].proposalId != 0) return FundingMechanism.Standard;
        else if (extraordinaryFundingProposals[proposalId_].proposalId != 0) return FundingMechanism.Extraordinary;
        else revert ProposalNotFound();
    }

    /**
     * @notice Find the status of a given proposal.
     * @dev Overrides Governor.state() to check proposal status based upon Grant Fund specific logic.
     * @param proposalId_ The id of the proposal to query the status of.
     * @return ProposalState of the given proposal.
     */
    function state(uint256 proposalId_) public view override(Governor) returns (IGovernor.ProposalState) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // standard proposal state checks
        if (mechanism == FundingMechanism.Standard) {
            Proposal memory proposal = standardFundingProposals[proposalId_];
            if (proposal.executed) return IGovernor.ProposalState.Executed;
            else if (distributions[proposal.distributionId].endBlock >= block.number) return IGovernor.ProposalState.Active;
            else if (_standardFundingVoteSucceeded(proposalId_)) return IGovernor.ProposalState.Succeeded;
            else return IGovernor.ProposalState.Defeated;
        }
        // extraordinary funding proposal state
        else {
            bool voteSucceeded = _extraordinaryFundingVoteSucceeded(proposalId_);

            if (extraordinaryFundingProposals[proposalId_].executed) return IGovernor.ProposalState.Executed;
            else if (extraordinaryFundingProposals[proposalId_].endBlock >= block.number && !voteSucceeded) return IGovernor.ProposalState.Active;
            else if (voteSucceeded) return IGovernor.ProposalState.Succeeded;
            else return IGovernor.ProposalState.Defeated;
        }
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @notice Vote on a proposal in the screening or funding stage of the Distribution Period.
     * @dev Override channels all other castVote methods through here.
     * @param proposalId_ The current proposal being voted upon.
     * @param account_    The voting account.
     * @param params_     The amount of votes being allocated in the funding stage.
     * @return votesCast_ The amount of votes cast.
     */
     function _castVote(uint256 proposalId_, address account_, uint8, string memory, bytes memory params_) internal override(Governor) returns (uint256 votesCast_) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // standard funding mechanism
        if (mechanism == FundingMechanism.Standard) {
            Proposal storage proposal = standardFundingProposals[proposalId_];
            QuarterlyDistribution memory currentDistribution = distributions[proposal.distributionId];
            uint256 screeningPeriodEndBlock = currentDistribution.endBlock - 72000;

            // screening stage
            if (block.number >= currentDistribution.startBlock && block.number <= screeningPeriodEndBlock) {
                uint256 votes = _getVotes(account_, block.number, bytes("Screening"));

                votesCast_ = _screeningVote(account_, proposal, votes);
            }

            // funding stage
            else if (block.number > screeningPeriodEndBlock && block.number <= currentDistribution.endBlock) {
                QuadraticVoter storage voter = quadraticVoters[currentDistribution.id][account_];

                // this is the first time a voter has attempted to vote this period
                if (voter.votingWeight == 0) {
                    voter.votingWeight = Maths.wpow(_getVotesSinceSnapshot(account_, screeningPeriodEndBlock - 33, screeningPeriodEndBlock), 2);
                    voter.budgetRemaining = int256(voter.votingWeight);
                }

                // amount of quadratic budget to allocated to the proposal
                int256 budgetAllocation = abi.decode(params_, (int256));

                // check if the voter has enough budget remaining to allocate to the proposal
                if (Maths.abs(budgetAllocation) > voter.budgetRemaining) revert InsufficientBudget();

                votesCast_ = _fundingVote(proposal, account_, voter, budgetAllocation);
            }
        }

        // extraordinary funding mechanism
        else {
            votesCast_ = _extraordinaryFundingVote(proposalId_, account_);
        }
    }

    /**
     * @notice Calculates the number of votes available to an account depending on the current stage of the Distribution Period.
     * @dev    Overrides OpenZeppelin _getVotes implementation to ensure appropriate voting weight is always returned.
     * @dev    Snapshot checks are built into this function to ensure accurate power is returned regardless of the caller.
     * @dev    Number of votes available is equivalent to the usage of voting weight in the super class.
     * @param  account_        The voting account.
     * @param  params_         Params used to pass stage for Standard, and proposalId for extraordinary.
     * @return availableVotes_ The number of votes available to an account in a given stage.
     */
    function _getVotes(address account_, uint256, bytes memory params_) internal view override(Governor) returns (uint256 availableVotes_) {
        QuarterlyDistribution memory currentDistribution = distributions[distributionIdCheckpoints.latest()];

        // within screening period 1 token 1 vote
        if (keccak256(params_) == keccak256(bytes("Screening"))) {
            // calculate voting weight based on the number of tokens held before the start of the distribution period
            availableVotes_ = _getVotesSinceSnapshot(account_, currentDistribution.startBlock - 33, currentDistribution.startBlock);
        }
        // else if in funding period quadratic formula squares the number of votes
        else if (keccak256(params_) == keccak256(bytes("Funding"))) {
            QuadraticVoter memory voter = quadraticVoters[currentDistribution.id][account_];

            // voter has already allocated some of their budget this period
            if (voter.votingWeight != 0) {
                availableVotes_ = uint256(voter.budgetRemaining);
            }
            // this is the first time a voter has attempted to vote this period
            else {
                availableVotes_ = Maths.wpow(_getVotesSinceSnapshot(account_, currentDistribution.endBlock - 72033, currentDistribution.endBlock - 72000), 2);
            }
        }
        else {
            if (params_.length != 0) {
                // attempt to decode a proposalId from the params
                uint256 proposalId = abi.decode(params_, (uint256));

                // one token one vote for extraordinary funding
                if (proposalId != 0) {
                    uint256 startBlock = extraordinaryFundingProposals[proposalId].startBlock;
                    availableVotes_ = _getVotesSinceSnapshot(account_, startBlock - 33, startBlock);
                }
            }
            // voting is not possible for non-specified pathways
            else {
                availableVotes_ = 0;
            }
        }
    }

     /**
     * @notice Retrieve the voting power of an account.
     * @dev    Voteing power is the minimum of the amount of votes available at a snapshot block 33 blocks prior to voting start, and at the vote starting block.
     * @param account_        The voting account.
     * @param snapshot_       One of block numbers to retrieve the voting power at. 33 blocks prior to the vote starting block.
     * @param voteStartBlock_ The block number the vote started at.
     * @return                The voting power of the account.
     */
    function _getVotesSinceSnapshot(address account_, uint256 snapshot_, uint256 voteStartBlock_) internal view returns (uint256) {
        uint256 votes1 = token.getPastVotes(account_, snapshot_);

        // enable voting weight to be calculated during the voting period's start block
        voteStartBlock_ = voteStartBlock_ != block.number ? voteStartBlock_ : block.number - 1;
        uint256 votes2 = token.getPastVotes(account_, voteStartBlock_);

        return Maths.min(votes2, votes1);
    }

    /**************************/
    /*** Required Overrides ***/
    /**************************/

     /**
     * @notice Check whether an account has voted on a proposal.
     * @dev    Votes can only votes once during the screening stage, and only once on proposals in the extraordinary funding round.
               In the funding stage they can vote as long as they have budget.
     * @dev    See {IGovernor-hasVoted}.
     * @return hasVoted_ Boolean for whether the account has already voted in the current proposal, and mechanism.
     */
    function hasVoted(uint256 proposalId_, address account_) public view override(IGovernor) returns (bool hasVoted_) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // Checks if Proposal is Standard
        if (mechanism == FundingMechanism.Standard) {
            Proposal memory proposal = standardFundingProposals[proposalId_]; 
            QuarterlyDistribution memory currentDistribution = distributions[proposal.distributionId];
            uint256 screeningPeriodEndBlock = currentDistribution.endBlock - 72000;

            // screening stage
            if (block.number >= currentDistribution.startBlock && block.number <= screeningPeriodEndBlock) {
                hasVoted_ = hasVotedScreening[proposal.distributionId][account_];
            }

            // funding stage
            else if (block.number > screeningPeriodEndBlock && block.number <= currentDistribution.endBlock) {
                QuadraticVoter storage voter = quadraticVoters[currentDistribution.id][account_];

                // Check if voter has voted
                if (uint256(voter.budgetRemaining) < voter.votingWeight) {
                    hasVoted_ = true;
                }
            }
        }
        else {
            hasVoted_ = hasVotedExtraordinary[proposalId_][account_];
        }
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // slither-disable-next-line naming-convention
    function COUNTING_MODE() public pure override(IGovernor) returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @notice Required override; not currently used due to divergence in voting logic.
     * @dev    See {IGovernor-_countVote}.
     */
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory) internal override(Governor) {}

    /**
     * @notice Required override used in Governor.state()
     * @dev Since no quorum is used, but this is called as part of state(), this is hardcoded to true.
     * @dev See {IGovernor-quorumReached}.
     */
    // slither-disable-next-line dead-code
    function _quorumReached(uint256) internal pure override(Governor) returns (bool) {
        return true;
    }

   /**
     * @notice Required override; not currently used due to divergence in voting logic.
     * @dev    See {IGovernor-quorum}.
     */
    function quorum(uint256) public pure override(IGovernor) returns (uint256) {}

   /**
     * @notice Required override; not currently used due to divergence in voting logic.
     * @dev    Replaced by mechanism specific voteSucceeded functions.
     * @dev    See {IGovernor-quorum}.
     */
    // slither-disable-next-line dead-code
    function _voteSucceeded(uint256 proposalId) internal view override(Governor) returns (bool) {}

    /**
     * @notice Required override.
     * @dev    Since no voting delay is implemented, this is hardcoded to 0.
     */
    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return 0;
    }

    /**
     * @notice Required override; see {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view override(IGovernor) returns (uint256) {}

}
