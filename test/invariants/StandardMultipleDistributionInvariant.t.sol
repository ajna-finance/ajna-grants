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
    }

    // TODO: rename to current and next
    // TODO: add common asserts for these invariants across test files?
    // TODO: check current treasury and token balance?
    function invariant_DP1_DP2_DP3_DP4_DP5_DP6() external {
        uint24 distributionId = _grantFund.getDistributionId();
        (
            ,
            uint256 startBlockCurrent,
            uint256 endBlockCurrent,
            uint128 fundsAvailableCurrent,
            ,
        ) = _grantFund.getDistributionPeriodInfo(distributionId);

        uint256 totalFundsAvailable = 0;
        uint256 currentTreasury = _grantFund.treasury();

        uint24 i = distributionId;
        while (i > 0) {
            (
                ,
                uint256 startBlockPrev,
                uint256 endBlockPrev,
                uint128 fundsAvailablePrev,
                ,
                bytes32 topSlateHash
            ) = _grantFund.getDistributionPeriodInfo(i);
            StandardHandler.DistributionState memory state = _standardHandler.getDistributionState(i);

            totalFundsAvailable += fundsAvailablePrev;
            require(
                totalFundsAvailable < currentTreasury,
                "invariant DP5: The treasury balance should be greater than the sum of the funds available in all distribution periods"
            );

            require(
                fundsAvailablePrev == Maths.wmul(.03 * 1e18, state.treasuryAtStartBlock + fundsAvailablePrev),
                "invariant DP3: A distribution's fundsAvailablePrev should be equal to 3% of the treasurie's balance at the block `startNewDistributionPeriod()` is called"
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
            uint256 totalTokensRequestedByProposals = 0;

            // check each distribution period's top ten slate of proposals for executions and compare with distribution funds available
            for (uint p = 0; p < topTenProposals.length; ++p) {
                // get proposal info
                (
                    ,
                    uint24 proposalDistributionId,
                    ,
                    uint128 tokensRequested,
                    ,
                    bool executed
                ) = _grantFund.getProposalInfo(topTenProposals[p]);
                assertEq(proposalDistributionId, i);

                if (executed) {
                    // invariant DP2: Each winning proposal successfully claims no more that what was finalized in the challenge stage
                    assertLt(tokensRequested, fundsAvailablePrev);
                    assertTrue(totalTokensRequestedByProposals <= fundsAvailablePrev);

                    totalTokensRequestedByProposals += tokensRequested;
                }
            }

            // check the top funded proposal slate
            totalTokensRequestedByProposals = 0;
            uint256[] memory proposalSlate = _grantFund.getFundedProposalSlate(state.currentTopSlate);
            for (uint j = 0; j < proposalSlate.length; ++j) {
                (
                    ,
                    uint24 proposalDistributionId,
                    ,
                    uint128 tokensRequested,
                    ,
                    bool executed
                ) = _grantFund.getProposalInfo(proposalSlate[j]);
                assertEq(proposalDistributionId, i);

                if (executed) {
                    // invariant DP2: Each winning proposal successfully claims no more that what was finalized in the challenge stage
                    assertLt(tokensRequested, fundsAvailablePrev);
                    assertTrue(totalTokensRequestedByProposals <= fundsAvailablePrev);

                    totalTokensRequestedByProposals += tokensRequested;
                }
            }

            {
                if (i != distributionId) {
                    // assertTrue(false);
                    // FIXME: if new distribution started before end of distribution period then surplus won't be added automatically to the treasury...
                    // only add the surplus if the proposal was executed?

                    uint256 surplus = 0;
                    if (startBlockCurrent > endBlockPrev + 50400) {
                        // then the treasury should have updated
                        surplus = fundsAvailablePrev - totalTokensRequestedByProposals;
                    }

                    console.log("surplus:               ", surplus);
                    console.log("treasuryAtStartBlock:  ", state.treasuryAtStartBlock);
                    console.log("fundsAvailableCurrent: ", fundsAvailableCurrent);
                    console.log("fundsAvailablePrev:    ", fundsAvailablePrev);
                    console.log(fundsAvailableCurrent == Maths.wmul(.03 * 1e18, surplus + state.treasuryAtStartBlock));

                    // TODO: need to be able to look back multiple distribution periods to see if the treasury was updated

                    require(
                        fundsAvailableCurrent == Maths.wmul(.03 * 1e18, surplus + state.treasuryAtStartBlock),
                        "invariant DP6: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury"
                    );
                    fundsAvailableCurrent = fundsAvailablePrev;
                }
            }

            --i;
        }
    }

    function invariant_T1() external {
        // invariant T1: The Grant Fund's treasury should always be less than or equal to the contract's token blance.
        assertTrue(_ajna.balanceOf(address(_grantFund)) >= _grantFund.treasury());
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
