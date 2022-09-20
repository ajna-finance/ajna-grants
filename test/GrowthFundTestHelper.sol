// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { AjnaToken } from "../src/BaseToken.sol";
import { GrowthFund } from "../src/GrowthFund.sol";

import { SigUtils } from "./utils/SigUtils.sol";

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings } from "@oz/utils/Strings.sol"; // used for createNProposals

abstract contract GrowthFundTestHelper is Test {

    using SafeCast for uint256;
    using Strings for string;

    // TODO: replace with selectors from Governor interface?
    /***************************/
    /*** OpenZeppelin Events ***/
    /***************************/

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event ProposalExecuted(uint256 proposalId);
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**************************/
    /*** Growth Fund Events ***/
    /**************************/

    event FinalizeDistribution(uint256 indexed distributionId_, uint256 tokensBurned);
    event QuarterlyDistributionStarted(uint256 indexed distributionId_, uint256 startBlock_, uint256 endBlock_);

    /***********************/
    /*** Testing Structs ***/
    /***********************/

    struct TestProposal {
        uint256 proposalId;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    /*****************************/
    /*** Test Helper Functions ***/
    /*****************************/

    function _createProposal(GrowthFund growthFund_, address proposer_, address[] memory targets_, uint256[] memory values_, bytes[] memory proposalCalldatas_, string memory description) internal returns (TestProposal memory) {
        // generate expected proposal state
        uint256 expectedProposalId = growthFund_.hashProposal(targets_, values_, proposalCalldatas_, keccak256(bytes(description)));
        uint256 startBlock = block.number.toUint64() + growthFund_.votingDelay().toUint64();
        uint256 endBlock   = startBlock + growthFund_.votingPeriod().toUint64();

        // submit proposal
        changePrank(proposer_);
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            expectedProposalId,
            proposer_,
            targets_,
            values_,
            new string[](targets_.length),
            proposalCalldatas_,
            startBlock,
            endBlock,
            description
        );
        uint256 proposalId = growthFund_.propose(targets_, values_, proposalCalldatas_, description);
        assertEq(proposalId, expectedProposalId);

        return TestProposal(proposalId, targets_, values_, proposalCalldatas_, description);
    }

    // TODO: make token receivers dynamic as well?
    function _createNProposals(GrowthFund growthFund_, AjnaToken token_, uint n, address tokenReceiver_) internal returns (TestProposal[] memory) {
        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(token_);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        TestProposal[] memory testProposals = new TestProposal[](n);

        for (uint256 i = 1; i < n + 1; ++i) {

            // generate description string
            string memory descriptionPartOne = "Proposal to transfer ";
            string memory descriptionPartTwo = Strings.toString(i * 1e18);
            string memory descriptionPartThree = " tokens to tester address";
            string memory description = string(abi.encodePacked(descriptionPartOne, descriptionPartTwo, descriptionPartThree));

            // generate calldata
            bytes[] memory proposalCalldata = new bytes[](1);
            proposalCalldata[0] = abi.encodeWithSignature(
                "transfer(address,uint256)",
                tokenReceiver_,
                i * 1e18
            );

            TestProposal memory proposal = _createProposal(growthFund_, tokenReceiver_, ajnaTokenTargets, values, proposalCalldata, description);
            testProposals[i - 1] = proposal;
        }
        return testProposals;
    }

    function _delegateVotes(AjnaToken token_, address delegator_, address delegatee_) internal {
        changePrank(delegator_);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator_, address(0), delegatee_);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegatee_, 0, 50_000_000 * 1e18);
        token_.delegate(delegatee_);
    }

    function _startDistributionPeriod(GrowthFund growthFund_) internal {
        vm.expectEmit(true, true, false, true);
        emit QuarterlyDistributionStarted(1, block.number, block.number + growthFund_.distributionPeriodLength());
        growthFund_.startNewDistributionPeriod();
    }

    function _vote(GrowthFund growthFund_, address voter_, uint256 proposalId_, uint8 support_, uint256 votingWeightSnapshotBlock_) internal {
        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, growthFund_.getVotes(address(voter_), votingWeightSnapshotBlock_), "");
        growthFund_.castVote(proposalId_, support_);
    }

    function _fundingVote(GrowthFund growthFund_, address voter_, uint256 proposalId_, uint8 support_, int256 votesAllocated_, uint256) internal {
        string memory reason = "";
        bytes memory params = abi.encode(votesAllocated_);

        // convert negative votes to account for budget expenditure and check emit value
        uint256 voteAllocatedEmit;
        if (votesAllocated_ < 0) {
            voteAllocatedEmit = uint256(votesAllocated_ * -1);
        }
        else {
            voteAllocatedEmit = uint256(votesAllocated_);
        }

        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, voteAllocatedEmit, "");
        growthFund_.castVoteWithReasonAndParams(proposalId_, support_, reason, params);
    }

}
