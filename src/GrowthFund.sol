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
        string description;      // TODO: may not be necessary if we are also storing proposalId
        // uint256 tokensRequested; // TODO: does this need to be tracked?
        uint256 proposalId;      // OZ.Governor proposalId
        uint256 distributionId;  // Id of the distribution period in which the proposal was made
        uint256 votesReceived;   // accumulator of votes received by a proposal
        bool isVoting;
        bool succeeded;
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
    function getProposalInfo() external view {}

    function getTopTenProposals(uint256 distributionId_) external view returns (Proposal[] memory) {
        return topTenProposals[distributionId_];
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        // TODO: will need to update the value in the calldata
        // TODO: figure out how to decompose tokenId to calculate tokensRequested...
        // If we do decompose, how do we ensure that they did actually supply a `transferTo(address,uint256)`
        // do we need to create it ourselves?
        // uint256 tokensRequested = 0;

        // TODO: add the distributionId of the period in which the proposal was submitted
        // create a struct to store proposal information
        Proposal memory newProposal = Proposal(description, proposalId, getDistributionId(), 0, true, false);

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

    // TODO: restrict voting through this method to the distribution period? -> may need to place this overriding logic in _castVote instead
    // _castVote() and update growthFund structs tracking progress
    // TODO: update this to castVote() override with if block that checks voting round and acts accordingly to maintain compatibility with tall.xyz
    // TODO: then: if screenProposals call _screenProposals, if fundProposals call _fundProposals() 
    function castVote(uint256 proposalId_, uint8 support_) public override(Governor) onlyScreenOnce returns(uint256) {
        QuarterlyDistribution storage currentDistribution = distributions[getDistributionId()];

        // TODO: determine a better way to calculate the screening period block range
        uint256 screeningPeriodEndBlock = currentDistribution.startBlock + (currentDistribution.endBlock - currentDistribution.startBlock) / 2;
        require(block.number < screeningPeriodEndBlock, "screening period ended");

        // TODO: determine when to calculate voting weight
        uint256 blockToCountVotesAt = currentDistribution.startBlock;

        // update proposal vote count
        uint256 votes = _getVotes(msg.sender, blockToCountVotesAt, "");
        Proposal storage proposal = proposals[proposalId_];
        proposal.votesReceived += votes;

        // increment quarterly votes counter
        quarterlyVotesCounter += votes;

        Proposal[] storage currentTopTenProposals = topTenProposals[getDistributionId()];

        // check if additional votes are enough to push the proposal into the top 10
        if (currentTopTenProposals.length == 0 || currentTopTenProposals.length < 10) {
            currentTopTenProposals.push(proposal);
        }
        else {
            int indexInArray = _findInArray(proposal.proposalId, currentTopTenProposals);

            // proposal is already in the array
            if (indexInArray != -1) {
                currentTopTenProposals[uint256(indexInArray)] = proposal;

                // sort top ten proposals
                _quickSortProposalsByVotes(currentTopTenProposals, 0, int(currentTopTenProposals.length - 1));
            }
            // proposal isn't already in the array
            else if(currentTopTenProposals[currentTopTenProposals.length - 1].votesReceived < proposal.votesReceived) {
                currentTopTenProposals.pop();
                currentTopTenProposals.push(proposal);

                // sort top ten proposals
                _quickSortProposalsByVotes(currentTopTenProposals, 0, int(currentTopTenProposals.length - 1));
            }
        }

        // TODO: remove after end of dev process
        require(topTenProposals[getDistributionId()].length <= 10 && topTenProposals[getDistributionId()].length > 0, "CV:LIST_MALFORMED");

        // record voters vote
        hasScreened[msg.sender] = true;

        // vote for the given proposal
        return super.castVote(proposalId_, support_);
    }

    // TODO: move this into sort library
    // return the index of the proposalId in the array, else -1
    function _findInArray(uint256 proposalId, Proposal[] storage array) internal returns (int256 index) {
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

    /**
     * @notice Determine the 10 proposals which will make it through screening and move on to the funding round.
     */
    function determineScreeningOutcome() public {
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



}
