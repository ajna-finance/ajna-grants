// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IVotes }    from "@oz/governance/utils/IVotes.sol";
import { SafeCast }  from "@oz/utils/math/SafeCast.sol";

import { Maths } from "./libraries/Maths.sol";

import { ExtraordinaryFunding } from "./base/ExtraordinaryFunding.sol";
import { StandardFunding }      from "./base/StandardFunding.sol";

import { IGrantFund } from "./interfaces/IGrantFund.sol";

contract GrantFund is IGrantFund, ExtraordinaryFunding, StandardFunding {

    IVotes public immutable token;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(IVotes token_, uint256 treasury_)
    {
        ajnaTokenAddress = address(token_);
        token = token_;
        treasury = treasury_;
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Given a proposalId, find if it is a standard or extraordinary proposal.
     * @param proposalId_ The id of the proposal to query the mechanism of.
     * @return FundingMechanism to which the proposal was submitted.
     */
    function findMechanismOfProposal(
        uint256 proposalId_
    ) public view returns (FundingMechanism) {
        if (standardFundingProposals[proposalId_].proposalId != 0)           return FundingMechanism.Standard;
        else if (extraordinaryFundingProposals[proposalId_].proposalId != 0) return FundingMechanism.Extraordinary;
        else revert ProposalNotFound();
    }

    /**
     * @notice Find the status of a given proposal.
     * @dev Check proposal status based upon Grant Fund specific logic.
     * @param proposalId_ The id of the proposal to query the status of.
     * @return ProposalState of the given proposal.
     */
    function state(
        uint256 proposalId_
    ) public view returns (ProposalState) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // standard proposal state checks
        if (mechanism == FundingMechanism.Standard) {
            return _standardProposalState(proposalId_);
        }
        // extraordinary funding proposal state
        else {
            return _getExtraordinaryProposalState(proposalId_);
        }
    }

}
