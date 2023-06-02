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
     * @dev Emitted when a proposal is executed.
     * @dev Compatibile with interface used by Compound Governor Bravo and OpenZeppelin Governor.
     */
    event ProposalExecuted(uint256 proposalId);

    /**
     * @dev Emitted when a proposal is created.
     * @dev Compatibile with interface used by Compound Governor Bravo and OpenZeppelin Governor.
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
     * @dev Emitted when votes are cast on a proposal.
     * @dev Compatibile with interface used by Compound Governor Bravo and OpenZeppelin Governor.
     */
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
}

