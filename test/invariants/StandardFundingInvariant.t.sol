// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TestBase } from "./TestBase.sol";
import { StandardFundingHandler } from "./StandardFundingHandler.sol";

contract StandardFundingInvariant is TestBase {

    uint256 internal constant NUM_ACTORS = 50;

    StandardFundingHandler internal _standardFundingHandler;

    function setUp() public override virtual{
        super.setUp();

        // calculate the number of tokens not in the treasury, to be distributed to actors
        uint256 tokensNotInTreasury = _token.balanceOf(_tokenDeployer) - treasury;

        _standardFundingHandler = new StandardFundingHandler(
            payable(address(_grantFund)),
            address(_token),
            _tokenDeployer,
            NUM_ACTORS,
            tokensNotInTreasury
        );

        // TODO: Change once this issue is resolved -> https://github.com/foundry-rs/foundry/issues/2963
        targetSender(address(0x1234));
    }

    function invariant_SS1_SS3_SS4_SS5() public {
        uint256 actorCount = _standardFundingHandler.getActorsCount();

        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);

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

        uint256 standardFundingProposalsSubmitted = _standardFundingHandler.getStandardFundingProposalsLength();

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

            uint256 votingPower = _standardFundingHandler.getVotes(actor);
            // TODO: expand this assertion
            // invariant SS2: can only vote up to the amount of voting power at the snapshot blocks
            assertTrue(_standardFundingHandler.sumVoterScreeningVotes(actor) <= votingPower);

            for (uint256 j = 0; j < _standardFundingHandler.numVotingActorScreeningVotes(actor); ++j) {
                (, uint256 screeningVotes, , uint256 proposalId) = _standardFundingHandler.getVotingActorsInfo(actor, j);
                // invariant can only cast positive votes
                assertTrue(screeningVotes > 0);

                // check voter only votes upon proposals that they have submitted
                assertTrue(_standardFundingHandler.findProposalIndex(proposalId, _standardFundingHandler.getStandardFundingProposals()) != -1);
            }
        }
    }

    function invariant_FS1_FS2() public {
        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);

        // invariant FS1: only proposals in the top ten list should be able to recieve funding votes
        for (uint256 j = 0; j < _standardFundingHandler.getStandardFundingProposalsLength(); ++j) {
            uint256 proposalId = _standardFundingHandler.standardFundingProposals(j);
            (, uint24 distributionId, , , int128 fundingVotesReceived, ) = _grantFund.getProposalInfo(proposalId);
            if (_standardFundingHandler.findProposalIndex(proposalId, topTenProposals) == -1) {
                assertEq(fundingVotesReceived, 0);
            }
            // invariant FS2: distribution id for a proposal should be the same as the current distribution id
            assertEq(distributionId, _grantFund.getDistributionId());
        }
    }

}
