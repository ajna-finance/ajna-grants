// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IERC20 }    from "@oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@oz/token/ERC20/utils/SafeERC20.sol";

import { StandardFunding }      from "./base/StandardFunding.sol";

import { IGrantFund } from "./interfaces/IGrantFund.sol";

contract GrantFund is IGrantFund, StandardFunding {

    using SafeERC20 for IERC20;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(address ajnaToken_) {
        ajnaTokenAddress = ajnaToken_;
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /// @inheritdoc IGrantFund
    function hashProposal(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external pure override returns (uint256 proposalId_) {
        proposalId_ = _hashProposal(targets_, values_, calldatas_, descriptionHash_);
    }

    /// @inheritdoc IGrantFund
    function state(
        uint256 proposalId_
    ) external view override returns (ProposalState) {
        return _getStandardProposalState(proposalId_);
    }

    /**************************/
    /*** Treasury Functions ***/
    /**************************/

    /// @inheritdoc IGrantFund
    function fundTreasury(uint256 fundingAmount_) external override {
        IERC20 token = IERC20(ajnaTokenAddress);

        // update treasury accounting
        treasury += fundingAmount_;

        emit FundTreasury(fundingAmount_, treasury);

        // transfer ajna tokens to the treasury
        token.safeTransferFrom(msg.sender, address(this), fundingAmount_);
    }

}
