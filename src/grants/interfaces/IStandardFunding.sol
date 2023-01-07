// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.16;

/**
 * @title Ajna Grant Coordination Fund Standard Proposal flow.
 */
interface IStandardFunding {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice User attempted to execute a proposal before the distribution period ended.
     */
     error DistributionPeriodStillActive();

    /**
     * @notice User attempted to execute a proposal before the distribution period ended.
     */
     error ExecuteProposalInvalid();

    /**
     * @notice User attempted to finalize a distribution for execution when it has already been executed, or isn't ready.
     */
    error FinalizeDistributionInvalid();

    /**
     * @notice User attempted to vote with more qvBudget than was available to them.
     */
    error InsufficientBudget();

    /**
     * @notice Delegatee attempted to claim delegate reward before the challenge period ended.
     */
    error ChallengePeriodNotEnded();

    /**
     * @notice Delegatee attempted to claim delegate reward when not voted in screening.
     */
    error DelegateRewardInvalid();

    /**
     * @notice User attempted to propose after screening period ended
     */
    error ScreeningPeriodEnded();

    /**
     * @notice User attempted to Claim delegate reward again
     */
    error RewardAlreadyClaimed();

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when a new top ten slate is submitted and set as the leading optimized slate.
     *  @param  distributionId_  Id of the distribution period.
     *  @param  fundedSlateHash_ Hash of the proposals to be funded.
     */
    event FundedSlateUpdated(uint256 indexed distributionId_, bytes32 indexed fundedSlateHash_);

    /**
     *  @notice Emitted at the beginning of a new quarterly distribution period.
     *  @param  distributionId_ Id of the new distribution period.
     *  @param  startBlock_     Block number of the quarterly distrubtions start.
     *  @param  endBlock_       Block number of the quarterly distrubtions end.
     */
    event QuarterlyDistributionStarted(uint256 indexed distributionId_, uint256 startBlock_, uint256 endBlock_);

    /**
     *  @notice Emitted when delegatee claims his rewards.
     *  @param  delegateeAddress_ Address of delegatee.
     *  @param  distributionId_  Id of distribution period.
     *  @param  rewardClaimed_    Amount of Reward Claimed.
     */
    event DelegateRewardClaimed(address indexed delegateeAddress_, uint256 indexed distributionId_, uint256 rewardClaimed_);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains proposals that made it through the screening process to the funding stage.
     */
    struct QuarterlyDistribution {
        uint256 id;                  // id of the current quarterly distribution
        uint256 quadraticVotesCast;  // total number of votes cast in funding stage that quarter
        uint256 startBlock;          // block number of the quarterly distributions start
        uint256 endBlock;            // block number of the quarterly distributions end
        uint256 fundsAvailable;      // maximum fund (including delegate reward) that can be taken out that quarter   
        bytes32 fundedSlateHash;     // hash of list of proposals to fund
    }

    /**
     * @notice Contains information about proposals in a distribution period.
     */
    struct Proposal {
        uint256 proposalId;       // OZ.Governor proposalId
        uint256 distributionId;   // Id of the distribution period in which the proposal was made
        uint256 votesReceived;    // accumulator of screening votes received by a proposal
        uint256 tokensRequested;  // number of Ajna tokens requested in the proposal
        int256  qvBudgetAllocated; // accumulator of QV budget allocated
        bool    executed;         // whether the proposal has been executed
    }

    /**
     * @notice Contains information about voters during a distribution period's funding stage.
     */
    struct QuadraticVoter {
        uint256 votingWeight;   // amount of votes originally available to the voter
        int256 budgetRemaining; // remaining voting budget in the given period
    }

}
