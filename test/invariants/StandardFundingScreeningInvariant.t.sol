// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { StandardFundingTestBase } from "./base/StandardFundingTestBase.sol";
import { StandardFundingHandler } from "./handlers/StandardFundingHandler.sol";

contract StandardFundingScreeningInvariant is StandardFundingTestBase {

    function setUp() public override {
        super.setUp();

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _standardFundingHandler.startNewDistributionPeriod.selector;
        selectors[1] = _standardFundingHandler.proposeStandard.selector;
        selectors[2] = _standardFundingHandler.screeningVote.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardFundingHandler),
            selectors: selectors
        }));

    }

    function invariant_SS1_SS3_SS4_SS5() public {
        uint256 actorCount = _standardFundingHandler.getActorsCount();

        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);

        if (_standardFundingHandler.screeningVotesCast() > 0) {
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

        uint256 standardFundingProposalsSubmitted = _standardFundingHandler.standardFundingProposalCount();

        // check invariants against all submitted proposals
        for (uint256 j = 0; j < standardFundingProposalsSubmitted; ++j) {
            (, , uint256 votesReceived, , , ) = _grantFund.getProposalInfo(_standardFundingHandler.standardFundingProposals(j));
            // invariant SS4: votes recieved for a proposal can only be positive
            assertTrue(votesReceived >= 0);
        }

        // not all proposals submitted by actors will make it through the screening stage
        assertTrue(standardFundingProposalsSubmitted >= topTenProposals.length);
    }

    function invariant_SS2() public {
        uint256 actorCount = _standardFundingHandler.getActorsCount();

        for (uint256 i = 0; i < actorCount; ++i) {
            address actor = _standardFundingHandler.actors(i);

            uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), actor);

            // TODO: expand this assertion
            // invariant SS2: can only vote up to the amount of voting power at the snapshot blocks
            assertTrue(_standardFundingHandler.sumVoterScreeningVotes(actor) <= votingPower);

            ( , IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams) = _standardFundingHandler.getVotingActorsInfo(actor);

            for (uint256 j = 0; j < screeningVoteParams.length; ++j) {
                // invariant: can only cast positive votes
                assertTrue(screeningVoteParams[j].votes > 0);

                // check voter only votes upon proposals that they have submitted
                assertTrue(_findProposalIndex(screeningVoteParams[j].proposalId, _standardFundingHandler.getStandardFundingProposals()) != -1);
            }
        }
    }

    function invariant_call_summary() external view {
        console.log("\nCall Summary\n");
        console.log("--SFM----------");
        console.log("SFH.startNewDistributionPeriod ",  _standardFundingHandler.numberOfCalls("SFH.startNewDistributionPeriod"));
        console.log("SFH.proposeStandard            ",  _standardFundingHandler.numberOfCalls("SFH.proposeStandard"));
        console.log("SFH.screeningVote              ",  _standardFundingHandler.numberOfCalls("SFH.screeningVote"));
        console.log("SFH.fundingVote                ",  _standardFundingHandler.numberOfCalls("SFH.fundingVote"));
        console.log("SFH.updateSlate                ",  _standardFundingHandler.numberOfCalls("SFH.updateSlate"));
        console.log("------------------");
        console.log(
            "Total Calls:",
            _standardFundingHandler.numberOfCalls("SFH.startNewDistributionPeriod") +
            _standardFundingHandler.numberOfCalls("SFH.proposeStandard") +
            _standardFundingHandler.numberOfCalls("SFH.screeningVote") +
            _standardFundingHandler.numberOfCalls("SFH.fundingVote") +
            _standardFundingHandler.numberOfCalls("SFH.updateSlate")
        );
        console.log(" ");
        console.log("--Proposal Stats--");
        console.log("Number of Proposals", _standardFundingHandler.standardFundingProposalCount());
        console.log("------------------");

        uint24 distributionId = _grantFund.getDistributionId();

        // sum proposal votes of each actor
        for (uint256 i = 0; i < _standardFundingHandler.getActorsCount(); ++i) {
            address actor = _standardFundingHandler.actors(i);
            // get actor info
            (
                IStandardFunding.FundingVoteParams[] memory fundingVoteParams,
                IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams
            ) = _standardFundingHandler.getVotingActorsInfo(actor);

            console.log("Actor: ", actor);
            console.log("Delegate: ", _token.delegates(actor));
            console.log("Screening Voting Power: ", _grantFund.getVotesScreening(distributionId, actor));
            console.log("Screening Votes Cast:   ", _standardFundingHandler.sumVoterScreeningVotes(actor));
            console.log("Screening proposals voted for:   ", screeningVoteParams.length);
            console.log("------------------");
        }
    }

}
