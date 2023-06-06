// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.18;

/**
 * @title Grant Fund State.
 */
interface IGrantFundState {

    /*************/
    /*** Enums ***/
    /*************/

    /**
     * @notice Enum listing a proposal's lifecycle.
     * @dev Compatibile with interface used by Compound Governor Bravo and OpenZeppelin Governor.
     * @dev Returned in `state()` function.
     * @param Pending   N/A for Ajna. Maintained for compatibility purposes.
     * @param Active    Block number is still within a proposal's distribution period, and the proposal hasn't yet been finalized.
     * @param Canceled  N/A for Ajna. Maintained for compatibility purposes.
     * @param Defeated  Proposal wasn't finalized.
     * @param Succeeded Proposal was succesfully voted on and finalized, and can be executed at will.
     * @param Queued    N/A for Ajna. Maintained for compatibility purposes.
     * @param Expired   N/A for Ajna. Maintained for compatibility purposes.
     * @param Executed  Proposal was executed.
     */
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains proposals that made it through the screening process to the funding stage.
     * @param id                   Id of the current distribution period.
     * @param startBlock           Block number of the distribution period's start.
     * @param endBlock             Block number of the distribution period's end.
     * @param fundsAvailable       Maximum fund (including delegate reward) that can be taken out that period.
     * @param fundingVotePowerCast Total number of voting power allocated in funding stage that period.
     * @param fundedSlateHash      Hash of leading slate of proposals to fund.
     */
    struct DistributionPeriod {
        uint24  id;
        uint48  startBlock;
        uint48  endBlock;
        uint128 fundsAvailable;
        uint256 fundingVotePowerCast;
        bytes32 fundedSlateHash;
    }

    /**
     * @notice Contains information about proposals in a distribution period.
     * @param proposalId           OZ.Governor compliant proposalId. Hash of propose() inputs.
     * @param distributionId       Id of the distribution period in which the proposal was made.
     * @param executed             Whether the proposal has been executed.
     * @param votesReceived        Accumulator of screening votes received by a proposal.
     * @param tokensRequested      Number of Ajna tokens requested by the proposal.
     * @param fundingVotesReceived Accumulator of funding votes allocated to the proposal.
     */
    struct Proposal {
        uint256 proposalId;
        uint24  distributionId;
        bool    executed;
        uint128 votesReceived;
        uint128 tokensRequested;
        int128  fundingVotesReceived;
    }

    /**
     * @notice Contains information about voters during a vote made by a QuadraticVoter in the Funding stage of a distribution period.
     * @dev    Used in fundingVote().
     * @param proposalId Id of the proposal being voted on.
     * @param votesUsed  Number of votes allocated to the proposal.
     */
    struct FundingVoteParams {
        uint256 proposalId;
        int256 votesUsed;
    }

    /**
     * @notice Contains information about voters during a vote made during the Screening stage of a distribution period.
     * @dev    Used in screeningVote().
     * @param proposalId Id of the proposal being voted on.
     * @param votes      Number of votes allocated to the proposal.
     */
    struct ScreeningVoteParams {
        uint256 proposalId;
        uint256 votes;
    }

    /**
     * @notice Contains information about voters during a distribution period's funding stage.
     * @dev    Used in `fundingVote()`, and `claimDelegateReward()`.
     * @param fundingVotingPower          Amount of votes originally available to the voter, equal to the sum of the square of their initial votes.
     * @param fundingRemainingVotingPower Remaining voting power in the given period.
     * @param votesCast                   Array of votes cast by the voter.
     * @param screeningVotesCast          Number of screening votes cast by the voter.
     * @param hasClaimedReward            Whether the voter has claimed their reward for the given period.
     */
    struct VoterInfo {
        uint128 fundingVotingPower;
        uint128 fundingRemainingVotingPower;
        FundingVoteParams[] votesCast;
        uint248 screeningVotesCast;
        bool hasClaimedReward;
    }

}

