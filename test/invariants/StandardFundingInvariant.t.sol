// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";

import { TestBase } from "./TestBase.sol";
import { StandardFundingHandler } from "./StandardFundingHandler.sol";

contract StandardFundingInvariant is TestBase {

    uint256 internal constant NUM_ACTORS = 20;

    StandardFundingHandler internal _standardFundingHandler;

    function setUp() public override {
        super.setUp();

        // TODO: modify this setup to enable use of random tokens not in treasury
        // calculate the number of tokens not in the treasury, to be distributed to actors
        uint256 tokensNotInTreasury = _token.balanceOf(_tokenDeployer) - treasury;

        _standardFundingHandler = new StandardFundingHandler(
            payable(address(_grantFund)),
            address(_token),
            _tokenDeployer,
            NUM_ACTORS,
            tokensNotInTreasury
        );

        // get the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = _standardFundingHandler.startNewDistributionPeriod.selector;
        selectors[1] = _standardFundingHandler.proposeStandard.selector;
        selectors[2] = _standardFundingHandler.screeningVoteMulti.selector;
        selectors[3] = _standardFundingHandler.fundingVotesMulti.selector;
        selectors[4] = _standardFundingHandler.checkSlate.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardFundingHandler),
            selectors: selectors
        }));

        // explicitly target handler
        targetContract(address(_standardFundingHandler));

        // skip time for snapshots and start distribution period
        vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);
        _grantFund.startNewDistributionPeriod();

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

            uint256 votingPower = _grantFund.getVotesWithParams(actor, block.number, bytes("Screening"));

            // TODO: expand this assertion
            // invariant SS2: can only vote up to the amount of voting power at the snapshot blocks
            assertTrue(_standardFundingHandler.sumVoterScreeningVotes(actor) <= votingPower);

            uint256[] memory votingActorScreeningVotes = _standardFundingHandler.votingActorScreeningVotes(actor);
            uint256[] memory votingActorScreeningProposalIds = _standardFundingHandler.votingActorScreeningProposalIds(actor);

            for (uint256 j = 0; j < votingActorScreeningVotes.length; ++j) {
                // invariant can only cast positive votes
                assertTrue(votingActorScreeningVotes[j] > 0);

                // check voter only votes upon proposals that they have submitted
                assertTrue(_findProposalIndex(votingActorScreeningProposalIds[j], _standardFundingHandler.getStandardFundingProposals()) != -1);
            }
        }
    }

    function invariant_FS1_FS2() public {
        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);

        // invariant FS1: only proposals in the top ten list should be able to recieve funding votes
        for (uint256 j = 0; j < _standardFundingHandler.standardFundingProposalCount(); ++j) {
            uint256 proposalId = _standardFundingHandler.standardFundingProposals(j);
            (, uint24 distributionId, , , int128 fundingVotesReceived, ) = _grantFund.getProposalInfo(proposalId);
            if (_findProposalIndex(proposalId, topTenProposals) == -1) {
                assertEq(fundingVotesReceived, 0);
            }
            // invariant FS2: distribution id for a proposal should be the same as the current distribution id
            assertEq(distributionId, _grantFund.getDistributionId());
        }
    }

    function invariant_call_summary() external view {
        console.log("\nCall Summary\n");
        console.log("--SFM----------");
        console.log("SFH.startNewDistributionPeriod ",  _standardFundingHandler.numberOfCalls("SFH.startNewDistributionPeriod"));
        console.log("SFH.proposeStandard            ",  _standardFundingHandler.numberOfCalls("SFH.proposeStandard"));
        console.log("SFH.screeningVoteMulti         ",  _standardFundingHandler.numberOfCalls("SFH.screeningVoteMulti"));
        console.log("SFH.fundingVotesMulti          ",  _standardFundingHandler.numberOfCalls("SFH.fundingVotesMulti"));
        console.log("SFH.checkSlate                 ",  _standardFundingHandler.numberOfCalls("SFH.checkSlate"));
        console.log("------------------");
        console.log(
            "Total Calls:",
            _standardFundingHandler.numberOfCalls("SFH.startNewDistributionPeriod") +
            _standardFundingHandler.numberOfCalls("SFH.proposeStandard") +
            _standardFundingHandler.numberOfCalls("SFH.screeningVoteMulti") +
            _standardFundingHandler.numberOfCalls("SFH.fundingVotesMulti") +
            _standardFundingHandler.numberOfCalls("SFH.checkSlate")
        );
        console.log(" ");
        console.log("--Proposal Stats--");
        console.log("Number of Proposals", _standardFundingHandler.standardFundingProposalCount());
        console.log("------------------");
        // sum proposal votes of each actor
        for (uint256 i = 0; i < _standardFundingHandler.getActorsCount(); ++i) {
            address actor = _standardFundingHandler.actors(i);
            console.log("Actor: ", actor);
            console.log("Delegate: ", _token.delegates(actor));
            console.log("Screening Voting Power: ", _grantFund.getVotesWithParams(actor, block.number, bytes("Screening")));
            console.log("Screening Votes Cast:   ", _standardFundingHandler.sumVoterScreeningVotes(actor));
            console.log("Screening proposals voted for:   ", _standardFundingHandler.numVotingActorScreeningVotes(actor));

            // console.log("Funding Voting Power:   ", _grantFund.getVotesWithParams(actor, block.number, bytes("Funding")));
            console.log("Funding Votes Cast:     ", uint256(_standardFundingHandler.sumVoterFundingVotes(actor)));
            console.log("------------------");
        }
        console.log("------------------");
        console.log("Number of Actors", _standardFundingHandler.getActorsCount());
        console.log("number of funding stage starts       ", _standardFundingHandler.numberOfCalls("SFH.FundingStage"));
        console.log("number of funding stage success votes", _standardFundingHandler.numberOfCalls("SFH.fundingVotesMulti.success"));
        console.log("distributionId", _grantFund.getDistributionId());
        console.log("SFH.checkSlate.success", _standardFundingHandler.numberOfCalls("SFH.checkSlate.success"));
    }

}
