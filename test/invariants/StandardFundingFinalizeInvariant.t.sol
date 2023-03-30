// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { StandardFundingTestBase } from "./base/StandardFundingTestBase.sol";
import { StandardFundingHandler } from "./handlers/StandardFundingHandler.sol";

contract StandardFundingFinalizeInvariant is StandardFundingTestBase {

    // override setup to start tests in the funding stage with proposals that have already been screened and funded
    function setUp() public override {
        super.setUp();

        // create 15 proposals
        _standardFundingHandler.createProposals(15);

        // vote on proposals
        _standardFundingHandler.screeningVoteProposals();

        // skip time into the funding stage
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        uint256 fundingStageStartBlock = endBlock - 72000;
        vm.roll(fundingStageStartBlock + 100);

        // TODO: voter's cast funding votes randomly

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _standardFundingHandler.fundingVote.selector;
        selectors[1] = _standardFundingHandler.updateSlate.selector;
        selectors[2] = _standardFundingHandler.executeStandard.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardFundingHandler),
            selectors: selectors
        }));
    }

}
