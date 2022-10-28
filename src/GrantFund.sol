// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/governance/Governor.sol";
import "@oz/governance/extensions/GovernorVotes.sol";
import "@oz/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@oz/governance/IGovernor.sol";
import "@oz/governance/utils/IVotes.sol";
import "@oz/security/ReentrancyGuard.sol";
import "@oz/token/ERC20/IERC20.sol";
import "@oz/utils/Checkpoints.sol";

import "./libraries/Maths.sol";

import "./interfaces/IGrantFund.sol";

import "./base/ExtraordinaryFunding.sol";
import "./base/StandardFunding.sol";


contract GrantFund is IGrantFund, ExtraordinaryFunding, StandardFunding, GovernorVotesQuorumFraction, ReentrancyGuard {

    using Checkpoints for Checkpoints.History;

    /***********************/
    /*** State Variables ***/
    /***********************/

    //  base quorum percentage required for extraordinary funding is 50%
    uint256 internal immutable extraordinaryFundingBaseQuorum = 50;

    // // address of the ajna token used in grant coordination
    // address public ajnaTokenAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(IVotes token_)
        Governor("AjnaEcosystemGrantFund")
        GovernorVotes(token_) // token that will be used for voting
        GovernorVotesQuorumFraction(4) // percentage of total voting power required; updateable via governance proposal
    {
        ajnaTokenAddress = address(token_);
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Submit a new proposal to the Grant Coordination Fund
     * @dev    All proposals can be submitted by anyone. There can only be one value in each array. Interface inherits from OZ.propose().
     * @param  targets_ List of contracts the proposal calldata will interact with. Should be the Ajna token contract for all proposals.
     * @param  values_ List of values to be sent with the proposal calldata. Should be 0 for all proposals.
     * @param  calldatas_ List of calldata to be executed. Should be the transfer() method.
     * @return proposalId_ The id of the newly created proposal.
     */
    function propose(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) public override(Governor) returns (uint256 proposalId_) {
        proposalId_ = super.propose(targets_, values_, calldatas_, description_);

        // store new proposal information
        Proposal storage newProposal = proposals[proposalId_];
        newProposal.proposalId = proposalId_;
        newProposal.distributionId = _distributionIdCheckpoints.latest();

        // check proposal parameters are valid and update tokensRequested
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
            newProposal.tokensRequested += tokensRequested;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Execute a proposal that has been approved by the community.
     * @dev    Calls out to Governor.execute()
     * @dev    Check for proposal being succesfully funded or previously executed is handled by Governor.execute().
     * @return proposalId_ of the executed proposal.
     */
    function execute(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) public payable override(Governor) nonReentrant returns (uint256) {
        // check that the distribution period has ended, and one week has passed to enable competing slates to be checked
        if (block.number <= distributions[_distributionIdCheckpoints.latest()].endBlock + 50400) revert ExecuteProposalInvalid();

        return super.execute(targets_, values_, calldatas_, descriptionHash_);
    }

    /**
     * @dev Required override; we don't currently have a threshold to create a proposal so this returns the default value of 0
     */
    function proposalThreshold() public view override(Governor) returns (uint256) {
        return super.proposalThreshold();
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
     */
     function _castVote(uint256 proposalId_, address account_, uint8, string memory, bytes memory params_) internal override(Governor) returns (uint256) {
        Proposal storage proposal = proposals[proposalId_];
        QuarterlyDistribution memory currentDistribution = distributions[proposal.distributionId];

        uint256 screeningPeriodEndBlock = currentDistribution.endBlock - 72000;
        bytes memory stage;
        uint256 votes;

        // screening stage
        if (block.number >= currentDistribution.startBlock && block.number <= screeningPeriodEndBlock) {
            stage = bytes("Screening");
            votes = _getVotes(account_, block.number, stage);

            return _screeningVote(account_, proposal, votes);
        }

        // funding stage
        else if (block.number > screeningPeriodEndBlock && block.number <= currentDistribution.endBlock) {
            stage = bytes("Funding");

            QuadraticVoter storage voter = quadraticVoters[currentDistribution.id][account_];

            // this is the first time a voter has attempted to vote this period
            if (voter.votingWeight == 0) {
                voter.votingWeight = Maths.wpow(super._getVotes(account_, screeningPeriodEndBlock - 33, ""), 2);
                voter.budgetRemaining = int256(voter.votingWeight);
            }

            // amount of quadratic budget to allocated to the proposal
            int256 budgetAllocation = abi.decode(params_, (int256));

            // check if the voter has enough budget remaining to allocate to the proposal
            if (voter.budgetRemaining == 0 || budgetAllocation > voter.budgetRemaining) revert InsufficientBudget();

            return _fundingVote(proposal, account_, voter, budgetAllocation);
        }
        else {
            // TODO: finsih implementing extraordinary funding mechanism pathway
            // if (abi.decode(params_, (string)) == bytes("Extraordinary")) {
                // TODO: set support_ variable
                _extraordinaryFundingVote(proposalId_, account_, 1);
            // }
        }
    }

    /**
     * @notice Calculates the number of votes available to an account depending on the current stage of the Distribution Period.
     * @dev    Overrides OpenZeppelin _getVotes implementation to ensure appropriate voting weight is always returned.
     * @dev    Snapshot checks are built into this function to ensure accurate power is returned regardless of the caller.
     * @dev    Number of votes available is equivalent to the usage of voting weight in the super class.
     * @param  account_     The voting account.
     * @param  blockNumber_ The block number to check the snapshot at.
     * @param  stage_       The stage of the distribution period, or signifier of the vote being part of the extraordinary funding mechanism.
     * @return The number of votes available to an account in a given stage.
     */
    function _getVotes(address account_, uint256 blockNumber_, bytes memory stage_) internal view override(Governor, GovernorVotes) returns (uint256) {
        QuarterlyDistribution memory currentDistribution = distributions[_distributionIdCheckpoints.latest()];

        // within screening period 1 token 1 vote
        if (keccak256(stage_) == keccak256(bytes("Screening"))) {
            // calculate voting weight based on the number of tokens held before the start of the distribution period
            return currentDistribution.startBlock == 0 ? 0 : super._getVotes(account_, currentDistribution.startBlock - 33, "");
        }
        // else if in funding period quadratic formula squares the number of votes
        else if (keccak256(stage_) == keccak256(bytes("Funding"))) {
            QuadraticVoter memory voter = quadraticVoters[currentDistribution.id][account_];
            // this is the first time a voter has attempted to vote this period
            if (voter.votingWeight == 0) {
                return Maths.wpow(super._getVotes(account_, currentDistribution.endBlock - 72033, ""), 2);
            }
            // voter has already allocated some of their budget this period
            else {
                return uint256(voter.budgetRemaining);
            }
        }
        // one token one vote for extraordinary funding
        else if (keccak256(stage_) == keccak256(bytes("Extraordinary"))) {
            return super._getVotes(account_, blockNumber_, "");
        }
        // voting is not possible for non-specified pathways
        else {
            return 0;
        }
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    //slither-disable-next-line naming-convention
    function COUNTING_MODE() public pure override(IGovernor) returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @notice Restrict voter to only voting once during the screening stage.
     * @dev    See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256, address account_) public view override(IGovernor) returns (bool) {
        return hasScreened[account_];
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
    function _quorumReached(uint256) internal pure override(Governor) returns (bool) {
        return true;
    }

    function _voteSucceeded(uint256 proposalId_) internal view override(Governor) returns (bool) {
        uint256 distributionId = _distributionIdCheckpoints.latest();
        return _findProposalIndex(proposalId_, fundedProposalSlates[distributionId][distributions[distributionId].fundedSlateHash]) != -1;
    }

    /**
     * @notice Required ovverride.
     * @dev    Since no voting delay is implemented, this is hardcoded to 0.
     */
    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculates the remaining blocks left in the current voting period
     * @dev    Required ovverride; see {IGovernor-votingPeriod}.
     * @return The remaining number of blocks.
     */
    function votingPeriod() public view override(IGovernor) returns (uint256) {
        QuarterlyDistribution memory currentDistribution = distributions[_distributionIdCheckpoints.latest()];
        uint256 screeningPeriodEndBlock = currentDistribution.endBlock - 72000;

        if (block.number < screeningPeriodEndBlock) {
            return screeningPeriodEndBlock - block.number;
        }
        else if (block.number > screeningPeriodEndBlock && block.number < currentDistribution.endBlock) {
            return currentDistribution.endBlock - block.number;
        }
        // TODO: implement exraordinary funding mechanism
        else {
            return 0;
        }
    }

    /*****************************/
    /*** Extraordinary Funding ***/
    /*****************************/

    /**
     * @notice Get the current extraordinaryFundingBaseQuorum required to pass an extraordinary funding proposal.
     */
    function getExtraordinaryFundingQuorum(uint256 blockNumber, uint256 tokensRequested) external view returns (uint256) {
    }

    // TODO: implement custom override - need to support both regular votes, and the extraordinaryFunding mechanism
    function quorum(uint256 blockNumber) public view override(IGovernor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

}
