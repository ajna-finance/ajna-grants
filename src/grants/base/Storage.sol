// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IGrantFundState } from "../interfaces/IGrantFundState.sol";

abstract contract Storage is IGrantFundState {

    /*****************/
    /*** Constants ***/
    /*****************/

    /**
     * @notice Maximum percentage of tokens that can be distributed by the treasury in a quarter.
     * @dev Stored as a Wad percentage.
     */
    uint256 internal constant GLOBAL_BUDGET_CONSTRAINT = 0.03 * 1e18;

    /**
     * @notice Length of the challengephase of the distribution period in blocks.
     * @dev    Roughly equivalent to the number of blocks in 7 days.
     * @dev    The period in which funded proposal slates can be checked in updateSlate.
     */
    uint256 internal constant CHALLENGE_PERIOD_LENGTH = 50400;

    /**
     * @notice Length of the distribution period in blocks.
     * @dev    Roughly equivalent to the number of blocks in 97 days.
     */
    uint48 internal constant DISTRIBUTION_PERIOD_LENGTH = 698400;

    /**
     * @notice Length of the funding stage of the distribution period in blocks.
     * @dev    Roughly equivalent to the number of blocks in 10 days.
     */
    uint256 internal constant FUNDING_PERIOD_LENGTH = 72000;

    /**
     * @notice Length of the screening stage of the distribution period in blocks.
     * @dev    Roughly equivalent to the number of blocks in 80 days.
     */
    uint256 internal constant SCREENING_PERIOD_LENGTH = 576000;

    /**
     * @notice Number of blocks prior to a given voting stage to check an accounts voting power.
     * @dev    Prevents flashloan attacks or duplicate voting with multiple accounts.
     */
    uint256 internal constant VOTING_POWER_SNAPSHOT_DELAY = 33;

    /***********************/
    /*** State Variables ***/
    /***********************/

    // address of the ajna token used in grant coordination
    address public ajnaTokenAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /**
     * @notice ID of the current distribution period.
     * @dev Used to access information on the status of an ongoing distribution.
     * @dev Updated at the start of each quarter.
     * @dev Monotonically increases by one per period.
     */
    uint24 internal _currentDistributionId = 0;

    /**
     * @notice Mapping of distribution periods from the grant fund.
     * @dev distributionId => DistributionPeriod
     */
    mapping(uint24 => DistributionPeriod) internal _distributions;

    /**
     * @dev Mapping of all proposals that have ever been submitted to the grant fund for screening.
     * @dev proposalId => Proposal
     */
    mapping(uint256 => Proposal) internal _proposals;

    /**
     * @dev Mapping of distributionId to a sorted array of 10 proposalIds with the most votes in the screening period.
     * @dev distribution.id => proposalId[]
     * @dev A new array is created for each distribution period
     */
    mapping(uint256 => uint256[]) internal _topTenProposals;

    /**
     * @notice Mapping of a hash of a proposal slate to a list of funded proposals.
     * @dev slate hash => proposalId[]
     */
    mapping(bytes32 => uint256[]) internal _fundedProposalSlates;

    /**
     * @notice Mapping of distribution periods to voters to a Quadratic Voter info struct.
     * @dev distributionId => voter address => QuadraticVoter 
     */
    mapping(uint256 => mapping(address => QuadraticVoter)) internal _quadraticVoters;

    /**
     * @notice Mapping of distributionId to whether surplus funds from distribution updated into treasury
     * @dev distributionId => bool
    */
    mapping(uint256 => bool) internal _isSurplusFundsUpdated;

    /**
     * @notice Mapping of distributionId to user address to whether user has claimed their delegate reward
     * @dev distributionId => address => bool
    */
    mapping(uint256 => mapping(address => bool)) public hasClaimedReward;

    /**
     * @notice Mapping of distributionId to user address to total votes cast on screening stage proposals.
     * @dev distributionId => address => uint256
    */
    mapping(uint256 => mapping(address => uint256)) public screeningVotesCast;

    /**
     * @notice Total funds available for distribution.
    */
    uint256 public treasury;
}
