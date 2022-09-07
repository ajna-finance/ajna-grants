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
     * @notice Accumulator tracking the number of votes cast in a quarter.
     * @dev Reset to 0 at the start of each new quarter.
     */
    uint256 quarterlyVotesCounter = 0;

    /**
     * @dev List of quarterly distributions paid out of the growth fund.
     */
    QuarterlyDistribution[] public quarterlyDistributions;

    /**
     * @dev List of all proposals that have ever been submitted to the growth fund.
     */
    Proposal[] public proposals;

    /***************/
    /*** Structs ***/
    /***************/

    struct QuarterlyDistribution {
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

    /**
     * @notice Get the current percentage of the maximum possible distribution of Ajna tokens that will be released from the treasury this quarter.
     */
    function maximumQuarterlyDistribution() public view returns (uint256) {
        uint256 growthFundBalance = votingTokenIERC20.balanceOf(address(this));

        uint256 tokensToAllocate = (quarterlyVotesCounter *  (votingTokenIERC20.totalSupply() - growthFundBalance)) * maximumTokenDistributionPercentage;

        return tokensToAllocate;
    }

    /**
     * @notice Set the new percentage of the maximum possible distribution of Ajna tokens that will be released from the treasury each quarter.
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
