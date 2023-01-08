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
        uint256 proposalId;        // OZ.Governor proposalId. Hash of proposeStandard inputs
        uint256 distributionId;    // Id of the distribution period in which the proposal was made
        uint256 votesReceived;     // accumulator of screening votes received by a proposal
        uint256 tokensRequested;   // number of Ajna tokens requested in the proposal
        int256  qvBudgetAllocated; // accumulator of QV budget allocated
        bool    executed;          // whether the proposal has been executed
    }

    /**
     * @notice Contains information about voters during a distribution period's funding stage.
     */
    struct QuadraticVoter {
        uint256 votingWeight;   // amount of votes originally available to the voter
        int256 budgetRemaining; // remaining voting budget in the given period
    }

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    /**
     * @notice Check if a slate of proposals meets requirements, and maximizes votes. If so, update QuarterlyDistribution.
     * @param  proposalIds_    Array of proposal Ids to check.
     * @param  distributionId_ Id of the current quarterly distribution.
     * @return isNewTopSlate   Boolean indicating whether the new proposal slate was set as the new top slate for distribution.
     */
    function checkSlate(uint256[] calldata proposalIds_, uint256 distributionId_) external returns (bool);

    /**
     * @notice distributes delegate reward based on delegatee Vote share.
     * @dev Can be called by anyone who has voted in both screening and funding period.
     * @param  distributionId_ Id of distribution from whinch delegatee wants to claim his reward.
     * @return rewardClaimed_  Amount of reward claimed by delegatee.
     */
    function claimDelegateReward(uint256 distributionId_) external returns(uint256 rewardClaimed_);

    /**
     * @notice Generate a unique hash of a list of proposal Ids for usage as a key for comparing proposal slates.
     * @param  proposalIds_ Array of proposal Ids to hash.
     * @return Bytes32      hash of the list of proposals.
     */
    function getSlateHash(uint256[] calldata proposalIds_) external pure returns (bytes32);

    /**
     * @notice Start a new Distribution Period and reset appropriate state.
     * @dev    Can be kicked off by anyone assuming a distribution period isn't already active.
     * @return newDistributionId_ The new distribution period Id.
     */
    function startNewDistributionPeriod() external returns (uint256 newDistributionId_);

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Execute a proposal that has been approved by the community.
     * @dev    Calls out to Governor.execute().
     * @dev    Check for proposal being succesfully funded or previously executed is handled by Governor.execute().
     * @return proposalId_ of the executed proposal.
     */
     function executeStandard(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) external returns (uint256 proposalId_);

    /**
     * @notice Submit a new proposal to the Grant Coordination Fund Standard Funding mechanism.
     * @dev    All proposals can be submitted by anyone. There can only be one value in each array. Interface inherits from OZ.propose().
     * @param  targets_ List of contracts the proposal calldata will interact with. Should be the Ajna token contract for all proposals.
     * @param  values_ List of values to be sent with the proposal calldata. Should be 0 for all proposals.
     * @param  calldatas_ List of calldata to be executed. Should be the transfer() method.
     * @return proposalId_ The id of the newly created proposal.
     */
    function proposeStandard(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) external returns (uint256 proposalId_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     * @notice Retrieve the QuarterlyDistribution distributionId at a given block.
     * @param  blockNumber The block number to check.
     * @return             The distributionId at the given block.
     */
    function getDistributionIdAtBlock(uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Retrieve the current QuarterlyDistribution distributionId.
     * @return The current distributionId.
     */
    function getDistributionId() external view returns (uint256);

    /**
     * @notice Mapping of distributionId to {QuarterlyDistribution} struct.
     * @param  distributionId_ The distributionId to retrieve the QuarterlyDistribution struct for.
     * @return distributionId     The retrieved struct's distributionId.
     * @return quadraticVotesCast The total number of votes cast in the distribution period's funding round.
     * @return startBlock         The block number of the distribution period's start.
     * @return endBlock           The block number of the distribution period's end.
     * @return fundsAvailable     The maximum amount of funds that can be taken out of the distribution period.
     * @return fundedSlateHash    The slate hash of the proposals that were funded.
     */
    function getDistributionPeriodInfo(uint256 distributionId_) external view returns (uint256, uint256, uint256, uint256, uint256, bytes32);

    /**
     * @notice Get the funded proposal slate for a given distributionId, and slate hash
     * @param  distributionId_ The distributionId of the distribution period to check.
     * @param  slateHash_      The slateHash to retrieve the funded proposals from.
     * @return                 The array of proposalIds that are in the funded slate hash.
     */
    function getFundedProposalSlate(uint256 distributionId_, bytes32 slateHash_) external view returns (uint256[] memory);

    /**
     * @notice Mapping of proposalIds to {Proposal} structs.
     * @param  proposalId_       The proposalId to retrieve the Proposal struct for.
     * @return proposalId        The retrieved struct's proposalId.
     * @return distributionId    The distributionId in which the proposal was submitted.
     * @return votesReceived     The amount of votes the proposal has received in it's distribution period's screening round.
     * @return tokensRequested   The amount of tokens requested by the proposal.
     * @return qvBudgetAllocated The amount of quadratic vote budget allocated to the proposal in it's distribution period's funding round.
     * @return executed          True if the proposal has been executed.
     */
    function getProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, uint256, int256, bool);

    /**
     * @notice Retrieve the top ten proposals that have received the most votes in a given distribution period's screening round.
     * @dev    It may return less than 10 proposals if less than 10 have been submitted. 
     * @dev    Values are subject to change if the queried distribution period's screening round is ongoing.
     * @param  distributionId_ The distributionId of the distribution period to query.
     * @return topTenProposals Array of the top ten proposal's proposalIds.
     */
    function getTopTenProposals(uint256 distributionId_) external view returns (uint256[] memory);

    /**
     * @notice Get the current state of a given voter in the funding stage.
     * @param  distributionId_ The distributionId of the distribution period to check.
     * @param  account_        The address of the voter to check.
     * @return votingWeight    The voter's voting weight in the funding round. Equal to the square of their tokens in the voting snapshot.
     * @return budgetRemaining The voter's remaining quadratic vote budget in the given distribution period's funding round.
     */
    function getVoterInfo(uint256 distributionId_, address account_) external view returns (uint256, int256);

    /**
     * @notice Get the current maximum possible distribution of Ajna tokens that will be released from the treasury this quarter.
     * @return The number of Ajna tokens.
     */
    function maximumQuarterlyDistribution() external view returns (uint256);

}
