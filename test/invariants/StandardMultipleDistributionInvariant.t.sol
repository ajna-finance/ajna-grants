// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

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

    function invariant_DP1_DP2_DP3_DP4_DP5() external {
        uint24 distributionId = _grantFund.getDistributionId();
        console.log("distributionId??", distributionId);
        (
            ,
            uint256 startBlockCurrent,
            uint256 endBlockCurrent,
            ,
            ,
        ) = _grantFund.getDistributionPeriodInfo(distributionId);

        uint256 totalFundsAvailable = 0;

        uint24 i = distributionId;
        while (i > 0) {
            (
                ,
                uint256 startBlockPrev,
                uint256 endBlockPrev,
                uint128 fundsAvailablePrev,
                ,
            ) = _grantFund.getDistributionPeriodInfo(i);
            StandardHandler.DistributionState memory state = _standardHandler.getDistributionState(i);
            uint256 currentTreasury = state.treasuryBeforeStart;

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

            uint256 totalTokensRequestedByProposals = 0;

            // check the top funded proposal slate
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
                }
                totalTokensRequestedByProposals += tokensRequested;
            }
            assertTrue(totalTokensRequestedByProposals <= fundsAvailablePrev);

            // check invariants against each previous distribution periods
            if (i != distributionId) {
                // check each distribution period's end block and ensure that only 1 has an endblock not in the past.
                require(
                    endBlockPrev < startBlockCurrent && endBlockPrev < currentBlock,
                    "invariant DP1: Only one distribution period should be active at a time"
                );

                // decrement blocks to ensure that the next distribution period's end block is less than the current block
                startBlockCurrent = startBlockPrev;
                endBlockCurrent = endBlockPrev;
            }

            --i;
        }
    }

    // function invariant_DP6() external {
    //     uint24 distributionId = _grantFund.getDistributionId();

    //     for (uint24 i = 0; i <= distributionId; ) {
    //         if (i == 0) {
    //             ++i;
    //             continue;
    //         }

    //         (
    //             ,
    //             ,
    //             ,
    //             uint128 fundsAvailable,
    //             ,
    //         ) = _grantFund.getDistributionPeriodInfo(i);
    //         StandardHandler.DistributionState memory state = _standardHandler.getDistributionState(i);

    //         // check prior distributions for surplus to return to treasury
    //         (
    //             ,
    //             ,
    //             uint256 endBlockPrev,
    //             uint128 fundsAvailablePrev,
    //             ,
    //             bytes32 topSlateHashPrev
    //         ) = _grantFund.getDistributionPeriodInfo(i - 1);

    //         StandardHandler.DistributionState memory prevState = _standardHandler.getDistributionState(i - 1);
    //         uint256 expectedTreasury = prevState.treasuryAtStartBlock;
    //         uint256 surplus = 0;

    //         // if new distribution started before end of distribution period then surplus won't be added automatically to the treasury.
    //         // only add the surplus if the distribution period started after the end of the prior challenge period
    //         if (i > 1 && _standardHandler.getDistributionStartBlock(i) > endBlockPrev + 50400) {
    //             console.log("path 1");
    //             surplus += _standardHandler.updateTreasury(i - 1, fundsAvailablePrev, topSlateHashPrev);
    //             _standardHandler.setDistributionTreasuryUpdated(i -1);
    //         }
    //         // check two distribution periods back for surplus to return to treasury
    //         if (i > 2 && !_standardHandler.distributionIdSurplusAdded(i - 2)) {
    //             (
    //                 ,
    //                 ,
    //                 ,
    //                 uint128 fundsAvailableBeforePrev,
    //                 ,
    //                 bytes32 topSlateHashBeforePrev
    //             ) = _grantFund.getDistributionPeriodInfo(i - 2);
    //             surplus += _standardHandler.updateTreasury(i - 2, fundsAvailableBeforePrev, topSlateHashBeforePrev);
    //             _standardHandler.setDistributionTreasuryUpdated(i -2);
    //         }

    //         expectedTreasury += surplus;

    //         if (i == 1) {
    //             require(
    //                 fundsAvailable == Maths.wmul(.03 * 1e18, state.treasuryBeforeStart),
    //                 "invariant DP6: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury"
    //             );
    //         }
    //         else {
    //             require(
    //                 fundsAvailable == Maths.wmul(.03 * 1e18, expectedTreasury),
    //                 "invariant DP6: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury"
    //             );
    //         }

    //         ++i;
    //     }
    // }

    function invariant_T1_T2() external view {
        require(
            _grantFund.treasury() <= _ajna.balanceOf(address(_grantFund)),
            "invariant T1: The Grant Fund's treasury should always be less than or equal to the contract's token blance"
        );

        require(
            _grantFund.treasury() <= _ajna.totalSupply(),
            "invariant T2: The Grant Fund's treasury should always be less than or equal to the Ajna token total supply"
        );
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
        console.log("Slate Update Hap:           ", _standardHandler.numberOfCalls('SFH.updateSlate.HAP'));
        console.log("Slate Update Happy:         ", _standardHandler.numberOfCalls('SFH.updateSlate.HAPPY'));
        console.log("Slate Update Prep:          ", _standardHandler.numberOfCalls('SFH.updateSlate.prep'));
        console.log("Slate Update length:        ", _standardHandler.numberOfCalls('updateSlate.length'));
        console.log("Slate Update Called:        ", _standardHandler.numberOfCalls('SFH.updateSlate.called'));
        console.log("Slate Update Success:       ", _standardHandler.numberOfCalls('SFH.updateSlate.success'));
        console.log("Slate Update Top ten length ", _standardHandler.numberOfCalls('SFH.updateSlate.TopTenLen'));
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
