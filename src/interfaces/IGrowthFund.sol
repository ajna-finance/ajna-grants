// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

/**
 * @title Ajna ERC20 Pool
 */
interface IGrowthFund {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted at the beginning of a new quarterly distribution period.
     *  @param  distributionId_ Id of the new quarterly distribution.
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

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains proposals that made it through the screening process to the funding stage.
     * @dev Mapping and uint array used for tracking proposals in the distribution as typed arrays (like Proposal[]) can't be nested.
     */
    struct QuarterlyDistribution {
        uint256 id;                          // id of the current quarterly distribution
        uint256 tokensDistributed;           // number of ajna tokens distrubted that quarter
        uint256 votesCast;                   // total number of votes cast that quarter
        uint256 startBlock;                  // block number of the quarterly distrubtions start
        uint256 endBlock;                    // block number of the quarterly distrubtions end
    }

    struct Proposal {
        uint256 proposalId;      // OZ.Governor proposalId
        uint256 distributionId;  // Id of the distribution period in which the proposal was made
        uint256 votesReceived;   // accumulator of votes received by a proposal
        int256 tokensRequested;  // number of Ajna tokens requested in the proposal
        int256 fundingReceived;  // accumulator of QV budget allocated
        bool succeeded;
    }

    struct QuadraticVoter {
        int256 budgetRemaining; // remaining voting budget
        bytes32 commitment;      // commitment hash enabling scret voting
    }

    // TODO: use this enum instead of block number calculations?
    enum DistributionPhase {
        Screening,
        Funding,
        Pending // TODO: rename - indicate the period between phases and a new distribution period
    }

}
