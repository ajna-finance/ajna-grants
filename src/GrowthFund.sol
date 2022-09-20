// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Checkpoints } from "@oz/utils/Checkpoints.sol";

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { Governor } from "@oz/governance/Governor.sol";
import { GovernorCountingSimple } from "@oz/governance/extensions/GovernorCountingSimple.sol";
import { GovernorSettings } from "@oz/governance/extensions/GovernorSettings.sol";
import { GovernorVotes } from "@oz/governance/extensions/GovernorVotes.sol";
import { GovernorVotesQuorumFraction } from "@oz/governance/extensions/GovernorVotesQuorumFraction.sol";
import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";

import { Maths } from "./libraries/Maths.sol";

import { IGrowthFund } from "./interfaces/IGrowthFund.sol";

import { AjnaToken } from "./BaseToken.sol";

import { console } from "@std/console.sol";


contract GrowthFund is IGrowthFund, Governor, GovernorCountingSimple, GovernorSettings, GovernorVotes, GovernorVotesQuorumFraction {

    using Checkpoints for Checkpoints.History;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 internal extraordinaryFundingBaseQuorum;

    address public   votingTokenAddress;
    AjnaToken  internal ajnaToken;

    // TODO: update this from a percentage to just the numerator?
    /**
     * @notice Maximum amount of tokens that can be distributed by the treasury in a quarter.
     * @dev Stored as a Wad percentage.
     */
    uint256 public maximumTokenDistributionPercentage = Maths.wdiv(Maths.wad(2), Maths.wad(100));

    /**
     * @notice Length of the distribution period in blocks.
     */
    uint256 public distributionPeriodLength = 183272; // 4 weeks

    /**
     * @notice Accumulator tracking the number of votes cast in a quarter.
     * @dev Reset to 0 at the start of each new quarter.
     */
    uint256 quarterlyVotesCounter = 0;

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

    /**
     * @notice Ensure a proposal matches GrowthFund specifications.
     * @dev Targets_ should be the Ajna token contract, values_ should be 0, and calldatas_ should be transfer().
     * @param targets_   List of contract addresses the proposal interacts with.
     * @param values_    List of wei amounts to call the target address with.
     * @param calldatas_ List of calldatas to execute if the proposal is successful.
     */
    modifier checkProposal(address[] memory targets_, uint256[] memory values_, bytes[] calldata calldatas_) {
        for (uint i = 0; i < targets_.length;) {

            if (targets_[i] != votingTokenAddress) revert InvalidTarget();
            if (values_[i] != 0) revert InvalidValues();
            if (bytes4(calldatas_[i][:4]) != bytes4(0xa9059cbb)) revert InvalidSignature();

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
        GovernorSettings(1 /* 1 block */, 45818 /* 1 week */, 0) // default settings, can be updated via a governance proposal        
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

    // create a new distribution Id
    // TODO: update this from a simple nonce incrementor -> use counters.counter instead?
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

    function getDistributionPeriodInfo(uint256 distributionId_) external view returns (uint256, uint256, uint256, uint256, uint256, bool) {
        QuarterlyDistribution memory distribution = distributions[distributionId_];
        return (
            distribution.id,
            distribution.tokensDistributed,
            distribution.votesCast,
            distribution.startBlock,
            distribution.endBlock,
            distribution.executed
        );
    }

    function getProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, int256, int256, bool, bool) {
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

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] calldata calldatas,
        string memory description
    ) public override(Governor) checkProposal(targets, values, calldatas) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        // retrieve tokensRequested from proposal calldata
        (, uint256 tokensRequested) = abi.decode(calldatas[0][4:], (address, uint256));

        // TODO: check tokensRequested is less than the previous maximumQuarterlyDistribution
        // if (tokensRequested > maximumQuarterlyDistribution()) revert RequestedTooManyTokens();

        // store new proposal information
        Proposal storage newProposal = proposals[proposalId];
        newProposal.proposalId = proposalId;
        newProposal.distributionId = getDistributionId();
        newProposal.tokensRequested = int256(tokensRequested);

        return super.propose(targets, values, calldatas, description);
    }

    /**
     * @notice Start a new Distribution Period and reset appropiate state.
     * @dev    Can be kicked off by anyone assuming a distribution period isn't already active.
     */    
    function startNewDistributionPeriod() public returns (uint256) {
        QuarterlyDistribution memory lastDistribution = distributions[getDistributionId()];

        // TODO: add a delay to new period start
        // check that there isn't currently an active distribution period
        require(block.number > lastDistribution.endBlock, "Distribution Period Ongoing");

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

        // reset quarterly votes counter
        quarterlyVotesCounter = 0;

        emit QuarterlyDistributionStarted(newDistributionId, startBlock, endBlock);
        return newDistributionPeriod.id;
    }

    /*********************/
    /*** Vote Counting ***/
    /*********************/

    // TODO: override _countVote() as well
    // TODO: remove import of GovernorCountingSimple.sol
    // function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory) internal override(Governor) {
        // TODO: check if voter has already voted - or do it above based upon the funding flow?
    // }

    // TODO: finish implementing
    function _quorumReached(uint256 proposalId) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        return true;
    }

    function _voteSucceeded(uint256 proposalId_) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        console.log("in here");
        Proposal memory proposal = proposals[proposalId_];
        return proposal.succeeded == true;
    }

    /**************/
    /*** Voting ***/
    /**************/

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

        // all other votes -> governance? 
        // TODO: determine how this should be restricted
    }

    // TODO: add check to ensure that total funding received is still below the maximumQuarterlyDistribution invariant
    function _fundingVote(Proposal storage proposal_, address account_, uint256 votes_, int256 budgetAllocation_) internal returns (uint256) {
        QuadraticVoter storage voter = quadraticVoters[getDistributionId()][account_];

        // if first time voting update their voting weight
        if (voter.votingWeight == 0 && votes_ > 0) {
            voter.votingWeight = int256(votes_);
            voter.budgetRemaining = int256(votes_);
        }

        // TODO: implement this following update to the spec
        // calculate the vote cost of this vote based upon voters history in the funding round
        uint256 voteCost = 0;

        int256 remainingAllocationNeeded = proposal_.tokensRequested - proposal_.fundingReceived;
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
            // TODO: REMOVE THIS if check since people may want to overallocate to ensure passing?
            // prevent allocation to a proposal that has already reached its requested token amount
            if (!proposal_.succeeded) {
                allocationUsed = Maths.minInt(remainingAllocationNeeded, budgetAllocation_);
            }

            // update voter and proposal vote tracking
            voter.budgetRemaining -= allocationUsed;
            proposal_.fundingReceived += allocationUsed;
        }

        if (proposal_.fundingReceived >= proposal_.tokensRequested) {

            proposal_.succeeded = true;
        }
        else if (proposal_.fundingReceived != proposal_.tokensRequested && proposal_.succeeded) {
            proposal_.succeeded = false;
        }

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        emit VoteCast(account_, proposal_.proposalId, support, uint256(allocationUsed), "");
        return uint256(allocationUsed);
    }

    /**
     * @notice Vote on a proposal in the screening stage of the Distribution Period.
     * @param currentTopTenProposals_ List of top ten vote receiving proposals that made it through the screening round.
     * @param proposal_               The current proposal being voted upon.
     * @param support_                Vote direction, 1 is for, 0 is against.
     * @param votes_                  The amount of votes being cast.
     */
    function _screeningVote(Proposal[] storage currentTopTenProposals_, Proposal storage proposal_, uint8 support_, uint256 votes_) internal onlyScreenOnce returns (uint256) {
        // TODO: bring votes calculation into this internal function?

        // update proposal votes counter
        proposal_.votesReceived += votes_;

        // increment quarterly votes counter
        quarterlyVotesCounter += votes_;

        // check if additional votes are enough to push the proposal into the top 10
        if (currentTopTenProposals_.length == 0 || currentTopTenProposals_.length < 10) {
            currentTopTenProposals_.push(proposal_);
        }
        else {
            int indexInArray = _findInArray(proposal_.proposalId, currentTopTenProposals_);

            // proposal is already in the array
            if (indexInArray != -1) {
                currentTopTenProposals_[uint256(indexInArray)] = proposal_;

                // sort top ten proposals
                _quickSortProposalsByVotes(currentTopTenProposals_, 0, int(currentTopTenProposals_.length - 1));
            }
            // proposal isn't already in the array
            else if(currentTopTenProposals_[currentTopTenProposals_.length - 1].votesReceived < proposal_.votesReceived) {
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

    // TODO: check that the distribution period has actually ended prior to allowing people to call execute
    // TODO: create flows for distribution round execution, and governance parameter updates
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) public payable override(Governor) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        // check if proposal to execute is in the top 10, status succeeded, and it hasn't already been executed.
        if (_findInArray(proposalId, topTenProposals[getDistributionId()]) == -1 || !proposals[proposalId].succeeded || proposals[proposalId].executed) revert ProposalNotFunded();

        super.execute(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Update QuarterlyDistribution information, and burn any unused tokens.
     */
    function finalizeDistribution() public {
        QuarterlyDistribution storage currentDistribution = distributions[getDistributionId()];

        // check if the last distribution phase has ended and that proposals remain to be executed
        if (block.number <= currentDistribution.endBlock || currentDistribution.executed) revert FinalizeDistributionInvalid();

        currentDistribution.votesCast = quarterlyVotesCounter;
        currentDistribution.tokensDistributed = 0;

        Proposal[] memory currentTopTenProposals = topTenProposals[getDistributionId()];

        for (uint256 i = 0; i < currentTopTenProposals.length;) {
            if (proposals[currentTopTenProposals[i].proposalId].succeeded) {
                currentDistribution.tokensDistributed += uint256(currentTopTenProposals[i].tokensRequested);
            }

            unchecked {
                ++i;
            }
        }

        // transfer unused tokens to the burn address
        uint256 unusedTokens = maximumQuarterlyDistribution() - currentDistribution.tokensDistributed;
        ajnaToken.burn(unusedTokens);

        // mark the current distribution as execution, ensuring that succesful proposals can be executed and recieve their funding
        currentDistribution.executed = true;
        emit FinalizeDistribution(getDistributionId(), unusedTokens);
    }

    /**
     * @notice Get the current percentage of the maximum possible distribution of Ajna tokens that will be released from the treasury this quarter.
     */
    function maximumQuarterlyDistribution() public view returns (uint256) {
        uint256 growthFundBalance = ajnaToken.balanceOf(address(this));
        uint256 percentageOfTreasuryToAllocate = Maths.wmul(Maths.wdiv(quarterlyVotesCounter, (ajnaToken.totalSupply() - growthFundBalance)), maximumTokenDistributionPercentage);

        return Maths.wmul(growthFundBalance, percentageOfTreasuryToAllocate);
    }

    /******************************/
    /*** Growth Fund Parameters ***/
    /******************************/

    /**
     * @notice Set the new percentage of the maximum possible distribution of Ajna tokens that will be released from the treasury each quarter.
     * @dev Can only be called by Governance through the proposal process.
     */
    function setMaximumTokenDistributionPercentage(uint256 newDistributionPercentage_) public onlyGovernance {
        maximumTokenDistributionPercentage = newDistributionPercentage_;
    }

    function setDistributionPeriodLength(uint256 newDistributionPeriodLength_) public onlyGovernance {
        distributionPeriodLength = newDistributionPeriodLength_;
    }

    /**************************/
    /*** Required Overrides ***/
    /**************************/

    // TODO: tie this into quarterly distribution starting?
    // TODO: implement custom override
    function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    // TODO: tie this into screening period?
    // TODO: implement custom override
    function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    // TODO: implement custom override - need to support both regular votes, and the extraordinaryFunding mechanism
    function quorum(uint256 blockNumber) public view override(IGovernor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    // Required override; we don't currently have a threshold to create a proposal so this returns the default value of 0
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
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

    /**
     * @notice Update the extraordinaryFundingBaseQuorum upon a successful extraordinary funding vote.
     */
    function _setExtraordinaryFundingQuorum() internal {}

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

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
