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

import { console } from "@std/console.sol";


// TODO: figure out how to allow partial votes -> need to override cast votes to allocate only some amount of voting power?
contract GrowthFund is Governor, GovernorCountingSimple, GovernorSettings, GovernorVotes, GovernorVotesQuorumFraction {

    using Checkpoints for Checkpoints.History;

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted at the beginning of a new quarterly distribution period.
     *  @param  distributionId_ Id of the new quarterly distribution.
     *  @param  startBlock_     Block number of the quarterly distrubtions start.
     *  @param  endBlock_       Block number of the quarterly distrubtions end.
     */
    event QuarterlyDistributionStarted(uint256 indexed distributionId_, uint256 startBlock_, uint256 endBlock_);

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice Voter has already voted on a proposal in the screening stage in a quarter.
     */
    error AlreadyVoted();

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 internal extraordinaryFundingBaseQuorum;

    address public   votingToken;
    IERC20  internal votingTokenIERC20;

    // TODO: update this from a percentage to just the numerator?
    /**
     * @notice Maximum amount of tokens that can be distributed by the treasury in a quarter.
     * @dev Stored as a Wad percentage.
     */
    uint256 public maximumTokenDistributionPercentage = Maths.wad(2) / Maths.wad(100);

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

    // TODO: deploy a clone contract with a fresh contract and it's own sorted list OR having a mapping distributionId => SortedList
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


    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains proposals that made it through the screening process to the funding stage.
     * @dev Mapping and uint array used for tracking proposals in the distribution as typed arrays (like Proposal[]) can't be nested.
     */
    struct QuarterlyDistribution {
        uint256 id;                          // id of the current quarterly distribution
        uint256 tokensDistributed;           // number of ajna tokens distrubted that quarter
        uint256 votesCast;                   // total number of votes cast that quarter
        uint256 startBlock;                  // block number of the quarterly distrubtions start
        uint256 endBlock;                    // block number of the quarterly distrubtions end
    }

    struct Proposal {
        uint256 proposalId;      // OZ.Governor proposalId
        uint256 distributionId;  // Id of the distribution period in which the proposal was made
        uint256 votesReceived;   // accumulator of votes received by a proposal
        int256 tokensRequested;  // number of Ajna tokens requested in the proposal
        int256 fundingReceived;  // accumulator of QV budget allocated
        bool succeeded;
    }

    struct QuadraticVoter {
        int256 budgetRemaining; // remaining voting budget
        bytes32 commitment;      // commitment hash enabling scret voting
    }

    // TODO: use this enum instead of block number calculations?
    enum DistributionPhase {
        Screening,
        Funding,
        Pending // TODO: rename - indicate the period between phases and a new distribution period
    }

    // TODO: replace with governorCountingSimple.hasVoted?
    /**
     * @dev Restrict a voter to only voting on one proposal during the screening stage.
     */
    modifier onlyScreenOnce() {
        if (hasScreened[msg.sender]) revert AlreadyVoted();
        _;
    }

    constructor(IVotes token_)
        Governor("AjnaEcosystemGrowthFund")
        GovernorSettings(1 /* 1 block */, 45818 /* 1 week */, 0) // default settings, can be updated via a governance proposal        
        GovernorVotes(token_) // token that will be used for voting
        GovernorVotesQuorumFraction(4) // percentage of total voting power required; updateable via governance proposal
    {
        extraordinaryFundingBaseQuorum = 50; // initialize base quorum percentrage required for extraordinary funding to 50%
        votingToken = address(token_);
    }

    /*****************************/
    /*** Standard Distribution ***/
    /*****************************/

    // create a new distribution Id
    // TODO: update this from a simple nonce incrementor
    // TODO: replace with OpenZeppelin Checkpoints.push
    // TODO: user counters.counter as well?
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

    function getDistributionPeriodInfo(uint256 distributionId_) external view returns (uint256, uint256, uint256, uint256, uint256) {
        QuarterlyDistribution memory distribution = distributions[distributionId_];
        return (
            distribution.id,
            distribution.tokensDistributed,
            distribution.votesCast,
            distribution.startBlock,
            distribution.endBlock
        );
    }

    // TODO: implement this
    function getProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, int256, int256, bool) {
        Proposal memory proposal = proposals[proposalId_];
        return (
            proposal.proposalId,
            proposal.distributionId,
            proposal.votesReceived,
            proposal.tokensRequested,
            proposal.fundingReceived,
            proposal.succeeded
        );
    }

    function getTopTenProposals(uint256 distributionId_) external view returns (Proposal[] memory) {
        return topTenProposals[distributionId_];
    }

    // TODO: call out to propose() down below with additional field for tokens requested
    function distributionProposal() public returns (uint256) {}

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        // TODO: block proposals from being created that would take more than the maximumQuarterlyDistribution
        // TODO: will need to update the value in the calldata
        // TODO: figure out how to decompose tokenId to calculate tokensRequested...
        // If we do decompose, how do we ensure that they did actually supply a `transferTo(address,uint256)`
        // do we need to create it ourselves?
        int256 tokensRequested = 0;
        int256 fundingReceived = 0;

        // TODO: add the distributionId of the period in which the proposal was submitted
        // create a struct to store proposal information
        Proposal memory newProposal = Proposal(proposalId, getDistributionId(), 0, tokensRequested, fundingReceived, false);

        // store new proposal information
        proposals[proposalId] = newProposal;

        return super.propose(targets, values, calldatas, description);
    }

    // TODO: determine if anyone can kick or governance only
    // TODO: deploy a clone contract with a fresh contract and it's own sorted list OR having a mapping distributionId => SortedList
    function startNewDistributionPeriod() public returns (uint256) {
        // TODO: check block number meets conditions and start can proceed

        // TODO: calculate starting and ending block properly
        uint256 startBlock = block.number; // TODO: should this be the current block?
        uint256 endBlock = startBlock + distributionPeriodLength; // TODO:  (controlled by governance) //TODO: update this... AND TEST IN testStartNewDistributionPeriod

        // set new value for currentDistributionId
        _setNewDistributionId();

        uint256 currentDistributionId = getDistributionId();

        // create QuarterlyDistribution struct
        QuarterlyDistribution storage newDistributionPeriod = distributions[currentDistributionId];
        newDistributionPeriod.id =  currentDistributionId;
        newDistributionPeriod.startBlock = startBlock;
        newDistributionPeriod.endBlock = endBlock;

        // reset quarterly votes counter
        quarterlyVotesCounter = 0;

        emit QuarterlyDistributionStarted(currentDistributionId, startBlock, endBlock);
        return newDistributionPeriod.id;
    }

    // TODO: restrict voting through this method to the distribution period? -> may need to place this overriding logic in _castVote instead and ovverride other voting methods to channel through here
    // _castVote() and update growthFund structs tracking progress
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

            // TODO: figure out how to handle return type here
            _fundingVote(proposal, account_, budgetAllocation);
        }

        // all other votes -> governance? 
        // TODO: determine how this should be restricted
    }

    // TODO: add return value from fundingVote?
    function _fundingVote(Proposal storage proposal_, address account_, int256 budgetAllocation_) internal {
        QuadraticVoter storage voter = quadraticVoters[getDistributionId()][account_];

        // TODO: implement this
        // calculate the vote cost of this vote based upon voters history in the funding round
        uint256 voteCost = 0;

        int256 remainingAllocationNeeded = proposal_.tokensRequested - proposal_.fundingReceived;
        int256 allocationUsed;

        // case where voter is voting against the proposal
        if (budgetAllocation_ < 0) {
            allocationUsed = budgetAllocation_;
        }
        // voter is voting in support of the proposal
        else {
            // TODO: REMOVE THIS if check since people may want to overallocate to ensure passing?
            // prevent allocation to a proposal that has already reached its requested token amount
            if (!proposal_.succeeded) {
                allocationUsed = Maths.minInt(remainingAllocationNeeded, budgetAllocation_);
            }
        }

        // update voters budget tracking
        voter.budgetRemaining += allocationUsed;

        // update proposal state to account for additional vote allocation
        proposal_.fundingReceived += allocationUsed;

        if (proposal_.fundingReceived == proposal_.tokensRequested) {
            proposal_.succeeded = true;
        }
        else if (proposal_.fundingReceived != proposal_.tokensRequested && proposal_.succeeded) {
            proposal_.succeeded = false;
        }
    }

    /**
     * @notice Vote on a proposal in the screening stage of the Distribution Period.
     * @param currentTopTenProposals_ List of top ten vote receiving proposals that made it through the screening round.
     */
    function _screeningVote(Proposal[] storage currentTopTenProposals_, Proposal storage proposal_, uint8 support_, uint256 votes) internal onlyScreenOnce returns (uint256) {
        // TODO: bring votes calculation into this internal function?

        // update proposal votes counter
        proposal_.votesReceived += votes;

        // increment quarterly votes counter
        quarterlyVotesCounter += votes;

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

    // TODO: implement this -> uses enums instead of block number to determine what phase for voting
    //         DistributionPhase phase = distributionPhase()
    function distributionPhase(uint256 distributionId_) public view returns (DistributionPhase) {
    }

    // TODO: potentially will want to override Governor.execute()
    /**
     * @notice Execute proposals and distribute funds to successful proposals
     */
    function executeDistribution() public {
        // TODO: how to given block height if it's ok to distribute?

        QuarterlyDistribution storage currentDistribution = distributions[getDistributionId()];

        currentDistribution.votesCast = quarterlyVotesCounter;
        currentDistribution.tokensDistributed = maximumQuarterlyDistribution();

        // TODO: finish implementing -> need to split into end functions for each sub period
    }

    /**
     * @notice Get the current percentage of the maximum possible distribution of Ajna tokens that will be released from the treasury this quarter.
     */
    function maximumQuarterlyDistribution() public view returns (uint256) {
        uint256 growthFundBalance = votingTokenIERC20.balanceOf(address(this));

        uint256 tokensToAllocate = (quarterlyVotesCounter *  (votingTokenIERC20.totalSupply() - growthFundBalance)) * maximumTokenDistributionPercentage;

        return tokensToAllocate;
    }

    // TODO: implement this? May need to pass the QuarterlyDistribution struct...
    function _screeningPeriodEndBlock() public view returns (uint256 endBlock) {}

    /**
     * @notice Set the new percentage of the maximum possible distribution of Ajna tokens that will be released from the treasury each quarter.
     * @dev Can only be called by Governance through the proposal process.
     */
    function setMaximumTokenDistributionPercentage(uint256 newDistributionPercentage_) public onlyGovernance {
        maximumTokenDistributionPercentage = newDistributionPercentage_;
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
    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    // TODO: implement custom override - need to support both regular votes, and the extraordinaryFunding mechanism
    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }


    // TODO: implement custom override
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
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

    /************************/
    /*** Voting Functions ***/
    /************************/

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
