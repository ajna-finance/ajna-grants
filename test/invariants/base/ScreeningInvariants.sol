// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console } from "@std/console.sol";

import { GrantFund }        from "../../../src/grants/GrantFund.sol";
import { IGrantFund }       from "../../../src/grants/interfaces/IGrantFund.sol";

import { TestBase }        from "./TestBase.sol";
import { StandardHandler } from "../handlers/StandardHandler.sol";

abstract contract ScreeningInvariants is TestBase {

    /********************/
    /**** Invariants ****/
    /********************/

    function _invariant_SS1_SS3_SS4_SS5_SS6_SS7_SS9_SS10_SS11(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        // set block number to current block
        // TODO: find more elegant solution to block.number not being updated in time for the snapshot -> probably a modifier
        vm.roll(currentBlock);

        uint24 distributionId = grantFund_.getDistributionId();
        while (distributionId > 0) {

            uint256[] memory allProposals = standardHandler_.getStandardFundingProposals(distributionId);
            uint256 standardFundingProposalsSubmitted = allProposals.length;
            uint256[] memory topTenProposals = grantFund_.getTopTenProposals(distributionId);
            (, uint256 startBlock, , uint256 gbc, , ) = grantFund_.getDistributionPeriodInfo(distributionId);

            require(
                topTenProposals.length <= 10 && standardFundingProposalsSubmitted >= topTenProposals.length,
                "invariant SS1: 10 or less proposals should make it through the screening stage"
            );

            // check the state of the top ten proposals
            if (topTenProposals.length > 1) {
                for (uint256 i = 0; i < topTenProposals.length - 1; ++i) {
                    // check the current proposals votes received against the next proposal in the top ten list
                    (, uint24 distributionIdCurr, uint256 votesReceivedCurr, , , ) = grantFund_.getProposalInfo(topTenProposals[i]);
                    (, uint24 distributionIdNext, uint256 votesReceivedNext, , , ) = grantFund_.getProposalInfo(topTenProposals[i + 1]);
                    require(
                        votesReceivedCurr >= votesReceivedNext,
                        "invariant SS3: proposals should be sorted in descending order"
                    );

                    require(
                        votesReceivedCurr >= 0 && votesReceivedNext >= 0,
                        "invariant SS4: Screening votes recieved for a proposal can only be positive"
                    );

                    // TODO: improve this check
                    require(
                        distributionIdCurr == distributionIdNext && distributionIdCurr == distributionId,
                        "invariant SS5: distribution id for a proposal should be the same as the current distribution id"
                    );
                }
            }

            // find the number of screening votes received by the last proposal in the top ten list
            uint256 votesReceivedLast;
            if (topTenProposals.length != 0) {
                (, , votesReceivedLast, , , ) = grantFund_.getProposalInfo(topTenProposals[topTenProposals.length - 1]);
                assertGe(votesReceivedLast, 0);
            }

            // check invariants against all submitted proposals
            for (uint256 j = 0; j < standardFundingProposalsSubmitted; ++j) {
                (uint256 proposalId, , uint256 votesReceived, uint256 tokensRequested, , ) = grantFund_.getProposalInfo(standardHandler_.standardFundingProposals(distributionId, j));
                require(
                    votesReceived >= 0,
                    "invariant SS4: Screening votes recieved for a proposal can only be positive"
                );

                require(
                    votesReceived <= _ajna.totalSupply(),
                    "invariant SS7: a proposal should never receive more screening votes than the token supply"
                );

                // check each submitted proposals votes against the last proposal in the top ten list
                if (_findProposalIndex(proposalId, topTenProposals) == -1) {
                    if (votesReceivedLast != 0) {
                        require(
                            votesReceived <= votesReceivedLast,
                            "invariant SS6: proposals should be incorporated into the top ten list if, and only if, they have as many or more votes as the last member of the top ten list."
                        );
                    }
                }

                // TODO: account for multiple distribution periods?
                TestProposal memory testProposal = standardHandler_.getTestProposal(proposalId);
                require(
                    testProposal.blockAtCreation <= grantFund_.getScreeningStageEndBlock(startBlock),
                    "invariant SS9: A proposal can only be created during a distribution period's screening stage"
                );

                require(
                    tokensRequested <= gbc * 9 / 10, "invariant SS11: A proposal's tokens requested must be <= 90% of GBC"
                );
            }

            // check proposalIds for duplicates
            require(
                !hasDuplicates(allProposals), "invariant SS10: A proposal's proposalId must be unique"
            );

            // TODO: expand this assertion
            // invariant SS6: proposals should be incorporated into the top ten list if, and only if, they have as many or more votes as the last member of the top ten list.
            if (standardHandler_.screeningVotesCast() > 0) {
                assertTrue(topTenProposals.length > 0);
            }

            --distributionId;
        }
    }

    function _invariant_SS2_SS4_SS8(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        // set block number to current block
        // TODO: find more elegant solution to block.number not being updated in time for the snapshot -> probably a modifier
        vm.roll(currentBlock);

        uint256 actorCount = standardHandler_.getActorsCount();
        uint24 distributionId = grantFund_.getDistributionId();
        while (distributionId > 0) {

            // check invariants for all actors
            for (uint256 i = 0; i < actorCount; ++i) {
                address actor = standardHandler_.actors(i);
                uint256 votingPower = grantFund_.getVotesScreening(distributionId, actor);

                require(
                    standardHandler_.sumVoterScreeningVotes(actor, distributionId) <= votingPower,
                    "invariant SS2: can only vote up to the amount of voting power at the snapshot blocks"
                );

                // check the screening votes cast by the actor
                ( , IGrantFund.ScreeningVoteParams[] memory screeningVoteParams, ) = standardHandler_.getVotingActorsInfo(actor, distributionId);
                for (uint256 j = 0; j < screeningVoteParams.length; ++j) {
                    require(
                        screeningVoteParams[j].votes >= 0,
                        "invariant SS4: can only cast positive votes"
                    );

                    require(
                        _findProposalIndex(screeningVoteParams[j].proposalId, standardHandler_.getStandardFundingProposals(distributionId)) != -1,
                        "invariant SS8: a proposal can only receive screening votes if it was created via propose()"
                    );
                }
            }

            --distributionId;
        }
    }

}
