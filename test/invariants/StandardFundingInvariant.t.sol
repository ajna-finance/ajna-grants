// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { StandardTestBase } from "./base/StandardTestBase.sol";
import { StandardHandler } from "./handlers/StandardHandler.sol";

contract StandardFundingInvariant is StandardTestBase {

    // TODO: override the number of voting actors
    // override setup to start tests in the funding stage with already screened proposals
    function setUp() public override {
        super.setUp();

        // create 15 proposals
        _standardHandler.createProposals(15);

        // cast screening votes on proposals
        _standardHandler.screeningVoteProposals();

        // skip time into the funding stage
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        uint256 fundingStageStartBlock = endBlock - 72000;
        vm.roll(fundingStageStartBlock + 100);

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = _standardHandler.fundingVote.selector;
        selectors[1] = _standardHandler.updateSlate.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardHandler),
            selectors: selectors
        }));
    }

    function invariant_FS1_FS2_FS3() external {
        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);
        assertTrue(topTenProposals.length > 0); // check if something went wrong in setup

        // invariant FS1: only proposals in the top ten list should be able to recieve funding votes
        for (uint256 j = 0; j < _standardHandler.standardFundingProposalCount(); ++j) {
            uint256 proposalId = _standardHandler.standardFundingProposals(j);
            (, uint24 distributionId, , , int128 fundingVotesReceived, ) = _grantFund.getProposalInfo(proposalId);

            // invariant FS5: proposals not in the top ten should not be able to recieve funding votes
            if (_findProposalIndex(proposalId, topTenProposals) == -1) {
                assertEq(fundingVotesReceived, 0);
            }
            // invariant FS2: distribution id for a proposal should be the same as the current distribution id
            assertEq(distributionId, _grantFund.getDistributionId());
        }
    }

    function invariant_FS4_FS8() external {
        for (uint256 i = 0; i < _standardHandler.getActorsCount(); ++i) {
            address actor = _standardHandler.actors(i);

            uint24 distributionId = _grantFund.getDistributionId();

            // get the initial funding stage voting power of the actor
            (uint128 votingPower, uint128 remainingVotingPower, uint256 numberOfProposalsVotedOn) = _grantFund.getVoterInfo(distributionId, actor);

            // get the voting info of the actor
            (IStandardFunding.FundingVoteParams[] memory fundingVoteParams, ) = _standardHandler.getVotingActorsInfo(actor);

            uint128 sumOfSquares = SafeCast.toUint128(_standardHandler.sumSquareOfVotesCast(fundingVoteParams));

            // check voter votes cast are less than or equal to the sqrt of the voting power of the actor
            IStandardFunding.FundingVoteParams[] memory fundingVotesCast = _grantFund.getFundingVotesCast(distributionId, actor);

            // invariant FS4: sum of square of votes cast <= voting power of actor
            assertTrue(sumOfSquares <= votingPower);

            if (votingPower != 0 && remainingVotingPower == 0) {
                assertTrue(numberOfProposalsVotedOn == fundingVotesCast.length);
                assertTrue(numberOfProposalsVotedOn > 0);
            }

            // invariant FS8: a voter should never be able to cast more votes than the Ajna token supply of 1 billion.
            assertTrue(uint256(_standardHandler.sumFundingVotes(fundingVoteParams)) <= 1_000_000_000 * 1e18);

            // TODO: check getFundingPowerVotes to see if remaining voting power matches expectations
            // assertEq(_grantFund.getFundingPowerVotes(uint256(votingPower - remainingVotingPower)), uint256(_standardHandler.sumFundingVotes(actor, fundingVoteParams)));
        }
    }

    function invariant_call_summary() external view {
        uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        _standardHandler.logProposalSummary();
        _standardHandler.logActorSummary(distributionId, true, false);
        _logFundingSummary(distributionId);
    }

    function _logFundingSummary(uint24 distributionId_) internal view {
        console.log("\nFunding Summary\n");
        console.log("------------------");
        console.log("number of funding stage starts:        ", _standardHandler.numberOfCalls("SFH.FundingStage"));
        console.log("number of funding stage success votes: ", _standardHandler.numberOfCalls("SFH.fundingVote.success"));
        console.log("distributionId:                        ", distributionId_);
        console.log("SFH.updateSlate.success:               ", _standardHandler.numberOfCalls("SFH.updateSlate.success"));
        console.log("------------------");
    }

}
