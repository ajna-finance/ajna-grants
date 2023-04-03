// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { StandardTestBase } from "./base/StandardTestBase.sol";
import { StandardHandler } from "./handlers/StandardHandler.sol";

contract StandardScreeningInvariant is StandardTestBase {

    function setUp() public override {
        super.setUp();

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _standardHandler.startNewDistributionPeriod.selector;
        selectors[1] = _standardHandler.proposeStandard.selector;
        selectors[2] = _standardHandler.screeningVote.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardHandler),
            selectors: selectors
        }));

    }

    function invariant_SS1_SS3_SS4_SS5_SS6_SS7() public {
        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant SS1: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);
        assertTrue(standardFundingProposalsSubmitted >= topTenProposals.length);

        if (_standardHandler.screeningVotesCast() > 0) {
            assertTrue(topTenProposals.length > 0);
        }

        if (topTenProposals.length > 1) {
            for (uint256 i = 0; i < topTenProposals.length - 1; ++i) {
                // invariant SS3: proposals should be sorted in descending order
                (, uint24 distributionIdCurr, uint256 votesReceivedCurr, , , ) = _grantFund.getProposalInfo(topTenProposals[i]);
                (, uint24 distributionIdNext, uint256 votesReceivedNext, , , ) = _grantFund.getProposalInfo(topTenProposals[i + 1]);
                assertTrue(votesReceivedCurr >= votesReceivedNext);

                // invariant SS4: votes recieved for a proposal can only be positive
                // only proposals that recieve votes will make it into the top ten list
                assertTrue(votesReceivedCurr > 0);
                assertTrue(votesReceivedNext > 0);

                // invariant SS5: distribution id for a proposal should be the same as the current distribution id
                assertTrue(distributionIdCurr == distributionIdNext && distributionIdCurr == _grantFund.getDistributionId());
            }
        }

        uint256 standardFundingProposalsSubmitted = _standardHandler.standardFundingProposalCount();

        // find the number of screening votes received by the last proposal in the top ten list
        uint256 votesReceivedLast;
        if (topTenProposals.length != 0) {
            (, , votesReceivedLast, , , ) = _grantFund.getProposalInfo(topTenProposals[topTenProposals.length - 1]);
            assertGt(votesReceivedLast, 0);
        }

        // check invariants against all submitted proposals
        for (uint256 j = 0; j < standardFundingProposalsSubmitted; ++j) {
            (, , uint256 votesReceived, , , ) = _grantFund.getProposalInfo(_standardHandler.standardFundingProposals(j));
            // invariant SS4: votes recieved for a proposal can only be positive
            assertTrue(votesReceived >= 0);

            // invariant SS7: a proposal should never receive more votes than the token supply.
            assertTrue(votesReceived <= _token.totalSupply());

            // invariant SS6: For every proposal, it is included in the top 10 list if, and only if, it has as many or more votes as the last member of the top ten list.
            // if the proposal is not in the top ten list, then it should have received less screening votes than the last in the top 10
            if (_findProposalIndex(_standardHandler.standardFundingProposals(j), topTenProposals) == -1) {
                if (votesReceivedLast != 0) {
                    // assertTrue(votesReceived < votesReceivedLast);
                    assertGt(votesReceivedLast, votesReceived);
                }
            }
        }
    }

    function invariant_SS2_SS4() public {
        uint256 actorCount = _standardHandler.getActorsCount();
        uint24 distributionId = _grantFund.getDistributionId();

        // check invariants for all actors
        for (uint256 i = 0; i < actorCount; ++i) {
            address actor = _standardHandler.actors(i);

            uint256 votingPower = _grantFund.getVotesScreening(distributionId, actor);

            // invariant SS2: can only vote up to the amount of voting power at the snapshot blocks
            assertTrue(_standardHandler.sumVoterScreeningVotes(actor, distributionId) <= votingPower);

            ( , IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams, ) = _standardHandler.getVotingActorsInfo(actor, distributionId);

            for (uint256 j = 0; j < screeningVoteParams.length; ++j) {
                // invariant SS4: can only cast positive votes
                assertTrue(screeningVoteParams[j].votes > 0);

                // check voter only votes upon proposals that they have submitted
                assertTrue(_findProposalIndex(screeningVoteParams[j].proposalId, _standardHandler.getStandardFundingProposals()) != -1);
            }
        }
    }

    function invariant_call_summary() external view {
        uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        _standardHandler.logProposalSummary();
        _standardHandler.logActorSummary(distributionId, false, true);
    }

}
