// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IERC20 }          from "@oz/token/ERC20/IERC20.sol";
import { SafeCast }        from "@oz/utils/math/SafeCast.sol";
import { SafeERC20 }       from "@oz/token/ERC20/utils/SafeERC20.sol";

import { Storage } from "./Storage.sol";

import { IGrantFundActions } from "../interfaces/IGrantFundActions.sol";

import { Maths } from "../libraries/Maths.sol";

abstract contract DistributionManager is Storage {

    using SafeERC20 for IERC20;

    /**************************************************/
    /*** Distribution Management Functions External ***/
    /**************************************************/

    /// @inheritdoc IGrantFundActions
    function startNewDistributionPeriod() external override returns (uint24 newDistributionId_) {
        uint24  currentDistributionId       = _currentDistributionId;
        uint256 currentDistributionEndBlock = _distributions[currentDistributionId].endBlock;

        // check that there isn't currently an active distribution period
        if (block.number <= currentDistributionEndBlock) revert DistributionPeriodStillActive();

        // update Treasury with unused funds from last two distributions
        {
            // Check if any last distribution exists and its challenge stage is over
            if (currentDistributionId > 0 && (block.number > _getChallengeStageEndBlock(currentDistributionEndBlock))) {
                // Add unused funds from last distribution to treasury
                _updateTreasury(currentDistributionId);
            }

            // checks if any second last distribution exist and its unused funds are not added into treasury
            if (currentDistributionId > 1 && !_isSurplusFundsUpdated[currentDistributionId - 1]) {
                // Add unused funds from second last distribution to treasury
                _updateTreasury(currentDistributionId - 1);
            }
        }

        // set the distribution period to start at the current block
        uint48 startBlock = SafeCast.toUint48(block.number);
        uint48 endBlock = startBlock + DISTRIBUTION_PERIOD_LENGTH;

        // set new value for currentDistributionId
        newDistributionId_ = _setNewDistributionId();

        // create DistributionPeriod struct
        DistributionPeriod storage newDistributionPeriod = _distributions[newDistributionId_];
        newDistributionPeriod.id              = newDistributionId_;
        newDistributionPeriod.startBlock      = startBlock;
        newDistributionPeriod.endBlock        = endBlock;
        uint256 gbc                           = Maths.wmul(treasury, GLOBAL_BUDGET_CONSTRAINT);
        newDistributionPeriod.fundsAvailable  = SafeCast.toUint128(gbc);

        // decrease the treasury by the amount that is held for allocation in the new distribution period
        treasury -= gbc;

        emit DistributionPeriodStarted(
            newDistributionId_,
            startBlock,
            endBlock
        );
    }

    /// @inheritdoc IGrantFundActions
    function fundTreasury(uint256 fundingAmount_) external override {
        IERC20 token = IERC20(ajnaTokenAddress);

        // update treasury accounting
        treasury += fundingAmount_;

        emit FundTreasury(fundingAmount_, treasury);

        // transfer ajna tokens to the treasury
        token.safeTransferFrom(msg.sender, address(this), fundingAmount_);
    }

    /**************************************************/
    /*** Distribution Management Functions Internal ***/
    /**************************************************/

    /**
     * @notice Get the block number at which this distribution period's challenge stage ends.
     * @param  endBlock_ The end block of quarterly distribution to get the challenge stage end block for.
     * @return The block number at which this distribution period's challenge stage ends.
    */
    function _getChallengeStageEndBlock(
        uint256 endBlock_
    ) internal pure returns (uint256) {
        return endBlock_ + CHALLENGE_PERIOD_LENGTH;
    }

    /**
     * @notice Get the block number at which this distribution period's screening stage ends.
     * @param  endBlock_ The end block of quarterly distribution to get the screening stage end block for.
     * @return The block number at which this distribution period's screening stage ends.
    */
    function _getScreeningStageEndBlock(
        uint256 endBlock_
    ) internal pure returns (uint256) {
        return endBlock_ - FUNDING_PERIOD_LENGTH;
    }

    /**
     * @notice Updates Treasury with surplus funds from distribution.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length of at most 10.
     * @param distributionId_ distribution Id of updating distribution 
     */
    function _updateTreasury(
        uint24 distributionId_
    ) private {
        DistributionPeriod storage distribution = _distributions[distributionId_];
        bytes32 fundedSlateHash = distribution.fundedSlateHash;
        uint256 fundsAvailable  = distribution.fundsAvailable;

        uint256[] storage fundingProposalIds = _fundedProposalSlates[fundedSlateHash];

        uint256 totalTokenDistributed;
        uint256 numFundedProposals = fundingProposalIds.length;

        for (uint i = 0; i < numFundedProposals; ) {

            totalTokenDistributed += _proposals[fundingProposalIds[i]].tokensRequested;

            unchecked { ++i; }
        }

        uint256 totalDelegateRewards;
        // Increment totalTokenDistributed by delegate rewards if anyone has voted during funding voting
        if (_distributions[distributionId_].fundingVotePowerCast != 0) totalDelegateRewards = (fundsAvailable / 10);

        // re-add non distributed tokens to the treasury
        treasury += (fundsAvailable - totalTokenDistributed - totalDelegateRewards);

        _isSurplusFundsUpdated[distributionId_] = true;
    }

    /**
     * @notice Set a new DistributionPeriod Id.
     * @dev    Increments the previous Id nonce by 1.
     * @return newId_ The new distribution period Id.
     */
    function _setNewDistributionId() private returns (uint24 newId_) {
        newId_ = _currentDistributionId += 1;
    }

}
