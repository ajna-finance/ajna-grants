// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IERC20 }          from "@oz/token/ERC20/IERC20.sol";
import { SafeERC20 }       from "@oz/token/ERC20/utils/SafeERC20.sol";

import { ProposalManager } from "./base/ProposalManager.sol";
import { RewardManager } from "./base/RewardManager.sol";

import { Storage } from "./base/Storage.sol";

import { IGrantFundActions } from "./interfaces/IGrantFundActions.sol";

import { Maths } from "./libraries/Maths.sol";

contract GrantFund is ProposalManager, RewardManager {

    using SafeERC20 for IERC20;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(address ajnaToken_) {
        ajnaTokenAddress = ajnaToken_;
    }

    /*******************************/
    /*** External View Functions ***/
    /*******************************/

    /// @inheritdoc IGrantFundActions
    function getDescriptionHash(
        string memory description_
    ) external pure override returns (bytes32) {
        return _getDescriptionHash(description_);
    }

    /// @inheritdoc IGrantFundActions
    function getDelegateReward(
        uint24 distributionId_,
        address voter_
    ) external view override returns (uint256 rewards_) {
        DistributionPeriod memory currentDistribution = _distributions[distributionId_];
        QuadraticVoter        memory voter               = _quadraticVoters[distributionId_][voter_];

        rewards_ = _getDelegateReward(currentDistribution, voter);
    }

    /// @inheritdoc IGrantFundActions
    function getDistributionId() external view override returns (uint24) {
        return _currentDistributionId;
    }

    /// @inheritdoc IGrantFundActions
    function getDistributionPeriodInfo(
        uint24 distributionId_
    ) external view override returns (uint24, uint48, uint48, uint128, uint256, bytes32) {
        return (
            _distributions[distributionId_].id,
            _distributions[distributionId_].startBlock,
            _distributions[distributionId_].endBlock,
            _distributions[distributionId_].fundsAvailable,
            _distributions[distributionId_].fundingVotePowerCast,
            _distributions[distributionId_].fundedSlateHash
        );
    }

    /// @inheritdoc IGrantFundActions
    function getFundedProposalSlate(
        bytes32 slateHash_
    ) external view override returns (uint256[] memory) {
        return _fundedProposalSlates[slateHash_];
    }

    /// @inheritdoc IGrantFundActions
    function getFundingPowerVotes(
        uint256 votingPower_
    ) external pure override returns (uint256) {
        return Maths.wsqrt(votingPower_);
    }

    /// @inheritdoc IGrantFundActions
    function getFundingVotesCast(
        uint24 distributionId_,
        address account_
    ) external view override returns (FundingVoteParams[] memory) {
        return _quadraticVoters[distributionId_][account_].votesCast;
    }

    /// @inheritdoc IGrantFundActions
    function getProposalInfo(
        uint256 proposalId_
    ) external view override returns (uint256, uint24, uint128, uint128, int128, bool) {
        return (
            _proposals[proposalId_].proposalId,
            _proposals[proposalId_].distributionId,
            _proposals[proposalId_].votesReceived,
            _proposals[proposalId_].tokensRequested,
            _proposals[proposalId_].fundingVotesReceived,
            _proposals[proposalId_].executed
        );
    }

    /// @inheritdoc IGrantFundActions
    function getSlateHash(
        uint256[] calldata proposalIds_
    ) external pure override returns (bytes32) {
        return keccak256(abi.encode(proposalIds_));
    }

    /// @inheritdoc IGrantFundActions
    function getTopTenProposals(
        uint24 distributionId_
    ) external view override returns (uint256[] memory) {
        return _topTenProposals[distributionId_];
    }

    /// @inheritdoc IGrantFundActions
    function getVoterInfo(
        uint24 distributionId_,
        address account_
    ) external view override returns (uint128, uint128, uint256) {
        return (
            _quadraticVoters[distributionId_][account_].votingPower,
            _quadraticVoters[distributionId_][account_].remainingVotingPower,
            _quadraticVoters[distributionId_][account_].votesCast.length
        );
    }

    /// @inheritdoc IGrantFundActions
    function getVotesFunding(
        uint24 distributionId_,
        address account_
    ) external view override returns (uint256 votes_) {
        DistributionPeriod memory currentDistribution = _distributions[distributionId_];
        QuadraticVoter        memory voter               = _quadraticVoters[currentDistribution.id][account_];

        uint256 screeningStageEndBlock = _getScreeningStageEndBlock(currentDistribution.endBlock);

        votes_ = _getVotesFunding(account_, voter.votingPower, voter.remainingVotingPower, screeningStageEndBlock);
    }

    /// @inheritdoc IGrantFundActions
    function getVotesScreening(
        uint24 distributionId_,
        address account_
    ) external view override returns (uint256 votes_) {
        votes_ = _getVotesScreening(distributionId_, account_);
    }

}
