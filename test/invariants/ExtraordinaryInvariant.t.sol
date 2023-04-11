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

    function invariant_PE2_PE3_EE2_EE3_EE4() external view {
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

            console.log("grant fund state tokens requested:               %s", tokensRequested);
            console.log("proposal.totalTokensRequested:                   %s", proposal.totalTokensRequested);
            console.log("proposal.treasuryBalanceAtSubmission:            %s", proposal.treasuryBalanceAtSubmission);
            console.log("proposal.minimumThresholdPercentageAtSubmission: %s", proposal.minimumThresholdPercentageAtSubmission);

            // FIXME: check tokens requested -> proposal.totalTokensRequested seems to be messed up
            // need to get the minimum threshold percentage at time of submission
            require(
                proposal.totalTokensRequested <= Maths.wmul(proposal.treasuryBalanceAtSubmission, Maths.WAD - proposal.minimumThresholdPercentageAtSubmission),
                "invariant PE3: A proposal's tokens requested must be less than treasuryBalance * (1 - minimumThresholdPercentage)"
            );

            // TODO: get the minimum threshold percentage at time of execution
            // check executed proposals's exceeded required vote threshold
            if (executed) {
                require(
                    votesReceived >= tokensRequested + Maths.wmul((proposal.ajnaTotalSupplyAtExecution - proposal.treasuryBalanceAtExecution), proposal.minimumThresholdPercentageAtExecution),
                    "invariant EE2: A proposal can only be executed if its votesReceived exceeds its tokensRequested + the minimumThresholdPercentage times the non-treasury token supply at the time of execution"
                );
                require(
                    proposal.totalTokensRequested < Maths.wmul(proposal.treasuryBalanceAtExecution, Maths.WAD - proposal.minimumThresholdPercentageAtExecution),
                    "invariant EE3: A proposal can only be executed if it's tokensRequested is less than treasury * (1 - minimumThresholdPercentage)"
                );
            }
        }

        require(
            _extraordinaryHandler.getExecutedExtraordinaryProposals().length < 10,
            "invariant EE4: Only 9 proposals can be executed"
        );
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

    function invariant_EG1() external view {
        uint256 numberOfProposalsExecuted = _extraordinaryHandler.getExecutedExtraordinaryProposals().length;

        require(
            _grantFund.getMinimumThresholdPercentage() == 0.5 * 1e18 + (numberOfProposalsExecuted * (0.05 * 1e18)),
            "invariant EG1: The `minimumThresholdPercentage` variable increases by 5% for each successive executed proposal"
        );
    }

    function invariant_call_summary() external view {
        _extraordinaryHandler.logCallSummary();
        _extraordinaryHandler.logActorSummary(false);
        _logExtraordinarySummary();
    }

    function _logExtraordinarySummary() internal view {
        console.log("\nExtraordinary Summary\n");
        console.log("------------------");
        console.log("Extraordinary Proposals:  %s", _extraordinaryHandler.getExtraordinaryProposals().length);
        console.log("Extraordinary Executions: %s", _extraordinaryHandler.getExecutedExtraordinaryProposals().length);
    }

}
