// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console } from "@std/console.sol";

import { IGrantFund } from "../../../src/grants/interfaces/IGrantFund.sol";

import { StandardTestBase } from "../base/StandardTestBase.sol";
import { StandardHandler }  from "../handlers/StandardHandler.sol";

contract ScreeningInvariant is StandardTestBase {

    function setUp() public override {
        super.setUp();

        startDistributionPeriod();

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _standardHandler.startNewDistributionPeriod.selector;
        selectors[1] = _standardHandler.propose.selector;
        selectors[2] = _standardHandler.screeningVote.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardHandler),
            selectors: selectors
        }));

    }

    function invariant_screening_stage() external {
        _invariant_SS1_SS3_SS4_SS5_SS6_SS7_SS9_SS10_SS11(_grantFund, _standardHandler);
        _invariant_SS2_SS4_SS8(_grantFund, _standardHandler);
    }

    function invariant_call_summary() external view {
        uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        // _standardHandler.logProposalSummary();
        _standardHandler.logActorSummary(distributionId, false, true);
    }

}