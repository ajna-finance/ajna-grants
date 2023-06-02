// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.18;

/**
 * @title Grant Fund Events.
 */
interface IGrantFundEvents {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when a new top ten slate is submitted and set as the leading optimized slate.
     *  @param  distributionId  Id of the distribution period.
     *  @param  fundedSlateHash Hash of the proposals to be funded.
     */
    event FundedSlateUpdated(
        uint256 indexed distributionId,
        bytes32 indexed fundedSlateHash
    );

    /**
     *  @notice Emitted at the beginning of a new distribution period.
     *  @param  distributionId Id of the new distribution period.
     *  @param  startBlock     Block number of the distribution period start.
     *  @param  endBlock       Block number of the distribution period end.
     */
    event DistributionPeriodStarted(
        uint256 indexed distributionId,
        uint256 startBlock,
        uint256 endBlock
    );

    /**
     *  @notice Emitted when delegatee claims their rewards.
     *  @param  delegateeAddress Address of delegatee.
     *  @param  distributionId   Id of distribution period.
     *  @param  rewardClaimed    Amount of Reward Claimed.
     */
    event DelegateRewardClaimed(
        address indexed delegateeAddress,
        uint256 indexed distributionId,
        uint256 rewardClaimed
    );

    /**
     *  @notice Emitted when Ajna tokens are transferred to the GrantFund contract.
     *  @param  amount          Amount of Ajna tokens transferred.
     *  @param  treasuryBalance GrantFund's total treasury balance after the transfer.
     */
    event FundTreasury(uint256 amount, uint256 treasuryBalance);

    /**
     * @notice Emitted when a proposal is executed.
     * @dev Compatibile with interface used by Compound Governor Bravo and OpenZeppelin Governor.
     * @param proposalId Id of the proposal executed.
     */
    event ProposalExecuted(uint256 proposalId);

    /**
     * @notice Emitted when a proposal is created.
     * @dev Compatibile with interface used by Compound Governor Bravo and OpenZeppelin Governor.
     * @param proposalId  Id of the proposal created.
     * @param proposer    Address of the proposer.
     * @param targets     List of addresses of the contracts called by proposal's associated transactions.
     * @param values      List of values in wei for each proposal's associated transaction.
     * @param signatures  List of function signatures (can be empty) of the proposal's associated transactions.
     * @param calldatas   List of calldatas: calldata format is [functionId (4 bytes)][packed arguments (32 bytes per argument)].
     *                    Calldata is always transfer(address,uint256) for Ajna distribution proposals.
     * @param startBlock  Block number when the distribution period and screening stage begins:
     *                    holders must delegate their votes for the period 34 prior to this block to vote in the screening stage.
     * @param endBlock    Block number when the distribution period ends.
     * @param description Description of the proposal.
     */
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    /**
     * @notice Emitted when votes are cast on a proposal.
     * @dev Compatibile with interface used by Compound Governor Bravo and OpenZeppelin Governor.
     * @param voter      Address of the voter.
     * @param proposalId Id of the proposal voted on.
     * @param support    Indicates if the voter supports the proposal (0=against, 1=for).
     * @param weight     Amount of votes cast on the proposal.
     * @param reason     Reason given by the voter for or against the proposal.
     */
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
}

