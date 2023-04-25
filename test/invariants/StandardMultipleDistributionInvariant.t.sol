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

    // TODO: add invariant specific to this test that the treasury never increases past the initial treasury value
    function xinvariant_DP1_DP2_DP3_DP4_DP5_DP6() external {
        uint24 distributionId = _grantFund.getDistributionId();
        console.log("distributionId??", distributionId);
        (
            ,
            uint256 startBlockCurrent,
            uint256 endBlockCurrent,
            uint128 fundsAvailableCurrent,
            ,
        ) = _grantFund.getDistributionPeriodInfo(distributionId);

        uint256 totalFundsAvailable = 0;
        // StandardHandler.DistributionState memory state = _standardHandler.getDistributionState(distributionId);
        // uint256 currentTreasury = state.treasuryBeforeStart;
        // uint256 currentTreasury = _grantFund.treasury();

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

            uint256[] memory topTenProposals = _grantFund.getTopTenProposals(i);
            uint256 totalTokensRequestedByProposals = 0;

            // // check each distribution period's top ten slate of proposals for executions and compare with distribution funds available
            // for (uint p = 0; p < topTenProposals.length; ++p) {
            //     // get proposal info
            //     (
            //         ,
            //         uint24 proposalDistributionId,
            //         ,
            //         uint128 tokensRequested,
            //         ,
            //         bool executed
            //     ) = _grantFund.getProposalInfo(topTenProposals[p]);
            //     assertEq(proposalDistributionId, i);

            //     if (executed) {
            //         // invariant DP2: Each winning proposal successfully claims no more that what was finalized in the challenge stage
            //         assertLt(tokensRequested, fundsAvailablePrev);
            //         assertTrue(totalTokensRequestedByProposals <= fundsAvailablePrev);
            //     }
            // }

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
                }
                totalTokensRequestedByProposals += tokensRequested;
            }
            assertTrue(totalTokensRequestedByProposals <= fundsAvailablePrev);

            // check invariants against each previous distribution periods
            if (i != distributionId) {
                // if new distribution started before end of distribution period then surplus won't be added automatically to the treasury.
                // only add the surplus if the distribution period started before the end of the prior challenge period
                uint256 surplus = 0;
                if (startBlockCurrent > endBlockPrev + 50400 && state.treasuryUpdated == false) {
                    // then the surplus should have been added to the treasury
                    console.log("add surplus to treasury?");
                    surplus = fundsAvailablePrev - totalTokensRequestedByProposals;
                    _standardHandler.setDistributionTreasuryUpdated(i);
                }

                // check if the prior distribution period hadn't had it's surplus returned to the treasury either
                if (i > 1) {
                    (
                        ,
                        ,
                        uint256 endBlockBeforePrev,
                        uint128 fundsAvailableBeforePrev,
                        ,
                        bytes32 topSlateHashBeforePrev
                    ) = _grantFund.getDistributionPeriodInfo(i - 1);
                    if (startBlockPrev < endBlockBeforePrev + 50400) {
                        // then the surplus should have been added to the treasury
                        console.log("before prev surplus", surplus);
                        // console.log("before prev surplus", fundsAvailableBeforePrev);
                        surplus += fundsAvailableBeforePrev - _standardHandler.getTokensRequestedInFundedSlateInvariant(topSlateHashBeforePrev);
                        console.log("after prev surplus ", surplus);
                        _standardHandler.setDistributionTreasuryUpdated(i - 1);
                    }
                }

                console.log("-----------------------");
                console.log("distribution period        ", i);
                console.log("surplus                    ", surplus);
                console.log("state.treasury before star ", state.treasuryBeforeStart);
                console.log("state.treasuryAtStartBlock ", state.treasuryAtStartBlock);
                console.log("current treasury           ", currentTreasury);
                console.log("funds available prev       ", fundsAvailablePrev);
                console.log("funds available current    ", fundsAvailableCurrent);
                // console.log("funds available expected   ", Maths.wmul(.03 * 1e18, surplus + state.treasuryAtStartBlock));
                // console.log("funds available expected   ", Maths.wmul(.03 * 1e18, surplus + currentTreasury));
                console.log("funds available expected   ", Maths.wmul(.03 * 1e18, currentTreasury));

                // FIXME: this breaks at high depth
                // require(
                //     fundsAvailableCurrent == Maths.wmul(.03 * 1e18, surplus + state.treasuryAtStartBlock),
                //     "invariant DP6: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury"
                // );
                // fundsAvailableCurrent = fundsAvailablePrev;

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

    function invariant_DP6() external {
        uint24 distributionId = _grantFund.getDistributionId();

        for (uint24 i = 0; i <= distributionId; ) {
            if (i == 0) {
                ++i;
                continue;
            }

            // uint256 tokensRequested = _standardHandler.getTokensRequestedInFundedSlateInvariant(topSlateHash);

            uint256 surplus = 0;
            // uint256 expectedTreasuryAfter = state.treasuryAtStartBlock;

            (
                ,
                ,
                uint256 endBlock,
                uint128 fundsAvailable,
                ,
            ) = _grantFund.getDistributionPeriodInfo(i);
            StandardHandler.DistributionState memory state = _standardHandler.getDistributionState(i);

            // uint24 prevDistributionId = i - 2;
            // check if the prior distribution period hadn't had it's surplus returned to the treasury either
            (
                ,
                ,
                uint256 endBlockPrev,
                uint128 fundsAvailablePrev,
                ,
                bytes32 topSlateHashPrev
            ) = _grantFund.getDistributionPeriodInfo(i - 1);

            StandardHandler.DistributionState memory prevState = _standardHandler.getDistributionState(i - 1);
            uint256 expectedTreasury = prevState.treasuryAtStartBlock;

            // console.log("start block                ", startBlock);
            console.log("start block                ", _standardHandler.getDistributionStartBlock(i));
            // console.log("end block prev             ", endBlockPrev);
            console.log("end block                  ", endBlockPrev);
            // console.log("funds available prev       ", fundsAvailablePrev);
            if (i > 1 && _standardHandler.getDistributionStartBlock(i) > endBlockPrev + 50400) {
                console.log("path 1");
                // then the surplus should have been added to the treasury
                // tokensRequested += _standardHandler.getTokensRequestedInFundedSlateInvariant(topSlateHashPrev);
                // console.log("funds available prev       ", fundsAvailablePrev);
                // console.log("tokens requested prev      ", _standardHandler.getTokensRequestedInFundedSlateInvariant(topSlateHashPrev));
                // surplus += fundsAvailablePrev - _standardHandler.getTokensRequestedInFundedSlateInvariant(topSlateHashPrev);
                // _standardHandler.setDistributionTreasuryUpdated(i - 1);
                surplus += _standardHandler.updateTreasury(i - 1, fundsAvailablePrev, topSlateHashPrev);
                // expectedTreasury += surplus;
                // expectedTreasury = state.treasuryAtStartBlock + surplus;
                // expectedTreasuryAfter += surplus;
            }

            if (i > 2 && prevState.treasuryUpdated == false) {
                (
                    ,
                    ,
                    uint256 endBlockBeforePrev,
                    uint128 fundsAvailableBeforePrev,
                    ,
                    bytes32 topSlateHashBeforePrev
                ) = _grantFund.getDistributionPeriodInfo(i - 2);
                console.log("path 2");
                surplus += _standardHandler.updateTreasury(i - 2, fundsAvailableBeforePrev, topSlateHashBeforePrev);
                // expectedTreasury += surplus;
                // expectedTreasury = state.treasuryAtStartBlock + surplus;
                // expectedTreasuryAfter += surplus;
            }

            expectedTreasury += surplus;

            console.log("distribution period        ", i);
            console.log("surplus                    ", surplus);
            console.log("state.treasury before star ", prevState.treasuryBeforeStart);
            console.log("state.treasuryAtStartBlock ", prevState.treasuryAtStartBlock);
            console.log("funds available            ", fundsAvailable);
            console.log("funds available expected   ", Maths.wmul(.03 * 1e18, expectedTreasury));
            // console.log("funds available expected   ", Maths.wmul(.03 * 1e18, expectedTreasuryAfter));
            console.log("-----------------------");

            if (i == 1) {
                require(
                    fundsAvailable == Maths.wmul(.03 * 1e18, state.treasuryBeforeStart),
                    "invariant DP6: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury"
                );
            }
            else {
                require(
                    fundsAvailable == Maths.wmul(.03 * 1e18, expectedTreasury),
                    "invariant DP6: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury"
                );
            }

            ++i;
        }
    }

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
        uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        _standardHandler.logTimeSummary();

        console.log("scenario type", uint8(_standardHandler.getCurrentScenarioType()));

        console.log("Delegation Rewards Claimed: ", _standardHandler.numberOfCalls('SFH.claimDelegateReward.success'));
        console.log("Proposal Execute Count:     ", _standardHandler.numberOfCalls('SFH.executeStandard.success'));
        console.log("Slate Update Called:        ", _standardHandler.numberOfCalls('SFH.updateSlate.called'));
        console.log("Slate Update Count:         ", _standardHandler.numberOfCalls('SFH.updateSlate.success'));
        // _standardHandler.logProposalSummary();
        // _standardHandler.logActorSummary(distributionId, true, true);

        console.log("current distributionId: %s", distributionId);
        // TODO: need to be able to log all the different type of summaries
        // _logFinalizeSummary(distributionId);
    }
}
