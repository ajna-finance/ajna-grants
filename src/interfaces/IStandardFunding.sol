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
     * @notice User attempted to submit a proposal with too many target, values or calldatas.
     */
    error InvalidProposal();

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

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains proposals that made it through the screening process to the funding stage.
     */
    struct QuarterlyDistribution {
        uint256 id;                 // id of the current quarterly distribution
        uint256 votesCast;          // total number of votes cast that quarter
        uint256 startBlock;         // block number of the quarterly distributions start
        uint256 endBlock;           // block number of the quarterly distributions end
        bytes32 fundedSlateHash;    // hash of list of proposals to fund
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
    }

    /**
     * @notice Contains information about voters during a distribution period's funding stage.
     */
    struct QuadraticVoter {
        uint256 votingWeight;   // amount of votes originally available to the voter
        int256 budgetRemaining; // remaining voting budget in the given period
    }

}
