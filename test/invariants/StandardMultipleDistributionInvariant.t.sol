// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console }  from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";
import { Maths }            from "../../src/grants/libraries/Maths.sol";

import { StandardTestBase } from "./base/StandardTestBase.sol";
import { StandardHandler }  from "./handlers/StandardHandler.sol";
import { Handler }          from "./handlers/Handler.sol";

contract StandardMultipleDistributionInvariant is StandardTestBase {

    // run tests against all functions, having just started a distribution period
    function setUp() public override {
        super.setUp();

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = _standardHandler.startNewDistributionPeriod.selector;
        selectors[1] = _standardHandler.proposeStandard.selector;
        selectors[2] = _standardHandler.screeningVote.selector;
        selectors[3] = _standardHandler.fundingVote.selector;
        selectors[4] = _standardHandler.updateSlate.selector;
        selectors[5] = _standardHandler.executeStandard.selector;
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

        console.log("starting block number: %s", block.number);
    }

    // TODO: add common asserts for these invariants across test files?
    // TODO: check current treasury and token balance?
    function invariant_DP1_DP2_DP3_DP4() external {
        uint24 distributionId = _grantFund.getDistributionId();
        (, uint256 startBlockCurrent, uint256 endBlockCurrent, uint128 fundsAvailableCurrent, , ) = _grantFund.getDistributionPeriodInfo(distributionId);

        uint24 i = distributionId;
        while (i > 0) {
            (, uint256 startBlockPrev, uint256 endBlockPrev, uint128 fundsAvailable, , ) = _grantFund.getDistributionPeriodInfo(i);
            StandardHandler.DistributionState memory state = _standardHandler.getDistributionState(i);

            require(
                fundsAvailable == Maths.wmul(.03 * 1e18, state.treasuryAtStartBlock + fundsAvailable),
                "invariant DP3: A distribution's fundsAvailable should be equal to 3% of the treasurie's balance at the block `startNewDistributionPeriod()` is called"
            );

            require(
                endBlockPrev > startBlockPrev,
                "invariant DP4: A distribution's endBlock should be greater than its startBlock"
            );

            // check each distribution period's end block and ensure that only 1 has an endblock not in the past.
            if (i != distributionId) {
                require(
                    endBlockPrev < startBlockCurrent && endBlockPrev < currentBlock,
                    "invariant DP1: Only one distribution period should be active at a time"
                );

                // decrement blocks to ensure that the next distribution period's end block is less than the current block
                startBlockCurrent = startBlockPrev;
                endBlockCurrent = endBlockPrev;
            }

            uint256[] memory topTenProposals = _grantFund.getTopTenProposals(i);
            uint256 totalTokensRequestedByExecutedProposals = 0;

            // check each distribution period's top ten slate of proposals for executions and compare with distribution funds available
            for (uint p = 0; p < topTenProposals.length; ++p) {
                // get proposal info
                (, uint24 proposalDistributionId, , uint128 tokensRequested, , bool executed) = _grantFund.getProposalInfo(topTenProposals[p]);
                assertEq(proposalDistributionId, i);

                if (executed) {
                    // invariant DP2: Each winning proposal successfully claims no more that what was finalized in the challenge stage
                    assertLt(tokensRequested, fundsAvailable);
                    assertTrue(totalTokensRequestedByExecutedProposals <= fundsAvailable);

                    totalTokensRequestedByExecutedProposals += tokensRequested;
                }
            }

            // check the top funded proposal slate
            totalTokensRequestedByExecutedProposals = 0;
            uint256[] memory proposalSlate = _grantFund.getFundedProposalSlate(state.currentTopSlate);
            for (uint j = 0; j < proposalSlate.length; ++j) {
                (, uint24 proposalDistributionId, , uint128 tokensRequested, , bool executed) = _grantFund.getProposalInfo(proposalSlate[j]);
                assertEq(proposalDistributionId, i);

                if (executed) {
                    // invariant DP2: Each winning proposal successfully claims no more that what was finalized in the challenge stage
                    assertLt(tokensRequested, fundsAvailable);
                    assertTrue(totalTokensRequestedByExecutedProposals <= fundsAvailable);

                    totalTokensRequestedByExecutedProposals += tokensRequested;
                }
            }

            --i;
        }
    }

    function invariant_GF2() external {
        // invariant GF2: The Grant Fund's treasury should always be less than or equal to the contract's token blance.
        assertTrue(_ajna.balanceOf(address(_grantFund)) >= _grantFund.treasury());

        // TODO: invariant GF3: The treasury balance should be greater than the sum of the funds available in all distribution periods
    }

    function invariant_call_summary() external view {
        uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        // _standardHandler.logProposalSummary();
        // _standardHandler.logActorSummary(distributionId, true, true);

        console.log("current distributionId: %s", distributionId);
        console.log("block number:           %s", block.number);
        console.log("current block:          %s", currentBlock);
        // TODO: need to be able to log all the different type of summaries
        // _logFinalizeSummary(distributionId);
    }
}
