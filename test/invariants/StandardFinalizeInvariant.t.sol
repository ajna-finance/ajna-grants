// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";
import { Math } from "@oz/utils/math/Math.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IGrantFund } from "../../src/grants/interfaces/IGrantFund.sol";
import { Maths }      from "../../src/grants/libraries/Maths.sol";

import { StandardTestBase } from "./base/StandardTestBase.sol";
import { StandardHandler }  from "./handlers/StandardHandler.sol";
import { Handler }          from "./handlers/Handler.sol";

contract StandardFinalizeInvariant is StandardTestBase {

    struct LocalVotersInfo {
        uint128 fundingVotingPower;
        uint128 fundingRemainingVotingPower;
        uint256 votesCast;
    }

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
    }

    function invariant_CS1_CS2_CS3_CS4_CS5_CS6() view external {
        uint24 distributionId = _grantFund.getDistributionId();

        (, , uint256 endBlock, uint128 fundsAvailable, , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId);

        uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

        uint256[] memory topTenScreenedProposalIds = _grantFund.getTopTenProposals(distributionId);

        require(
            topSlateProposalIds.length <= 10,
            "invariant CS2: top slate should have 10 or less proposals"
        );

        // check proposal state of the constituents of the top slate
        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < topSlateProposalIds.length; ++i) {
            uint256 proposalId = topSlateProposalIds[i];
            (, , , uint128 tokensRequested, int128 fundingVotesReceived, ) = _grantFund.getProposalInfo(proposalId);
            totalTokensRequested += tokensRequested;

            require(
                fundingVotesReceived >= 0,
                "invariant CS3: Proposal slate should never contain a proposal with negative funding votes received"
            );

            require(
                _findProposalIndex(proposalId, topTenScreenedProposalIds) != -1,
                "invariant CS4: Proposal slate should never contain a proposal that wasn't in the top ten in the funding stage."
            );
        }

        require(
            totalTokensRequested <= uint256(fundsAvailable) * 9 / 10,
            "invariant CS1: total tokens requested should be <= 90% of fundsAvailable"
        );

        require(
            !_standardHandler.hasDuplicates(topSlateProposalIds),
            "invariant CS5: proposal slate should never contain duplicate proposals"
        );

        // check DistributionState for top slate updates
        StandardHandler.DistributionState memory state = _standardHandler.getDistributionState(distributionId);
        for (uint i = 0; i < state.topSlates.length; ++i) {
            StandardHandler.Slate memory slate = state.topSlates[i];

            require(
                slate.updateBlock <= endBlock && slate.updateBlock >= _grantFund.getChallengeStageStartBlock(endBlock),
                "invariant CS6: Funded proposal slate's can only be updated during a distribution period's challenge stage"
            );
        }
    }

    function invariant_ES1_ES2_ES3_ES4_ES5() external {
        uint24 distributionId = _grantFund.getDistributionId();
        while (distributionId > 0) {
            (, , , uint256 gbc, , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId);

            uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

            // calculate the total tokens requested by the proposals in the top slate
            uint256 totalTokensRequested = 0;
            for (uint256 i = 0; i < topSlateProposalIds.length; ++i) {
                uint256 proposalId = topSlateProposalIds[i];
                (, , , uint128 tokensRequested, , ) = _grantFund.getProposalInfo(proposalId);
                totalTokensRequested += tokensRequested;
            }

            uint256[] memory standardFundingProposals = _standardHandler.getStandardFundingProposals(distributionId);
            uint256[] memory topTenScreenedProposalIds = _grantFund.getTopTenProposals(distributionId);

            // check the state of every proposal submitted in this distribution period
            for (uint256 i = 0; i < standardFundingProposals.length; ++i) {
                uint256 proposalId = standardFundingProposals[i];
                (, uint24 proposalDistributionId, , uint256 tokenRequested, , bool executed) = _grantFund.getProposalInfo(proposalId);
                int256 proposalIndex = _findProposalIndex(proposalId, topSlateProposalIds);
                // invariant ES1: A proposal can only be executed if it's listed in the final funded proposal slate at the end of the challenge round.
                if (proposalIndex == -1) {
                    assertFalse(executed);
                }

                // invariant ES2: A proposal can only be executed after the challenge stage is complete.
                assertEq(distributionId, proposalDistributionId);
                if (executed) {
                    (, , uint48 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(proposalDistributionId);
                    // TODO: store and check proposal execution time
                    require(
                        currentBlock > endBlock,
                        "invariant ES2: A proposal can only be executed after the challenge stage is complete."
                    );

                    // check if proposalId exist in topTenScreenedProposals if it is executed
                    require(
                        _findProposalIndex(proposalId, topTenScreenedProposalIds) != -1,
                        "invariant ES4: A proposal can only be executed if it was in the top ten screened proposals at the end of the screening stage."
                    );

                    require(
                        tokenRequested <= gbc * 9 / 10,
                        "invariant ES5: An executed proposal should only ever transfer tokens <= 90% of GBC"
                    );

                }
            }

            require(
                !_standardHandler.hasDuplicates(_standardHandler.getProposalsExecuted()),
                "invariant ES3: A proposal can only be executed once."
            );

            --distributionId;
        }
    }

    function invariant_DR1_DR2_DR3_DR4_DR5() external {
        uint24 distributionId = _grantFund.getDistributionId();
        while (distributionId > 0) {
            (, , uint256 distributionEndBlock, uint128 fundsAvailable, uint256 fundingVotePowerCast, ) = _grantFund.getDistributionPeriodInfo(distributionId);

            uint256 totalRewardsClaimed;

            for (uint256 i = 0; i < _standardHandler.getActorsCount(); ++i) {
                address actor = _standardHandler.actors(i);

                // get the initial funding stage voting power of the actor
                LocalVotersInfo memory votersInfo;
               (votersInfo.fundingVotingPower, votersInfo.fundingRemainingVotingPower, ) = _grantFund.getVoterInfo(distributionId, actor);

                // get actor info from standard handler
                (
                    IGrantFund.FundingVoteParams[] memory fundingVoteParams,
                    IGrantFund.ScreeningVoteParams[] memory screeningVoteParams,
                    uint256 delegationRewardsClaimed
                ) = _standardHandler.getVotingActorsInfo(actor, distributionId);

                totalRewardsClaimed += delegationRewardsClaimed;

                if (delegationRewardsClaimed != 0) {
                    // check that delegation rewards are greater tahn 0 if they did vote in both stages
                    assertTrue(delegationRewardsClaimed >= 0);

                    uint256 votingPowerAllocatedByDelegatee = votersInfo.fundingVotingPower - votersInfo.fundingRemainingVotingPower;
                    uint256 rootVotingPowerAllocatedByDelegatee = Math.sqrt(votingPowerAllocatedByDelegatee * 1e18);

                    require(
                        fundingVoteParams.length > 0 && screeningVoteParams.length > 0,
                        "invariant DR2: Delegation rewards are 0 if voter didn't vote in both stages."
                    );

                    uint256 rewards;
                    if (votingPowerAllocatedByDelegatee > 0) {
                        rewards = Math.mulDiv(
                            fundsAvailable,
                            rootVotingPowerAllocatedByDelegatee,
                            10 * fundingVotePowerCast
                        );
                    }

                    require(
                        delegationRewardsClaimed == rewards,
                        "invariant DR3: Delegation rewards are proportional to voters funding power allocated in the funding stage."
                    );

                    if (distributionEndBlock >= block.timestamp) {
                        require(
                            _grantFund.getHasClaimedRewards(distributionId, actor) == false,
                            "invariant DR4: Delegation rewards can only be claimed for a distribution period after it ended"
                        );
                    }
                }
            }

            require(
                totalRewardsClaimed <= fundsAvailable * 1 / 10,
                "invariant DR1: Cumulative delegation rewards should be <= 10% of a distribution periods GBC"
            );

            // check state after all possible delegation rewards have been claimed
            if (_standardHandler.numberOfCalls('SFH.claimDelegateReward.success') == _standardHandler.getActorsCount()) {
                require(
                    totalRewardsClaimed >= Maths.wmul(fundsAvailable * 1 / 10, 0.9999 * 1e18),
                    "invariant DR5: Cumulative rewards claimed should be within 99.99% -or- 0.01 AJNA tokens of all available delegation rewards"
                );
                assertEq(totalRewardsClaimed, fundsAvailable * 1 / 10);
            }

            --distributionId;
        }
    }

    function invariant_call_summary() external view {
        uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        _standardHandler.logActorSummary(distributionId, false, false);
        _standardHandler.logProposalSummary();
        _standardHandler.logTimeSummary();
        _logFinalizeSummary(distributionId);
    }

    function _logFinalizeSummary(uint24 distributionId_) internal view {
        (, , , uint128 fundsAvailable, , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId_);
        uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

        uint256[] memory topTenScreenedProposalIds = _grantFund.getTopTenProposals(distributionId_);

        console.log("\nFinalize Summary\n");
        console.log("------------------");
        console.log("Distribution Id:            ", distributionId_);
        console.log("Delegation Rewards Claimed: ", _standardHandler.numberOfCalls('SFH.claimDelegateReward.success'));
        console.log("Proposal Execute attempt:   ", _standardHandler.numberOfCalls('SFH.execute.attempt'));
        console.log("Proposal Execute Count:     ", _standardHandler.numberOfCalls('SFH.execute.success'));
        console.log("Slate Created:              ", _standardHandler.numberOfCalls('SFH.updateSlate.prep'));
        console.log("Slate Update Called:        ", _standardHandler.numberOfCalls('SFH.updateSlate.called'));
        console.log("Slate Update Count:         ", _standardHandler.numberOfCalls('SFH.updateSlate.success'));
        console.log("Next Slate length:          ", _standardHandler.numberOfCalls('updateSlate.length'));
        console.log("Top Slate Proposal Count:   ", topSlateProposalIds.length);
        console.log("Top Ten Proposal Count:     ", topTenScreenedProposalIds.length);
        console.log("Funds Available:            ", fundsAvailable);
        console.log("Top slate funds requested:  ", _standardHandler.getTokensRequestedInFundedSlateInvariant(topSlateHash));
        (, , , , uint256 fundingPowerCast, ) = _grantFund.getDistributionPeriodInfo(distributionId_);
        console.log("Total Funding Power Cast    ", fundingPowerCast);
        console.log("------------------");
    }

}
