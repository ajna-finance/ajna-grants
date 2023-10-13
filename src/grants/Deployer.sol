// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { GrantFund } from "./GrantFund.sol";

contract Deployer {

    error IncorrectTreasuryBalance();

    error DistributionNotStarted();

    GrantFund public grantFund;

    function deployGrantFund(address ajnaToken_, uint256 treasury_) public returns (GrantFund grantFund_) {
        
        // deploy grant Fund
        grantFund_ = new GrantFund(ajnaToken_);

        // Approve ajna token to fund treasury
        IERC20(ajnaToken_).approve(address(grantFund_), treasury_);

        // Transfer treasury ajna tokens to Deployer contract
        IERC20(ajnaToken_).transferFrom(msg.sender, address(this), treasury_);

        // Fund treasury and start new distribution
        grantFund_.fundTreasury(treasury_);
        grantFund_.startNewDistributionPeriod();

        // check treasury balance is correct
        if(IERC20(ajnaToken_).balanceOf(address(grantFund_)) != treasury_) revert IncorrectTreasuryBalance();

        // check new distribution started
        if(grantFund_.getDistributionId() != 1) revert DistributionNotStarted();

        grantFund = grantFund_;
    }
}