// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.18;

import { IGrantFundState } from "./IGrantFundState.sol";

/**
 * @title Grant Fund User Actions.
 */
interface IGrantFundActions is IGrantFundState {

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    /**
     * @notice Transfers Ajna tokens to the GrantFund contract.
     * @param fundingAmount_ The amount of Ajna tokens to transfer.
     */
    function fundTreasury(uint256 fundingAmount_) external;

    /**
     * @notice Start a new Distribution Period and reset appropriate state.
     * @dev    Can be kicked off by anyone assuming a distribution period isn't already active.
     * @return newDistributionId_ The new distribution period Id.
     */
    function startNewDistributionPeriod() external returns (uint24 newDistributionId_);

    /************************************/
    /*** Delegation Rewards Functions ***/
    /************************************/

    /**
     * @notice distributes delegate reward based on delegatee Vote share.
     * @dev Can be called by anyone who has voted in both screening and funding stages.
     * @param  distributionId_ Id of distribution from which delegatee wants to claim their reward.
     * @return rewardClaimed_  Amount of reward claimed by delegatee.
     */
    function claimDelegateReward(
        uint24 distributionId_
    ) external returns(uint256 rewardClaimed_);

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Execute a proposal that has been approved by the community.
     * @dev    Calls out to _execute().
     * @dev    Only proposals in the finalized top slate slate at the end of the challenge period can be executed.
     * @param  targets_         List of contracts the proposal calldata will interact with. Should be the Ajna token contract for all proposals.
     * @param  values_          List of values to be sent with the proposal calldata. Should be 0 for all proposals.
     * @param  calldatas_       List of calldata to be executed. Should be the transfer() method.
     * @param  descriptionHash_ Hash of proposal's description string.
     * @return proposalId_      The id of the executed proposal.
     */
     function execute(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external returns (uint256 proposalId_);

    /**
     * @notice Create a proposalId from a hash of proposal's targets, values, and calldatas arrays, and a description hash.
     * @dev    Consistent with proposalId generation methods used in OpenZeppelin Governor.
     * @param targets_         The addresses of the contracts to call.
     * @param values_          The amounts of ETH to send to each target.
     * @param calldatas_       The calldata to send to each target.
     * @param descriptionHash_ The hash of the proposal's description string. Generated by `keccak256(bytes(description_))` or by calling `getDescriptionHash`.
     * @return proposalId_     The hashed proposalId created from the provided params.
     */
    function hashProposal(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external pure returns (uint256 proposalId_);

    /**
     * @notice Submit a new proposal to the Grant Coordination Fund Standard Funding mechanism.
     * @dev    Proposals can be submitted by anyone. Interface is compliant with OZ.propose().
     * @param  targets_     List of contracts the proposal calldata will interact with. Should be the Ajna token contract for all proposals.
     * @param  values_      List of values to be sent with the proposal calldata. Should be 0 for all proposals.
     * @param  calldatas_   List of calldata to be executed. Should be the transfer() method.
     * @param  description_ Proposal's description string.
     * @return proposalId_  The id of the newly created proposal.
     */
    function propose(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) external returns (uint256 proposalId_);

    /**
     * @notice Find the status of a given proposal.
     * @dev Proposal status depends on the stage of the distribution period in which it was submitted, and vote counts on the proposal.
     * @param proposalId_ The id of the proposal to query the status of.
     * @return ProposalState of the given proposal.
     */
    function state(
        uint256 proposalId_
    ) external view returns (ProposalState);

    /**
     * @notice Check if a slate of proposals meets requirements, and maximizes votes. If so, set the provided proposal slate as the new top slate of proposals.
     * @param  proposalIds_    Array of proposal Ids to check.
     * @param  distributionId_ Id of the current distribution period.
     * @return newTopSlate_    Boolean indicating whether the new proposal slate was set as the new top slate for distribution.
     */
    function updateSlate(
        uint256[] calldata proposalIds_,
        uint24 distributionId_
    ) external returns (bool newTopSlate_);

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @notice Cast an array of funding votes in one transaction.
     * @dev    Calls StandardFunding._fundingVote().
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param voteParams_ The array of votes on proposals to cast.
     * @return votesCast_ The total number of votes cast across all of the proposals.
     */
    function fundingVote(
        FundingVoteParams[] memory voteParams_
    ) external returns (uint256 votesCast_);

    /**
     * @notice Cast an array of screening votes in one transaction.
     * @dev    Calls StandardFunding._screeningVote().
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param  voteParams_ The array of votes on proposals to cast.
     * @return votesCast_  The total number of votes cast across all of the proposals.
     */
    function screeningVote(
        ScreeningVoteParams[] memory voteParams_
    ) external returns (uint256 votesCast_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     * @notice Get the block number at which this distribution period's challenge stage starts.
     * @param  endBlock_ The end block of a distribution period to get the challenge stage start block for.
     * @return The block number at which this distribution period's challenge stage starts.
    */
    function getChallengeStageStartBlock(uint256 endBlock_) external pure returns (uint256);

    /**
     * @notice Retrieve the delegate reward accrued to a voter in a given distribution period.
     * @param  distributionId_ The distributionId to calculate rewards for.
     * @param  voter_          The address of the voter to calculate rewards for.
     * @return rewards_        The rewards earned by the voter for voting in that distribution period.
     */
    function getDelegateReward(
        uint24 distributionId_,
        address voter_
    ) external view returns (uint256 rewards_);

    /**
     * @notice Calculate the description hash of a proposal.
     * @dev    The description hash is used as a unique identifier for a proposal. It is created by hashing the description string.
     * @param  description_ The proposal's description string.
     * @return              The hash of the proposal's description string.
     */
    function getDescriptionHash(string memory description_) external pure returns (bytes32);

    /**
     * @notice Retrieve the current DistributionPeriod distributionId.
     * @return The current distributionId.
     */
    function getDistributionId() external view returns (uint24);

    /**
     * @notice Mapping of distributionId to {DistributionPeriod} struct.
     * @param  distributionId_      The distributionId to retrieve the DistributionPeriod struct for.
     * @return distributionId       The retrieved struct's distributionId.
     * @return startBlock           The block number of the distribution period's start.
     * @return endBlock             The block number of the distribution period's end.
     * @return fundsAvailable       The maximum amount of funds that can be taken out of the distribution period.
     * @return fundingVotePowerCast The total number of votes cast in the distribution period's funding round.
     * @return fundedSlateHash      The slate hash of the proposals that were funded.
     */
    function getDistributionPeriodInfo(
        uint24 distributionId_
    ) external view returns (uint24, uint48, uint48, uint128, uint256, bytes32);

    /**
     * @notice Get the funded proposal slate for a given distributionId, and slate hash
     * @param  slateHash_      The slateHash to retrieve the funded proposals from.
     * @return                 The array of proposalIds that are in the funded slate hash.
     */
    function getFundedProposalSlate(
        bytes32 slateHash_
    ) external view returns (uint256[] memory);

    /**
     * @notice Get the block number at which this distribution period's funding stage ends.
     * @param  startBlock_ The start block of a distribution period to get the funding stage end block for.
     * @return The block number at which this distribution period's funding stage ends.
    */
    function getFundingStageEndBlock(uint256 startBlock_) external pure returns (uint256);

    /**
     * @notice Get the list of funding votes cast by an account in a given distribution period.
     * @param  distributionId_   The distributionId of the distribution period to check.
     * @param  account_          The address of the voter to check.
     * @return FundingVoteParams The list of FundingVoteParams structs that have been successfully cast the voter.
     */
    function getFundingVotesCast(uint24 distributionId_, address account_) external view returns (FundingVoteParams[] memory);

    /**
     * @notice Get the reward claim status of an account in a given distribution period.
     * @param  distributionId_ The distributionId of the distribution period to check.
     * @param  account_        The address of the voter to check.
     * @return                 The reward claim status of the account in the distribution period.
     */
    function getHasClaimedRewards(uint256 distributionId_, address account_) external view returns (bool);

    /**
     * @notice Mapping of proposalIds to {Proposal} structs.
     * @param  proposalId_          The proposalId to retrieve the Proposal struct for.
     * @return proposalId           The retrieved struct's proposalId.
     * @return distributionId       The distributionId in which the proposal was submitted.
     * @return votesReceived        The amount of votes the proposal has received in its distribution period's screening round.
     * @return tokensRequested      The amount of tokens requested by the proposal.
     * @return fundingVotesReceived The amount of funding votes cast on the proposal in its distribution period's funding round.
     * @return executed             True if the proposal has been executed.
     */
    function getProposalInfo(
        uint256 proposalId_
    ) external view returns (uint256, uint24, uint128, uint128, int128, bool);

    /**
     * @notice Get the block number at which this distribution period's screening stage ends.
     * @param  startBlock_ The start block of a distribution period to get the screening stage end block for.
     * @return The block number at which this distribution period's screening stage ends.
    */
    function getScreeningStageEndBlock(uint256 startBlock_) external pure returns (uint256);

    /**
     * @notice Get the number of screening votes cast by an account in a given distribution period.
     * @param  distributionId_ The distributionId of the distribution period to check.
     * @param  account_        The address of the voter to check.
     * @return                 The number of screening votes successfully cast the voter.
     */
    function getScreeningVotesCast(uint256 distributionId_, address account_) external view returns (uint256);

    /**
     * @notice Generate a unique hash of a list of proposal Ids for usage as a key for comparing proposal slates.
     * @param  proposalIds_ Array of proposal Ids to hash.
     * @return Bytes32      Hash of the list of proposals.
     */
    function getSlateHash(
        uint256[] calldata proposalIds_
    ) external pure returns (bytes32);

    /**
     * @notice Retrieve a bytes32 hash of the current distribution period stage.
     * @dev    Used to check if the distribution period is in the screening, funding, or challenge stages.
     * @return stage_ The hash of the current distribution period stage.
     */
    function getStage() external view returns (bytes32 stage_);

    /**
     * @notice Retrieve the top ten proposals that have received the most votes in a given distribution period's screening round.
     * @dev    It may return less than 10 proposals if less than 10 have been submitted. 
     * @dev    Values are subject to change if the queried distribution period's screening round is ongoing.
     * @param  distributionId_ The distributionId of the distribution period to query.
     * @return topTenProposals Array of the top ten proposal's proposalIds.
     */
    function getTopTenProposals(
        uint24 distributionId_
    ) external view returns (uint256[] memory);

    /**
     * @notice Get the current state of a given voter in the funding stage.
     * @param  distributionId_ The distributionId of the distribution period to check.
     * @param  account_        The address of the voter to check.
     * @return votingPower          The voter's voting power in the funding round. Equal to the square of their tokens in the voting snapshot.
     * @return remainingVotingPower The voter's remaining quadratic voting power in the given distribution period's funding round.
     * @return votesCast            The voter's number of proposals voted on in the funding stage.
     */
    function getVoterInfo(
        uint24 distributionId_,
        address account_
    ) external view returns (uint128, uint128, uint256);

    /**
     * @notice Get the remaining quadratic voting power available to the voter in the funding stage of a distribution period.
     * @dev    This value will be the square of the voter's token balance at the snapshot blocks.
     * @param  distributionId_ The distributionId of the distribution period to check.
     * @param  account_        The address of the voter to check.
     * @return votes_          The voter's remaining quadratic voting power.
     */
    function getVotesFunding(uint24 distributionId_, address account_) external view returns (uint256 votes_);

    /**
     * @notice Get the voter's voting power in the screening stage of a distribution period.
     * @param  distributionId_ The distributionId of the distribution period to check.
     * @param  account_        The address of the voter to check.
     * @return votes_           The voter's voting power.
     */
    function getVotesScreening(uint24 distributionId_, address account_) external view returns (uint256 votes_);
}
