// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "@std/Test.sol";

import { Deployer }  from "../../src/grants/Deployer.sol";
import { GrantFund } from "../../src/grants/GrantFund.sol";
import { TestAjnaToken } from "../utils/harness/TestAjnaToken.sol";

contract DeployerTest is Test {

    function testGrantFundDeployment() external {
        address owner = makeAddr("owner");
        vm.startPrank(owner);

        uint256 treasury = 50_000_000 * 1e18;

        TestAjnaToken ajnaToken = new TestAjnaToken();
        ajnaToken.mint(owner, treasury);

        Deployer deployer = new Deployer();
        ajnaToken.approve(address(deployer), treasury);

        GrantFund grantFund = deployer.deployGrantFund(address(ajnaToken), treasury);

        assertEq(grantFund.getDistributionId(), 1);

        (,,,uint256 fundAvailable,,) = grantFund.getDistributionPeriodInfo(1);

        assertEq(grantFund.treasury(), treasury - fundAvailable);

        assertEq(fundAvailable, treasury * 3 / 100);
    }
}