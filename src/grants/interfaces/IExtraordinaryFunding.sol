// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.16;

/**
 * @title Ajna Grant Coordination Fund Extraordinary Proposal flow.
 */
interface IExtraordinaryFunding {

    /**************/
    /*** Errors ***/
    /**************/

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
        uint128  startBlock;      // Block number of the start of the extraordinary funding proposal voting period.
        uint128  endBlock;        // Block number of the end of the extraordinary funding proposal voting period.
        uint128  tokensRequested; // Number of AJNA tokens requested.
        uint120  votesReceived;   // Total votes received for this proposal.
        bool     executed;        // Whether the proposal has been executed or not.
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Execute an extraordinary funding proposal if it has passed its' requisite vote threshold.
     * @param targets         The addresses of the contracts to call.
     * @param values          The amounts of ETH to send to each target.
     * @param calldatas       The calldata to send to each target.
     * @param descriptionHash The hash of the proposal's description.
     * @return proposalId     The ID of the executed proposal.
     */
    function executeExtraordinary(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256 proposalId);

    /**
     * @notice Submit a proposal to the extraordinary funding flow.
     * @param endBlock_            Block number of the end of the extraordinary funding proposal voting period.
     * @param targets             Array of addresses to send transactions to.
     * @param values              Array of values to send with transactions.
     * @param calldatas           Array of calldata to execute in transactions.
     * @param description_         Description of the proposal.
     * @return proposalId         ID of the newly submitted proposal.
     */
    function proposeExtraordinary(
        uint256 endBlock_,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description_
    ) external returns (uint256 proposalId);

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @notice Vote on a proposal for extraordinary funding.
     * @dev    Votes can only be cast affirmatively, or not cast at all.
     * @dev    A proposal can only be voted upon once, with the entirety of a voter's voting power.
     * @param  proposalId The ID of the proposal being voted upon.
     * @return votesCast_  The amount of votes cast.
     */
    function voteExtraordinary(
        uint256 proposalId
    ) external returns (uint256 votesCast_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param  percentage The percentage of the Non treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getSliceOfNonTreasury(
        uint256 percentage
    ) external view returns (uint256);

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage The percentage of the treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getSliceOfTreasury(
        uint256 percentage
    ) external view returns (uint256);

    /**
     *  @notice Mapping of proposalIds to {ExtraordinaryFundingProposal} structs.
     *  @param  proposalId     The proposalId to retrieve information about.
     *  @return proposalId      The retrieved struct's proposalId.
     *  @return startBlock      The block at which the proposal was submitted.
     *  @return endBlock        The block by which the proposal must pass.
     *  @return tokensRequested Amount of Ajna tokens requested by the proposal.
     *  @return votesReceived   Number of votes the proposal has received. One Ajna token is one vote.
     *  @return executed        Whether a succesful proposal has been executed.
     */
    function getExtraordinaryProposalInfo(
        uint256 proposalId
    ) external view returns (uint256, uint128, uint128, uint128, uint120, bool);

    /**
     * @notice Check if an extraordinary funding proposal met the requirements for execution.
     * @param  proposalId The ID of the proposal to check the status of.
     * @return True if the proposal was successful, false if not.
     */
    function getExtraordinaryProposalSucceeded(uint256 proposalId) external view returns (bool);

    /**
     * @notice Get the current minimum threshold percentage of Ajna tokens required for a proposal to exceed.
     * @return The minimum threshold percentage, in WAD.
     */
    function getMinimumThresholdPercentage() external view returns (uint256);

    /**
     * @notice Get an accounts voting power available for casting on a given proposal.
     * @dev    If the account has already voted on the proposal, the returned value will be 0.
     * @param  account    The address of the voter to check.
     * @param  proposalId The ID of the proposal being voted on.
     * @return             An accounts current voting power.
     */
    function getVotesExtraordinary(address account, uint256 proposalId) external view returns (uint256);

}
