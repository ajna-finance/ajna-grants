// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Governor } from "@oz/governance/Governor.sol";
import { GovernorCountingSimple } from "@oz/governance/extensions/GovernorCountingSimple.sol";
import { GovernorSettings } from "@oz/governance/extensions/GovernorSettings.sol";
import { GovernorVotes } from "@oz/governance/extensions/GovernorVotes.sol";
import { GovernorVotesQuorumFraction } from "@oz/governance/extensions/GovernorVotesQuorumFraction.sol";

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";


// TODO: figure out how to allow partial votes -> need to override cast votes to allocate only some amount of voting power
contract GrowthFund is Governor, GovernorCountingSimple, GovernorSettings, GovernorVotes, GovernorVotesQuorumFraction {

    uint256 internal extraordinaryFundingBaseQuorum;

    constructor(IVotes token_)
        Governor("AjnaEcosystemGrowthFund")
        GovernorSettings(1 /* 1 block */, 45818 /* 1 week */, 0) // default settings, can be updated via a governance proposal        
        GovernorVotes(token_) // token that will be used for voting
        GovernorVotesQuorumFraction(4) // percentage of total voting power required; updateable via governance proposal
    {
        extraordinaryFundingBaseQuorum = 50; // initialize base quorum percentrage required for extraordinary funding to 50%
    }

    // TODO: finish implementing
    /**
     * @notice Generate calldata that can be executed as part of a successful proposal.
     * @dev    Intended to allow the Ajna token to be passed as target contract, values to be the amount of ajna tokens, and calldata to contain the transfer instructions.
     */
    function generateFundingCalldata(address recipient) public view returns (bytes32) {

    }

    /*****************************/
    /*** Standard Distribution ***/
    /*****************************/

    /**
     * @notice Get the current maximum distribution of Ajna tokens that will be released from the treasury this quarter.
     */
    function maximumQuarterlyDistribution() public view returns (uint256) {}

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
        // return extraordinaryFundingBaseQuorum + 
        // token.getPastTotalSupply(blockNumber)
    }

    /**
     * @notice Update the extraordinaryFundingBaseQuorum upon a successful extraordinary funding vote.
     */
    function _setExtraordinaryFundingQuorum() internal {}



}
