// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";
import { Math }     from "@oz/utils/math/Math.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { GrantFund }  from "../../../src/grants/GrantFund.sol";
import { IGrantFund } from "../../../src/grants/interfaces/IGrantFund.sol";
import { Maths }      from "../../../src/grants/libraries/Maths.sol";

import { TestBase }        from "./TestBase.sol";
import { StandardHandler } from "../handlers/StandardHandler.sol";

abstract contract DistributionPeriodInvariants is TestBase {

    function _invariant_DP1_DP2_DP3_DP4_DP5(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        uint24 distributionId = grantFund_.getDistributionId();
        (
            ,
            uint256 startBlockCurrent,
            uint256 endBlockCurrent,
            ,
            ,
        ) = grantFund_.getDistributionPeriodInfo(distributionId);

        uint256 totalFundsAvailable = 0;

        uint24 i = distributionId;
        while (i > 0) {
            (
                ,
                uint256 startBlockPrev,
                uint256 endBlockPrev,
                uint128 fundsAvailablePrev,
                ,
            ) = grantFund_.getDistributionPeriodInfo(i);
            StandardHandler.DistributionState memory state = standardHandler_.getDistributionState(i);

            totalFundsAvailable += fundsAvailablePrev;
            require(
                totalFundsAvailable < state.treasuryBeforeStart,
                "invariant DP5: The treasury balance should be greater than the sum of the funds available in all distribution periods"
            );

            require(
                fundsAvailablePrev == Maths.wmul(.03 * 1e18, state.treasuryAtStartBlock + fundsAvailablePrev),
                "invariant DP3: A distribution's fundsAvailablePrev should be equal to 3% of the treasury's balance at the block `startNewDistributionPeriod()` is called"
            );

            require(
                endBlockPrev > startBlockPrev,
                "invariant DP4: A distribution's endBlock should be greater than its startBlock"
            );

            // check invariant DP5
            // seperate function avoids stack too deep error
            _invariant_DP5(_grantFund, state, i, fundsAvailablePrev);

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

    function _invariant_DP5(GrantFund grantFund_, StandardHandler.DistributionState memory state, uint256 distributionId_, uint256 fundsAvailablePrev_) internal {
        uint256 totalTokensRequestedByProposals = 0;

        // check the top funded proposal slate
        uint256[] memory proposalSlate = grantFund_.getFundedProposalSlate(state.currentTopSlate);
        for (uint j = 0; j < proposalSlate.length; ++j) {
            (
                ,
                uint24 proposalDistributionId,
                ,
                uint128 tokensRequested,
                ,
                bool executed
            ) = grantFund_.getProposalInfo(proposalSlate[j]);
            assertEq(proposalDistributionId, distributionId_);

            if (executed) {
                require(
                    tokensRequested < fundsAvailablePrev_,
                    "invariant DP2: Each winning proposal successfully claims no more that what was finalized in the challenge stage"
                );
            }
            totalTokensRequestedByProposals += tokensRequested;
        }
        assertTrue(totalTokensRequestedByProposals <= fundsAvailablePrev_);
    }

    function _invariant_DP6(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        uint24 distributionId = grantFund_.getDistributionId();

        for (uint24 i = 1; i <= distributionId; ) {
            (
                ,
                ,
                ,
                uint128 fundsAvailable,
                ,
            ) = grantFund_.getDistributionPeriodInfo(i);
            StandardHandler.DistributionState memory state = standardHandler_.getDistributionState(i);

            // check prior distributions for surplus to return to treasury
            uint24 prevDistributionId = i - 1;
            (
                ,
                ,
                ,
                uint128 fundsAvailablePrev,
                ,
                bytes32 topSlateHashPrev
            ) = grantFund_.getDistributionPeriodInfo(prevDistributionId);

            // calculate the expected treasury amount at the start of the current distribution period <i>
            uint256 expectedTreasury = state.treasuryBeforeStart;
            uint256 surplus = standardHandler_.updateTreasury(prevDistributionId, fundsAvailablePrev, topSlateHashPrev);
            expectedTreasury += surplus;

            require(
                fundsAvailable == Maths.wmul(.03 * 1e18, expectedTreasury),
                "invariant DP6: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury"
            );

            ++i;
        }
    }

    function _invariant_T1_T2(GrantFund grantFund_, StandardHandler standardHandler_) internal view {
        require(
            grantFund_.treasury() <= _ajna.balanceOf(address(grantFund_)),
            "invariant T1: The Grant Fund's treasury should always be less than or equal to the contract's token blance"
        );

        require(
            grantFund_.treasury() <= _ajna.totalSupply(),
            "invariant T2: The Grant Fund's treasury should always be less than or equal to the Ajna token total supply"
        );
    }

}
