// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.16;

/**
 * @title Ajna Growth Coordination Fund
 */
interface IGrowthFund {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted at the end of a distribution period.
     *  @param  distributionId_  Id of the distribution period.
     *  @param  fundedSlateHash_ Hash of the proposals to be funded.
     */
    event FinalizeDistribution(uint256 indexed distributionId_, bytes32 indexed fundedSlateHash_);

    /**
     *  @notice Emitted at the beginning of a new quarterly distribution period.
     *  @param  distributionId_ Id of the new distribution period.
     *  @param  startBlock_     Block number of the quarterly distrubtions start.
     *  @param  endBlock_       Block number of the quarterly distrubtions end.
     */
    event QuarterlyDistributionStarted(uint256 indexed distributionId_, uint256 startBlock_, uint256 endBlock_);

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice Voter has already voted on a proposal in the screening stage in a quarter.
     */
    error AlreadyVoted();

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
     * @notice Non Ajna token contract address specified in target list.
     */
    error InvalidTarget();

    /**
     * @notice Non-zero amount specified in values array.
     * @dev This parameter is only used for sending ETH which the GrowthFund doesn't utilize.
     */
    error InvalidValues();

    /**
     * @notice Calldata for a method other than `transfer(address,uint256) was provided in a proposal.
     * @dev seth sig "transfer(address,uint256)" == 0xa9059cbb.
     */
    error InvalidSignature();

    /**
     * @notice User attempted to submit a proposal with too many target, values or calldatas.
     */
    error InvalidProposal();

    /**
     * @notice User attempted to execute a proposal that wasn't succesfully funded.
     */
    error ProposalNotFunded();

    /**
     * @notice Proposal requests more tokens than the previous maximum quarterly distribution.
     */
    error RequestedTooManyTokens();

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains proposals that made it through the screening process to the funding stage.
     * @dev Mapping and uint array used for tracking proposals in the distribution as typed arrays (like Proposal[]) can't be nested.
     */
    struct QuarterlyDistribution {
        uint256 id;                 // id of the current quarterly distribution
        uint256 votesCast;          // total number of votes cast that quarter
        uint256 startBlock;         // block number of the quarterly distrubtions start
        uint256 endBlock;           // block number of the quarterly distrubtions end
        bytes32 fundedSlateHash;    // hash of list of proposals to fund
    }

    struct Proposal {
        uint256 proposalId;       // OZ.Governor proposalId
        uint256 distributionId;   // Id of the distribution period in which the proposal was made
        uint256 votesReceived;    // accumulator of screening votes received by a proposal
        uint256 tokensRequested;  // number of Ajna tokens requested in the proposal
        int256 qvBudgetAllocated; // accumulator of QV budget allocated
        bool succeeded;           // whether or not the proposal was fully funded
        bool executed;            // whether or not the proposal has been executed
    }

    struct QuadraticVoter {
        uint256 votingWeight;   // amount of votes originally available to the voter
        int256 budgetRemaining; // remaining voting budget in the given period
    }

    // TODO: use this enum instead of block number calculations?
    enum DistributionPhase {
        Screening,
        Funding,
        Pending // TODO: rename - indicate the period between phases and a new distribution period
    }

}
