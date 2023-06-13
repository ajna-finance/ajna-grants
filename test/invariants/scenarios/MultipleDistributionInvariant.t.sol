// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { Maths }            from "../../../src/grants/libraries/Maths.sol";

import { StandardTestBase } from "../base/StandardTestBase.sol";
import { StandardHandler }  from "../handlers/StandardHandler.sol";
import { Handler }          from "../handlers/Handler.sol";

contract MultipleDistributionInvariant is StandardTestBase {

    // run tests against all functions, having just started a distribution period
    function setUp() public override {
        super.setUp();

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = _standardHandler.startNewDistributionPeriod.selector;
        selectors[1] = _standardHandler.propose.selector;
        selectors[2] = _standardHandler.screeningVote.selector;
        selectors[3] = _standardHandler.fundingVote.selector;
        selectors[4] = _standardHandler.updateSlate.selector;
        selectors[5] = _standardHandler.execute.selector;
        selectors[6] = _standardHandler.claimDelegateReward.selector;
        selectors[7] = _standardHandler.roll.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardHandler),
            selectors: selectors
        }));

        // update scenarioType to fast to have larger rolls
        _standardHandler.setCurrentScenarioType(Handler.ScenarioType.Fast);

        vm.roll(block.number + 100);
        currentBlock = block.number;
    }

    function invariant_distribution_period() external {
        // _invariant_DP1_DP2_DP3_DP4_DP5(_grantFund, _standardHandler);
        // _invariant_DP6(_grantFund, _standardHandler);
        // _invariant_T1_T2(_grantFund, _standardHandler);
    }

    function invariant_all() external {
        // // screening invariants
        _invariant_SS1_SS3_SS4_SS5_SS6_SS7_SS9_SS10_SS11(_grantFund, _standardHandler);
        // _invariant_SS2_SS4_SS8(_grantFund, _standardHandler); // WORKING

        // // funding invariants
        // _invariant_FS1_FS2_FS3(_grantFund, _standardHandler);
        // _invariant_FS4_FS5_FS6_FS7_FS8(_grantFund, _standardHandler);

        // finalize invariants
        // _invariant_CS1_CS2_CS3_CS4_CS5_CS6(_grantFund, _standardHandler); // WORKING
        // _invariant_ES1_ES2_ES3_ES4_ES5(_grantFund, _standardHandler); // WORKING
        // _invariant_DR1_DR2_DR3_DR4_DR5(_grantFund, _standardHandler); // WORKING
    }

    function invariant_call_summary() external view {
        // uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        _standardHandler.logTimeSummary();

        console.log("scenario type", uint8(_standardHandler.getCurrentScenarioType()));

        console.log("Delegation Rewards:         ", _standardHandler.numberOfCalls('delegationRewardSet'));
        console.log("Delegation Rewards Claimed: ", _standardHandler.numberOfCalls('SFH.claimDelegateReward.success'));
        console.log("Proposal Execute attempt:   ", _standardHandler.numberOfCalls('SFH.execute.attempt'));
        console.log("Proposal Execute Count:     ", _standardHandler.numberOfCalls('SFH.execute.success'));
        console.log("Slate Update Prep:          ", _standardHandler.numberOfCalls('SFH.updateSlate.prep'));
        console.log("Slate Update length:        ", _standardHandler.numberOfCalls('updateSlate.length'));
        console.log("Slate Update Called:        ", _standardHandler.numberOfCalls('SFH.updateSlate.called'));
        console.log("Slate Update Success:       ", _standardHandler.numberOfCalls('SFH.updateSlate.success'));
        console.log("Slate Proposals:            ", _standardHandler.numberOfCalls('proposalsInSlates'));
        console.log("unused proposal:            ", _standardHandler.numberOfCalls('unused.proposal'));
        console.log("unexecuted proposal:        ", _standardHandler.numberOfCalls('unexecuted.proposal'));
        console.log("funding stage starts:       ", _standardHandler.numberOfCalls("SFH.FundingStage"));
        console.log("funding stage success votes ", _standardHandler.numberOfCalls("SFH.fundingVote.success"));


        (, , , , uint256 fundingPowerCast, ) = _grantFund.getDistributionPeriodInfo(2);
        console.log("Total Funding Power Cast    ", fundingPowerCast);


        if (_standardHandler.numberOfCalls('unexecuted.proposal') != 0) {
            console.log("state of unexecuted:        ", uint8(_grantFund.state(_standardHandler.numberOfCalls('unexecuted.proposal'))));
        }
        // _standardHandler.logProposalSummary();
        // _standardHandler.logActorSummary(distributionId, true, true);
    }
}