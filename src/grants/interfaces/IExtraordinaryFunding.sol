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

    /**
     * @notice Proposal wasn't approved or has already been executed and isn't available for execution.
     */
    error ExecuteExtraordinaryProposalInvalid();

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains information about proposals made to the ExtraordinaryFunding mechanism.
     */
    struct ExtraordinaryFundingProposal {
        uint256  proposalId;      // Unique ID of the proposal. Hashed from proposeExtraordinary inputs.
        uint256  tokensRequested; // Number of AJNA tokens requested.
        uint256  startBlock;      // Block number of the start of the extraordinary funding proposal voting period.
        uint256  endBlock;        // Block number of the end of the extraordinary funding proposal voting period.
        uint256  votesReceived;   // Total votes received for this proposal.
        bool     succeeded;       // Whether the proposal succeeded or not.
        bool     executed;        // Whether the proposal has been executed or not.
    }

}
