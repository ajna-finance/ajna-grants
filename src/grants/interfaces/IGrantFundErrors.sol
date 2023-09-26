// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.18;

/**
 * @title Grant Fund Errors.
 */
interface IGrantFundErrors {

    /**************/
    /*** Errors ***/
    /**************/

    /**
     * @notice User attempted to start a new distribution or claim delegation rewards before the distribution period ended.
     */
     error DistributionPeriodStillActive();

    /**
     * @notice Delegatee attempted to claim delegate rewards when they didn't vote in both stages.
     */
    error DelegateRewardInvalid();

    /**
     * @notice User attempted to execute a proposal before the distribution period ended.
     */
     error ExecuteProposalInvalid();

    /**
     * @notice User attempted to change the direction of a subsequent funding vote on the same proposal.
     */
    error FundingVoteWrongDirection();

    /**
     * @notice User attempted to vote with more voting power than was available to them.
     */
    error InsufficientVotingPower();

    /**
     * @notice Voter does not have enough voting power remaining to cast the vote.
     */
    error InsufficientRemainingVotingPower();

    /**
     * @notice User submitted a proposal with invalid parameters.
     * @dev    A proposal is invalid if it has a mismatch in the number of targets, values, or calldatas.
     * @dev    It is also invalid if it's calldata selector doesn't equal transfer().
     */
    error InvalidProposal();

    /**
     * @notice User provided a slate of proposalIds that is invalid.
     */
    error InvalidProposalSlate();

    /**
     * @notice User attempted to cast an invalid vote (outside of the distribution period, ).
     * @dev    This error is thrown when the user attempts to vote outside of the allowed period, vote with 0 votes, or vote with more than their voting power.
     */
    error InvalidVote();

    /**
     * @notice User attempted to submit a duplicate proposal.
     */
    error ProposalAlreadyExists();

    /**
     * @notice Proposal didn't meet requirements for execution.
     */
    error ProposalNotSuccessful();

    /**
     * @notice User attempted to Claim delegate reward again
     */
    error RewardAlreadyClaimed();

    /**
     * @notice User attempted to propose after screening period ended
     */
    error ScreeningPeriodEnded();

}