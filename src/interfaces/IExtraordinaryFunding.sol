// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.16;

/**
 * @title Ajna Grant Coordination Fund Extraordinary Proposal flow.
 */
interface IExtraordinaryFunding {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice User attempted to submit a proposal with invalid parameters.
     */
    error ExtraordinaryFundingProposalInvalid();

    /**
     * @notice The current block isn't in the specified range of active blocks.
     */
    error ExtraordinaryFundingProposalInactive();

    error ExecuteExtraordinaryProposalInvalid();

    /***************/
    /*** Structs ***/
    /***************/

    struct ExtraordinaryFundingProposal {
        uint256  proposalId;
        uint256  tokensRequested; // Number of AJNA tokens requested.
        uint256  startBlock;      // Block number of the start of the extraordinary funding proposal voting period.
        uint256  endBlock;
        uint256  votesReceived;   // Total votes received for this proposal.
        bool     succeeded;
        bool     executed;
    }

}
