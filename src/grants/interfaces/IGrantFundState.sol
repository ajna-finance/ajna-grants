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
     * @notice Enum listing available proposal types.
     */
    enum FundingMechanism {
        Standard,
        Extraordinary
    }

    /**
     * @dev Enum listing a proposal's lifecycle.
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
     */
    struct DistributionPeriod {
        uint24  id;                   // id of the current distribution period
        uint48  startBlock;           // block number of the distribution period's start
        uint48  endBlock;             // block number of the distribution period's end
        uint128 fundsAvailable;       // maximum fund (including delegate reward) that can be taken out that period
        uint256 fundingVotePowerCast; // total number of voting power allocated in funding stage that period
        bytes32 fundedSlateHash;      // hash of list of proposals to fund
    }

    /**
     * @notice Contains information about proposals in a distribution period.
     */
    struct Proposal {
        uint256 proposalId;           // OZ.Governor compliant proposalId. Hash of propose() inputs
        uint24  distributionId;       // Id of the distribution period in which the proposal was made
        bool    executed;             // whether the proposal has been executed
        uint128 votesReceived;        // accumulator of screening votes received by a proposal
        uint128 tokensRequested;      // number of Ajna tokens requested in the proposal
        int128  fundingVotesReceived; // accumulator of funding votes allocated to the proposal.
    }

    /**
     * @notice Contains information about voters during a vote made by a QuadraticVoter in the Funding stage of a distribution period.
     */
    struct FundingVoteParams {
        uint256 proposalId;
        int256 votesUsed;
    }

    /**
     * @notice Contains information about voters during a vote made during the Screening stage of a distribution period.
     * @dev    Used in screeningVoteMulti().
     */
    struct ScreeningVoteParams {
        uint256 proposalId; // the proposal being voted on
        uint256 votes;      // the number of votes to allocate to the proposal
    }

    /**
     * @notice Contains information about voters during a distribution period's funding stage.
     */
    struct QuadraticVoter {
        uint128 votingPower;           // amount of votes originally available to the voter, equal to the sum of the square of their initial votes
        uint128 remainingVotingPower;  // remaining voting power in the given period
        FundingVoteParams[] votesCast; // array of votes cast by the voter
    }

}

