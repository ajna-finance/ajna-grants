// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Checkpoints } from "@oz/utils/Checkpoints.sol";

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { Governor } from "@oz/governance/Governor.sol";
import { GovernorVotes } from "@oz/governance/extensions/GovernorVotes.sol";
import { GovernorVotesQuorumFraction } from "@oz/governance/extensions/GovernorVotesQuorumFraction.sol";
import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";

import { Maths } from "./libraries/Maths.sol";

import { IGrowthFund } from "./interfaces/IGrowthFund.sol";

import { AjnaToken } from "./AjnaToken.sol";

import { console } from "@std/console.sol";


// TODO: remove burning
// TODO: implement budget

contract GrowthFund is IGrowthFund, Governor, GovernorVotesQuorumFraction {

    using Checkpoints for Checkpoints.History;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 internal extraordinaryFundingBaseQuorum;

    address public   votingTokenAddress;
    AjnaToken  internal ajnaToken;

    // TODO: update this from a percentage to just the numerator?
    /**
     * @notice Maximum percentage of tokens that can be distributed by the treasury in a quarter.
     * @dev Stored as a Wad percentage.
     */
    uint256 public globalBudgetConstraint = Maths.wdiv(Maths.wad(2), Maths.wad(100));

    /**
     * @notice Length of the distribution period in blocks.
     */
    uint256 public distributionPeriodLength = 183272; // 4 weeks

    /**
     * @notice ID of the current distribution period.
     * @dev Used to access information on the status of an ongoing distribution.
     * @dev Updated at the start of each quarter.
     */
    Checkpoints.History private _distributionIdCheckpoints;

    /**
     * @notice Mapping of quarterly distributions from the growth fund.
     * @dev distributionId => QuarterlyDistribution
     */
    mapping(uint256 => QuarterlyDistribution) distributions;

    /**
     * @notice Mapping checking if a voter has voted on a proposal during the screening stage in a quarter.
     * @dev Reset to false at the start of each new quarter.
     */
    mapping(address => bool) hasScreened;

    /**
     * @dev Mapping of all proposals that have ever been submitted to the growth fund for screening.
     * @dev distribution.id => proposalId => Proposal
     */
    mapping(uint256 => Proposal) proposals;

    /**
     * @dev Mapping of distributionId to a sorted array of 10 proposals with the most votes in the screening period.
     * @dev distribution.id => Proposal[]
     * @dev A new array is created for each distribution period
     */
    mapping(uint256 => Proposal[]) topTenProposals;

    /**
     * @notice Mapping of quarterly distributions to a hash of a proposal slate to a list of funded proposals.
     * @dev distributionId => slate hash => Proposal[]
     */
    mapping(uint256 => mapping(bytes32 => Proposal[])) fundedProposalSlates;

    /**
     * @notice Mapping of quarterly distributions to voters to a Quadratic Voter info struct.
     * @dev distributionId => voter address => QuadraticVoter 
     */
    mapping (uint256 => mapping(address => QuadraticVoter)) quadraticVoters;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    // TODO: replace with governorCountingSimple.hasVoted?
    /**
     * @notice Restrict a voter to only voting on one proposal during the screening stage.
     */
    modifier onlyScreenOnce() {
        if (hasScreened[msg.sender]) revert AlreadyVoted();
        _;
    }

    // TODO: add revert if length is greater than 1
    /**
     * @notice Ensure a proposal matches GrowthFund specifications.
     * @dev Targets_ should be the Ajna token contract, values_ should be 0, and calldatas_ should be transfer().
     * @param targets_   List of contract addresses the proposal interacts with.
     * @param values_    List of wei amounts to call the target address with.
     * @param calldatas_ List of calldatas to execute if the proposal is successful.
     */
    modifier checkProposal(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_) {
        for (uint i = 0; i < targets_.length;) {

            if (targets_[i] != votingTokenAddress) revert InvalidTarget();
            if (values_[i] != 0) revert InvalidValues();

            // check calldata function selector is transfer()
            bytes memory dataWithSig = calldatas_[i];
            bytes4 selector;
            assembly {
                selector := mload(add(dataWithSig, 0x20))
            }
            if (selector != bytes4(0xa9059cbb)) revert InvalidSignature();

            unchecked {
                ++i;
            }
        }
        _;
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(IVotes token_)
        Governor("AjnaEcosystemGrowthFund")
        GovernorVotes(token_) // token that will be used for voting
        GovernorVotesQuorumFraction(4) // percentage of total voting power required; updateable via governance proposal
    {
        extraordinaryFundingBaseQuorum = 50; // initialize base quorum percentrage required for extraordinary funding to 50%

        votingTokenAddress = address(token_);
        ajnaToken          = AjnaToken(address(token_));
    }

    /*****************************/
    /*** Standard Distribution ***/
    /*****************************/

    /**
     * @notice Set a new DistributionPeriod Id.
     * @dev    Increments the previous Id nonce by 1, and sets a checkpoint at the calling block.number.
     */
    function _setNewDistributionId() private {
        // increment the distributionId
        uint256 currentDistributionId = getDistributionId();
        uint256 newDistributionId = currentDistributionId += 1;

        // set the current block number as the checkpoint for the current block
        _distributionIdCheckpoints.push(newDistributionId);
    }

    function getDistributionId() public view returns (uint256) {
        return _distributionIdCheckpoints.latest();
    }

    function getDistributionIdAtBlock(uint256 blockNumber) public view returns (uint256) {
        return _distributionIdCheckpoints.getAtBlock(blockNumber);
    }

    // TODO: implement this -> uses enums instead of block number to determine what phase for voting
    //         DistributionPhase phase = distributionPhase()
    function getDistributionPhase(uint256 distributionId_) public view returns (DistributionPhase) {
    }

    function getDistributionPeriodInfo(uint256 distributionId_) external view returns (uint256, uint256, uint256, uint256, bytes32) {
        QuarterlyDistribution memory distribution = distributions[distributionId_];
        return (
            distribution.id,
            distribution.votesCast,
            distribution.startBlock,
            distribution.endBlock,
            distribution.fundedSlateHash
        );
    }

    /**
     * @notice Get the funded proposal slate for a given distributionId, and slate hash
     */
    function getFundedProposalSlate(uint256 distributionId_, bytes32 slateHash_) external view returns (Proposal[] memory) {
        return fundedProposalSlates[distributionId_][slateHash_];
    }

    function getProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, uint256, int256, bool, bool) {
        Proposal memory proposal = proposals[proposalId_];
        return (
            proposal.proposalId,
            proposal.distributionId,
            proposal.votesReceived,
            proposal.tokensRequested,
            proposal.fundingReceived,
            proposal.succeeded,
            proposal.executed
        );
    }

    function getVoterInfo(uint256 distributionId_, address account_) external view returns (int256, int256, bytes32) {
        QuadraticVoter memory voter = quadraticVoters[distributionId_][account_];
        return (
            voter.votingWeight,
            voter.budgetRemaining,
            voter.commitment
        );
    }

    function getTopTenProposals(uint256 distributionId_) external view returns (Proposal[] memory) {
        return topTenProposals[distributionId_];
    }

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    /**
     * @notice Start a new Distribution Period and reset appropiate state.
     * @dev    Can be kicked off by anyone assuming a distribution period isn't already active.
     */
    function startNewDistributionPeriod() public returns (uint256) {
        QuarterlyDistribution memory lastDistribution = distributions[getDistributionId()];

        // check that there isn't currently an active distribution period
        if (block.number <= lastDistribution.endBlock) revert DistributionPeriodStillActive();

        // TODO: calculate starting and ending block properly -> should startBlock be the current block?
        uint256 startBlock = block.number;
        uint256 endBlock = startBlock + distributionPeriodLength;

        // set new value for currentDistributionId
        _setNewDistributionId();

        uint256 newDistributionId = getDistributionId();

        // create QuarterlyDistribution struct
        QuarterlyDistribution storage newDistributionPeriod = distributions[newDistributionId];
        newDistributionPeriod.id =  newDistributionId;
        newDistributionPeriod.startBlock = startBlock;
        newDistributionPeriod.endBlock = endBlock;

        emit QuarterlyDistributionStarted(newDistributionId, startBlock, endBlock);
        return newDistributionPeriod.id;
    }

    function _sumFundingReceived(Proposal[] memory proposalSubset_) internal pure returns (uint256 sum) {
        sum = 0;
        for (uint i = 0; i < proposalSubset_.length;) {
            sum += uint256(proposalSubset_[i].fundingReceived);

            unchecked {
                ++i;
            }
        }
    }

    function getSlateHash(Proposal[] calldata proposals_) public pure returns (bytes32) {
        return keccak256(abi.encode(proposals_));
    }

    function _updateFundedSlate(Proposal[] calldata fundedProposals_, QuarterlyDistribution storage currentDistribution_, bytes32 slateHash_) internal {
        for (uint i = 0; i < fundedProposals_.length; ) {

            // update list of proposals to fund
            fundedProposalSlates[currentDistribution_.id][slateHash_].push(fundedProposals_[i]);

            unchecked {
                ++i;
            }
        }

        // update hash to point to the new leading slate of proposals
        currentDistribution_.fundedSlateHash = slateHash_;
    }

    /**
     * @notice Check if a slate of proposals meets requirements, and maximizes votes. If so, update QuarterlyDistribution.
     * @return Boolean indicating whether the new proposal slate was set as the new slate for distribution.
     */
    function checkSlate(Proposal[] calldata fundedProposals_, uint256 distributionId_) public returns (bool) {
        QuarterlyDistribution storage currentDistribution = distributions[distributionId_];

        // check that the function is being called within the challenge period
        if (block.number <= currentDistribution.endBlock || block.number > currentDistribution.endBlock + 50400) {
            return false;
        }

        uint256 gbc = maximumQuarterlyDistribution();
        uint256 sum = 0;
        uint256 totalTokensRequested = 0;

        for (uint i = 0; i < fundedProposals_.length; ) {
            // check if Proposal is in the topTenProposals list
            if (_findInArray(fundedProposals_[i].proposalId, topTenProposals[distributionId_]) == -1) return false;

            // TODO: account for fundingReceived possibly being negative
            // update counters
            sum += uint256(fundedProposals_[i].fundingReceived);
            totalTokensRequested += fundedProposals_[i].tokensRequested;

            // check if slate of proposals exceeded budget constraint
            if (totalTokensRequested > gbc) {
                return false;
            }

            unchecked {
                ++i;
            }
        }

        // get pointers for comparing proposal slates
        bytes32 currentSlateHash = currentDistribution.fundedSlateHash;
        bytes32 newSlateHash = getSlateHash(fundedProposals_);

        // check if current slate received more support than the current leading slate
        if (currentSlateHash != 0) {
            if (sum > _sumFundingReceived(fundedProposalSlates[distributionId_][currentSlateHash])) {

                _updateFundedSlate(fundedProposals_, currentDistribution, newSlateHash);
                return true;
            }
        }
        // set as first slate of funded proposals
        else {
            _updateFundedSlate(fundedProposals_, currentDistribution, newSlateHash);
            return true;
        }

        return false;
    }

    /**
     * @notice Get the current maximum possible distribution of Ajna tokens that will be released from the treasury this quarter.
     */
    function maximumQuarterlyDistribution() public view returns (uint256) {
        uint256 growthFundBalance = ajnaToken.balanceOf(address(this));
        return Maths.wmul(growthFundBalance, globalBudgetConstraint);
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) checkProposal(targets, values, calldatas) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        // https://github.com/ethereum/solidity/issues/9439
        // retrieve tokensRequested from incoming calldata, accounting for selector and recipient address
        bytes memory dataWithSig = calldatas[0];
        uint256 tokensRequested;
        assembly {
            tokensRequested := mload(add(dataWithSig, 68))
        }

        // store new proposal information
        Proposal storage newProposal = proposals[proposalId];
        newProposal.proposalId = proposalId;
        newProposal.distributionId = getDistributionId();
        newProposal.tokensRequested = tokensRequested;

        return super.propose(targets, values, calldatas, description);
    }

    /**
     * @notice Execute a proposal that has been approved by the community.
     * @dev    Calls out to Governor.execute()
     * @return proposalId of the executed proposal.
     */
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) public payable override(Governor) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage proposal = proposals[proposalId];

        // check if propsal is in the fundedProposalSlates list
        if (_findInArray(proposalId, fundedProposalSlates[proposal.distributionId][distributions[proposal.distributionId].fundedSlateHash]) == -1) {
            revert ProposalNotFunded();
        }

        // check that the distribution period has ended, and it hasn't already been executed
        if (block.number <= distributions[proposal.distributionId].endBlock + 50400 || proposals[proposalId].executed) revert ExecuteProposalInvalid();

        // update proposal state
        proposal.succeeded = true;
        proposal.executed = true;

        super.execute(targets, values, calldatas, descriptionHash);
        return proposalId;
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure override(IGovernor) returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @dev See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId, address account_) public view override(IGovernor) returns (bool) {
        if (hasScreened[account_]) return true;
    }

    // TODO: finish implementing
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory) internal override(Governor) {
        // TODO: check if voter has already voted - or do it above based upon the funding flow?
    }

    // TODO: finish implementing -> add flag to see if the vote is for a StandardProposal or ExtraordinaryFundingProposal
    function _quorumReached(uint256 proposalId) internal view override(Governor) returns (bool) {
        return true;
    }

    function _voteSucceeded(uint256 proposalId_) internal view override(Governor) returns (bool) {
        return proposals[proposalId_].succeeded;
    }

    // TODO: may want to replace the conditional checks of stage here with the DistributionPhase enum
    /**
     * @notice Vote on a proposal in the screening or funding stage of the Distribution Period.
     * @dev Override channels all other castVote methods through here.
     * @param proposalId_ The current proposal being voted upon.
     * @param account_    The voting account.
     * @param support_    Vote direction, 1 is for, 0 is against.
     * @param params_     The amount of votes being allocated in the funding stage.
     */
     function _castVote(uint256 proposalId_, address account_, uint8 support_, string memory, bytes memory params_) internal override(Governor) returns (uint256) {
        QuarterlyDistribution storage currentDistribution = distributions[getDistributionId()];
        Proposal[] storage currentTopTenProposals = topTenProposals[getDistributionId()];
        Proposal storage proposal = proposals[proposalId_];

        bytes memory stage;
        uint256 screeningPeriodEndBlock = currentDistribution.startBlock + (currentDistribution.endBlock - currentDistribution.startBlock) / 2;
        uint256 blockToCountVotesAt;
        uint256 votes;

        // screening stage
        if (block.number >= currentDistribution.startBlock && block.number <= screeningPeriodEndBlock) {
            // determine stage and available screening votes
            stage = bytes("Screening");
            blockToCountVotesAt = currentDistribution.startBlock;
            votes = _getVotes(account_, blockToCountVotesAt, stage);

            return _screeningVote(currentTopTenProposals, proposal, support_, votes);
        }

        // funding stage
        else if (block.number > screeningPeriodEndBlock && block.number <= currentDistribution.endBlock) {
            stage = bytes("Funding");
            blockToCountVotesAt = screeningPeriodEndBlock + 1; // assume funding stage starts immediatly after screening stage
            votes = _getVotes(account_, blockToCountVotesAt, stage);

            // amount of quadratic budget to allocated to the proposal
            int256 budgetAllocation = abi.decode(params_, (int256));

            return _fundingVote(proposal, account_, votes, budgetAllocation);
        }
    }

    // TODO: ensure this updated Proposal ties back to top ten proposals
    // TODO: rename fundingReceived to votesReceived
    function _fundingVote(Proposal storage proposal_, address account_, uint256 votes_, int256 budgetAllocation_) internal returns (uint256) {
        uint256 distributionId = getDistributionId();
        QuadraticVoter storage voter = quadraticVoters[distributionId][account_];

        // if first time voting update their voting weight
        if (voter.votingWeight == 0 && votes_ > 0) {
            voter.votingWeight = int256(votes_);
            voter.budgetRemaining = int256(votes_);
        }

        int256 allocationUsed;
        uint8  support = 1;

        // case where voter is voting against the proposal
        if (budgetAllocation_ < 0) {
            allocationUsed -= budgetAllocation_;
            support = 0;

            // update voter and proposal vote tracking
            voter.budgetRemaining -= allocationUsed;
            proposal_.fundingReceived -= allocationUsed;
        }
        // voter is voting in support of the proposal
        else {
            allocationUsed = budgetAllocation_;

            // update voter and proposal vote tracking
            voter.budgetRemaining -= allocationUsed;
            proposal_.fundingReceived += allocationUsed;
        }

        // update proposal vote tracking in top ten array
        topTenProposals[distributionId][uint256(_findInArray(proposal_.proposalId, topTenProposals[distributionId]))].fundingReceived = proposal_.fundingReceived;

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        emit VoteCast(account_, proposal_.proposalId, support, uint256(allocationUsed), "");
        return uint256(allocationUsed);
    }

    // TODO: check voting against a proposal
    /**
     * @notice Vote on a proposal in the screening stage of the Distribution Period.
     * @param currentTopTenProposals_ List of top ten vote receiving proposals that made it through the screening round.
     * @param proposal_               The current proposal being voted upon.
     * @param support_                Vote direction, 1 is for, 0 is against.
     * @param votes_                  The amount of votes being cast.
     */
    function _screeningVote(Proposal[] storage currentTopTenProposals_, Proposal storage proposal_, uint8 support_, uint256 votes_) internal onlyScreenOnce returns (uint256) {
        // update proposal votes counter
        proposal_.votesReceived += votes_;

        // check if proposal was already screened
        int indexInArray = _findInArray(proposal_.proposalId, currentTopTenProposals_);

        // check if the proposal should be added to the top ten list for the first time
        if (currentTopTenProposals_.length < 10 && indexInArray == -1) {
            currentTopTenProposals_.push(proposal_);
        }
        else {
            // proposal is already in the array
            if (indexInArray != -1) {
                currentTopTenProposals_[uint256(indexInArray)] = proposal_;

                // sort top ten proposals
                _quickSortProposalsByVotes(currentTopTenProposals_, 0, int(currentTopTenProposals_.length - 1));
            }
            // proposal isn't already in the array
            else if(currentTopTenProposals_[currentTopTenProposals_.length - 1].votesReceived < proposal_.votesReceived) {
                // replace least supported proposal with the new proposal
                currentTopTenProposals_.pop();
                currentTopTenProposals_.push(proposal_);

                // sort top ten proposals
                _quickSortProposalsByVotes(currentTopTenProposals_, 0, int(currentTopTenProposals_.length - 1));
            }
        }

        // ensure proposal list is within expected bounds
        require(topTenProposals[getDistributionId()].length <= 10 && topTenProposals[getDistributionId()].length > 0, "CV:LIST_MALFORMED");

        // record voters vote
        hasScreened[msg.sender] = true;

        // vote for the given proposal
        return super._castVote(proposal_.proposalId, msg.sender, support_, "", "");
    }

    /**
     * @notice Calculates the number of votes available to an account depending on the current stage of the Distribution Period.
     * @dev    Overrides OpenZeppelin _getVotes implementation to ensure appropriate voting weight is always returned.
     */
    function _getVotes(address account_, uint256 blockNumber_, bytes memory stage_) internal view override(Governor, GovernorVotes) returns (uint256) {
        // if block number within screening period 1 token 1 vote
        if (keccak256(stage_) == keccak256(bytes("Screening"))) {
            return super._getVotes(account_, blockNumber_, "");
        }
        // else if in funding period quadratic formula squares the number of votes
        else if (keccak256(stage_) == keccak256(bytes("Funding"))) {
            return (super._getVotes(account_, blockNumber_, "") ** 2);
        }
        // else one token one vote for all other voting
        else {
            return super._getVotes(account_, blockNumber_, "");
        }
    }

    // TODO: place these functions in their relevant sections
    /**************************/
    /*** Required Overrides ***/
    /**************************/

    /**
     * @notice Required ovverride.
     * @dev    Since no voting delay is implemented, this is hardcoded to 0.
     */
    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculates the remaining blocks left in the screening period.
     * @return The remaining number of blocks.
     */
    function votingPeriod() public view override(IGovernor) returns (uint256) {
        // TODO: return remaining time in whichever period we're in (super.propose()#266)
        QuarterlyDistribution memory currentDistribution = distributions[getDistributionId()];
        uint256 screeningPeriodEndBlock = currentDistribution.startBlock + (currentDistribution.endBlock - currentDistribution.startBlock) / 2;
        return screeningPeriodEndBlock - block.number;
    }

    // TODO: implement custom override - need to support both regular votes, and the extraordinaryFunding mechanism
    function quorum(uint256 blockNumber) public view override(IGovernor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    // Required override; we don't currently have a threshold to create a proposal so this returns the default value of 0
    function proposalThreshold() public view override(Governor) returns (uint256) {
        return super.proposalThreshold();
    }

    /*****************************/
    /*** Extraordinary Funding ***/
    /*****************************/

    /**
     * @notice Get the current extraordinaryFundingBaseQuorum required to pass an extraordinary funding proposal.
     */
    function getExtraordinaryFundingQuorum(uint256 blockNumber, uint256 tokensRequested) public view returns (uint256) {
    }

    /*************************/
    /*** Sorting Functions ***/
    /*************************/

    // TODO: move this into sort library
    // return the index of the proposalId in the array, else -1
    function _findInArray(uint256 proposalId, Proposal[] storage array) internal view returns (int256 index) {
        index = -1; // default value indicating proposalId not in the array

        for (int i = 0; i < int(array.length);) {
            if (array[uint256(i)].proposalId == proposalId) {
                index = i;
            }

            unchecked {
                ++i;
            }
        }
    }

    // TODO: move this into sort library
    /**
     * @notice Determine the 10 proposals which will make it through screening and move on to the funding round.
     * @dev    Implements the descending quicksort algorithm from this discussion: https://gist.github.com/subhodi/b3b86cc13ad2636420963e692a4d896f#file-quicksort-sol-L12
     */
    function _quickSortProposalsByVotes(Proposal[] storage arr, int left, int right) internal {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)].votesReceived;
        while (i <= j) {
            while (arr[uint(i)].votesReceived > pivot) i++;
            while (pivot > arr[uint(j)].votesReceived) j--;
            if (i <= j) {
                Proposal memory temp = arr[uint(i)];
                arr[uint(i)] = arr[uint(j)];
                arr[uint(j)] = temp;
                i++;
                j--;
            }
        }
        if (left < j)
            _quickSortProposalsByVotes(arr, left, j);
        if (i < right)
            _quickSortProposalsByVotes(arr, i, right);
    }

}
