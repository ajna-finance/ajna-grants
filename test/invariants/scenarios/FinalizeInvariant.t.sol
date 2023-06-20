// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";

import { StandardTestBase } from "../base/StandardTestBase.sol";
import { StandardHandler }  from "../handlers/StandardHandler.sol";
import { Handler }          from "../handlers/Handler.sol";

contract FinalizeInvariant is StandardTestBase {

    // override setup to start tests in the challenge stage with proposals that have already been screened and funded
    function setUp() public override {
        super.setUp();

        startDistributionPeriod();

        // create 15 proposals
        _standardHandler.createProposals(15);

        // cast screening votes on proposals
        _standardHandler.screeningVoteProposals();

        // skip time into the funding stage
        uint24 distributionId = _grantFund.getDistributionId();
        (, uint256 startBlock, uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        uint256 fundingStageStartBlock = _grantFund.getScreeningStageEndBlock(startBlock) + 1;
        vm.roll(fundingStageStartBlock + 100);
        currentBlock = fundingStageStartBlock + 100;

        // cast funding votes on proposals
        _standardHandler.fundingVoteProposals();

        _standardHandler.setCurrentScenarioType(Handler.ScenarioType.Medium);

        // skip time into the challenge stage
        uint256 challengeStageStartBlock = _grantFund.getChallengeStageStartBlock(endBlock);
        vm.roll(challengeStageStartBlock + 100);
        currentBlock = challengeStageStartBlock + 100;

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = _standardHandler.fundingVote.selector;
        selectors[1] = _standardHandler.updateSlate.selector;
        selectors[2] = _standardHandler.execute.selector;
        selectors[3] = _standardHandler.claimDelegateReward.selector;
        selectors[4] = _standardHandler.roll.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardHandler),
            selectors: selectors
        }));

        //  check test setup
        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(distributionId);
        assertTrue(topTenProposals.length > 0);
    }

    function invariant_finalize() external useCurrentBlock {
        _invariant_CS1_CS2_CS3_CS4_CS5_CS6(_grantFund, _standardHandler);
        _invariant_ES1_ES2_ES3_ES4_ES5(_grantFund, _standardHandler);
        _invariant_DR1_DR2_DR3_DR4_DR5(_grantFund, _standardHandler);
    }

    function invariant_call_summary() external useCurrentBlock {
        uint24 distributionId = _grantFund.getDistributionId();

        _logger.logCallSummary();
        _logger.logTimeSummary();
        _logger.logFinalizeSummary(distributionId);
        _logger.logActorSummary(distributionId, false, false);
        _logger.logProposalSummary();
        _logger.logActorDelegationRewards(distributionId);
    }

}
