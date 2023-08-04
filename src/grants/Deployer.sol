// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { GrantFund } from "./GrantFund.sol";

contract Deployer {

    GrantFund public grantFund;

    function deployGrantFund(address ajnaToken_, uint256 treasury_) public returns (GrantFund) {

        IERC20(ajnaToken_).transferFrom(msg.sender, address(this), treasury_);

        grantFund = new GrantFund(ajnaToken_);

        IERC20(ajnaToken_).approve(address(grantFund), treasury_);

        grantFund.fundTreasury(treasury_);

        grantFund.startNewDistributionPeriod();
        return grantFund;
    }
}