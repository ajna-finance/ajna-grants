// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console } from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { GrantFund }        from "../../../src/grants/GrantFund.sol";
import { IGrantFund }       from "../../../src/grants/interfaces/IGrantFund.sol";

import { TestBase }        from "./TestBase.sol";
import { StandardHandler } from "../handlers/StandardHandler.sol";

abstract contract FundingInvariants is TestBase {

    // hash the top ten proposals at the start of the funding stage to check composition
    bytes32 initialTopTenHash;

    function _invariant_FS1_FS2_FS3(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        uint256[] memory topTenProposals = grantFund_.getTopTenProposals(grantFund_.getDistributionId());

        // check if something went wrong in test setup
        assertTrue(topTenProposals.length > 0);

        require(
            topTenProposals.length <= 10,
            "invariant FS1: 10 or less proposals should make it through the screening stage"
        );

        uint24 distributionId = grantFund_.getDistributionId();
        uint256[] memory standardFundingProposals = standardHandler_.getStandardFundingProposals(distributionId);

        // check invariants against every proposal
        for (uint256 j = 0; j < standardFundingProposals.length; ++j) {
            uint256 proposalId = standardHandler_.standardFundingProposals(distributionId, j);
            (, uint24 proposalDistributionId, , , int128 fundingVotesReceived, ) = grantFund_.getProposalInfo(proposalId);

            if (_findProposalIndex(proposalId, topTenProposals) == -1) {
                require(
                    fundingVotesReceived == 0,
                    "invariant FS2: proposals not in the top ten should not be able to recieve funding votes"
                );
            }

            require(
                distributionId == proposalDistributionId,
                "invariant FS3: distribution id for a proposal should be the same as the current distribution id"
            );
        }
    }

    function _invariant_FS4_FS5_FS6_FS7_FS8(GrantFund grantFund_, StandardHandler standardHandler_) internal {
        uint24 distributionId = grantFund_.getDistributionId();

        // check invariants against every actor
        for (uint256 i = 0; i < standardHandler_.getActorsCount(); ++i) {
            address actor = standardHandler_.actors(i);

            // get the initial funding stage voting power of the actor
            (uint128 votingPower, uint128 remainingVotingPower, uint256 numberOfProposalsVotedOn) = grantFund_.getVoterInfo(distributionId, actor);

            // get the voting info of the actor
            (IGrantFund.FundingVoteParams[] memory fundingVoteParams, , ) = standardHandler_.getVotingActorsInfo(actor, distributionId);

            uint128 sumOfSquares = SafeCast.toUint128(standardHandler_.sumSquareOfVotesCast(fundingVoteParams));

            // check voter votes cast are less than or equal to the sqrt of the voting power of the actor
            IGrantFund.FundingVoteParams[] memory fundingVotesCast = grantFund_.getFundingVotesCast(distributionId, actor);

            require(
                sumOfSquares <= votingPower,
                "invariant FS4: sum of square of votes cast <= voting power of actor"
            );
            require(
                sumOfSquares == votingPower - remainingVotingPower,
                "invariant FS5: Sum of voter's votesCast should be equal to the square root of the voting power expended (FS4 restated, but added to test intermediate state as well as final)."
            );

            // check that the test functioned as expected
            if (votingPower != 0 && remainingVotingPower == 0) {
                assertTrue(numberOfProposalsVotedOn == fundingVotesCast.length);
                assertTrue(numberOfProposalsVotedOn > 0);
            }

            require(
                uint256(standardHandler_.sumFundingVotes(fundingVoteParams)) <= _ajna.totalSupply(),
                "invariant FS8: a voter should never be able to cast more votes than the Ajna token supply"
            );

            // check that there weren't any duplicate proposal entries, as votes for same proposal should be combined
            uint256[] memory proposalIdsVotedOn = new uint256[](fundingVotesCast.length);
            for (uint j = 0; j < fundingVotesCast.length; ) {
                proposalIdsVotedOn[j] = fundingVotesCast[j].proposalId;
                ++j;
            }
            require(
                standardHandler_.hasDuplicates(proposalIdsVotedOn) == false,
                "invariant FS6: All voter funding votes on a proposal should be cast in the same direction. Multiple votes on the same proposal should see the voting power increase according to the combined cost of votes."
            );
        }

        require(
            keccak256(abi.encode(grantFund_.getTopTenProposals(distributionId))) == initialTopTenHash,
            "invariant FS7: List of top ten proposals should never change once the funding stage has started"
        );
    }

}

