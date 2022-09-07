// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { Governor } from "@oz/governance/Governor.sol";
import { GovernorCountingSimple } from "@oz/governance/extensions/GovernorCountingSimple.sol";
import { GovernorSettings } from "@oz/governance/extensions/GovernorSettings.sol";
import { GovernorVotes } from "@oz/governance/extensions/GovernorVotes.sol";
import { GovernorVotesQuorumFraction } from "@oz/governance/extensions/GovernorVotesQuorumFraction.sol";

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";

import { Maths } from "./libraries/Maths.sol";


// TODO: figure out how to allow partial votes -> need to override cast votes to allocate only some amount of voting power?
contract GrowthFund is Governor, GovernorCountingSimple, GovernorSettings, GovernorVotes, GovernorVotesQuorumFraction {

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

    // TODO: reset this at the start of each new quarter
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
    uint256 currentDistributionId = 0;

    /**
     * @notice Mapping of quarterly distributions from the growth fund.
     * @dev distributionId => QuarterlyDistribution
     */
    mapping (uint256 => QuarterlyDistribution) distributions;

    /**
     * @notice Mapping checking if a voter has voted on a proposal during the screening stage in a quarter.
     * @dev Reset to false at the start of each new quarter.
     */
    mapping (address => bool) hasScreened;

    /**
     * @dev Mapping of all proposals that have ever been submitted to the growth fund for screening.
     * @dev proposalId => Proposal
     */
    mapping (uint256 => Proposal) proposals;


    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @dev Contains proposals that made it through the screening process to the funding stage.
     */
    struct QuarterlyDistribution {
        uint256 distributionId;     // id of the current quarterly distribution
        uint256 tokensDistributed;  // number of ajna tokens distrubted that quarter
        uint256 votesCast;          // total number of votes cast that quarter
        uint256 startingBlock;      // block number of the quarterly distrubtions start
        uint256 endingBlock;        // block number of the quarterly distrubtions end
        Proposal[] proposals;       // list of successful proposals receiving distribution in the quarter
    }

    struct Proposal {
        string description; // TODO: may not be necessary if we are also storing proposalId
        uint256 tokensRequested; // TODO:
        uint256 proposalId; // OZ.Governor proposalId
        uint256 votesReceived; // accumulator of votes received by a proposal
        bool executed;
        bool canceled;
    }

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
    function _setNewDistributionId() private {
        ++currentDistributionId;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        // TODO: create a Proposal object here
        // Proposal storage newProposal = Proposal();

        // TODO: store new proposal information
        // proposals[proposalId] = newProposal;

        return super.propose();
    }

    // TODO: determine if anyone can kick or governance only
    function startNewDistributionPeriod() public {
        // check block number can be kicked

        // set new value for currentDistributionId
        _setNewDistributionId();

        // store the new QuarterlyDistribution struct
        QuarterlyDistribution newDistributionPeriod = QuarterlyDistribution(currentDistributionId, );
    }

    // _castVote() and update growthFund structs tracking progress
    function screenProposals(uint256 proposalId_, uint8 support_) public onlyScreenOnce {
        QuarterlyDistribution storage currentDistribution = distributions[currentDistributionId];

        // TODO: determine a better way to calculate the screening period
        uint256 screeningPeriodEndBlock = currentDistribution.startBlock + (currentDistribution.endBlock - currentDistribution.startBlock);
        require(block.number < screeningPeriodEndBlock, "screening period ended");

        // TODO: need to override createProposal with storage of the proposal, followed by call to super.propose() for remaining logic
        Proposal storage proposal = proposals[proposalId_];

        // record voters vote
        hasScreened[msg.sender] = true;

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

    // TODO: implement custom override
    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

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
