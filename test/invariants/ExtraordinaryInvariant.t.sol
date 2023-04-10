// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console }  from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IExtraordinaryFunding } from "../../src/grants/interfaces/IExtraordinaryFunding.sol";
import { Maths }                 from "../../src/grants/libraries/Maths.sol";

import { ExtraordinaryTestBase } from "./base/ExtraordinaryTestBase.sol";
import { ExtraordinaryHandler }  from "./handlers/ExtraordinaryHandler.sol";

contract ExtraordinaryInvariant is ExtraordinaryTestBase {

    function setUp() public override {
        super.setUp();

        // TODO: need to setCurrentBlock?
        currentBlock = block.number;

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = _extraordinaryHandler.proposeExtraordinary.selector;
        selectors[1] = _extraordinaryHandler.voteExtraordinary.selector;
        selectors[2] = _extraordinaryHandler.executeExtraordinary.selector;
        selectors[3] = _extraordinaryHandler.roll.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_extraordinaryHandler),
            selectors: selectors
        }));
    }

    function invariant_PE2_PE3_EE2() external view {
        uint256[] memory proposals = _extraordinaryHandler.getExtraordinaryProposals();

        for (uint256 i = 0; i < proposals.length; ++i) {
            TestProposalExtraordinary memory proposal = _extraordinaryHandler.getTestProposal(proposals[i]);

            (
                uint256 proposalId,
                ,
                ,
                uint128 tokensRequested,
                uint120 votesReceived,
                bool executed
            ) = _grantFund.getExtraordinaryProposalInfo(proposal.proposalId);

            // // FIXME: check test setup
            // assertEq(uint256(tokensRequested), proposal.totalTokensRequested);
            // assertEq(proposalId, proposal.proposalId);

            // check proposal end block
            require(
                proposal.endBlock <= proposal.startBlock + 216_000,
                "invariant PE2: A proposal's endBlock must be less than the MAX_EFM_PROPOSAL_LENGTH of 216_000 blocks"
            );

            // check tokens requested
            require(
                proposal.totalTokensRequested < Maths.wmul(proposal.treasuryBalanceAtSubmission, 1e18 - _grantFund.getMinimumThresholdPercentage()),
                "invariant PE3: A proposal's tokens requested must be less than treasuryBalance * (1 - minimumThresholdPercentage)"
            );

            // check executed proposals's exceeded required vote threshold
            if (executed) {
                // require(
                //     votesReceived >= Maths.wmul(proposal.treasuryBalanceAtSubmission, _grantFund.getMinimumThresholdPercentage()),
                //     "invariant EE2: A proposal can only be executed after it surpasses the minimum vote threshold"
                // );
            }
        }
    }

    function invariant_VE1() external view {
        for (uint256 i = 0; i < _extraordinaryHandler.getActorsCount(); ++i) {
            address actor = _extraordinaryHandler.actors(i);

            ExtraordinaryHandler.ExtraordinaryVoteParams[] memory voteParams = _extraordinaryHandler.getVotingActorsInfo(actor);

            // check has no duplicates
            require(
                !hasDuplicates(_extraordinaryHandler.getVotingActorsProposals(actor)),
                "invariant VE1: A proposal can only be voted on once"
            );
        }
    }

    function invariant_call_summary() external view {
        _extraordinaryHandler.logCallSummary();
        _extraordinaryHandler.logActorSummary(true);
        _logExtraordinarySummary();
    }

    function _logExtraordinarySummary() internal view {
        console.log("\nExtraordinary Summary\n");
        console.log("------------------");
        console.log("Extraordinary Proposals:  %s", _extraordinaryHandler.getExtraordinaryProposals().length);
        console.log("Extraordinary Executions: %s", _extraordinaryHandler.getExecutedExtraordinaryProposals().length);
    }

}
