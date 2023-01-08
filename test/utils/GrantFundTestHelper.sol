// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings }  from "@oz/utils/Strings.sol"; // used for createNProposals
import { Test }     from "@std/Test.sol";

import { GrantFund }        from "../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { IAjnaToken }       from "./IAjnaToken.sol";

abstract contract GrantFundTestHelper is Test {

    using SafeCast for uint256;
    using Strings for string;

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

    event FundedSlateUpdated(uint256 indexed distributionId_, bytes32 indexed fundedSlateHash_);
    event QuarterlyDistributionStarted(uint256 indexed distributionId_, uint256 startBlock_, uint256 endBlock_);
    event DelegateRewardClaimed(address indexed delegateeAddress_, uint256 indexed distributionId_, uint256 rewardClaimed_);

    /***********************/
    /*** Testing Structs ***/
    /***********************/

    struct TestProposal {
        uint256 proposalId;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        address recipient;
        uint256 tokensRequested;
    }

    struct TestProposalExtraordinary {
        uint256 proposalId;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        address recipient;
        uint256 tokensRequested;
        uint256 endBlock;
    }

    struct TestProposalParams {
        address recipient;
        uint256 tokensRequested;
    }

    uint8 voteNo = 0;
    uint8 voteYes = 1;

    /*****************************/
    /*** Test Helper Functions ***/
    /*****************************/

    // helper method to check if element exists in array
    function _checkElementExist(uint256 element, uint256[] memory arr) internal pure returns(bool) {
        for(uint i = 0; i < arr.length; i++) {
            if(element == arr[i]){
                return true;
            }
        }
        return false;
    }

    function _claimDelegateReward(GrantFund grantFund_, address voter_, uint256 distributionId_, uint256 claimedReward_) internal {
        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit DelegateRewardClaimed(voter_, distributionId_, claimedReward_);
        grantFund_.claimDelegateReward(distributionId_);
    }

    function _createProposalExtraordinary(
        GrantFund grantFund_,
        address proposer_,
        uint256 endBlock,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory proposalCalldatas_,
        string memory description
    ) internal returns (TestProposalExtraordinary memory) {
        // generate expected proposal state
        uint256 expectedProposalId = grantFund_.hashProposal(targets_, values_, proposalCalldatas_, keccak256(bytes(description)));
        uint256 startBlock = block.number;

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
        uint256 proposalId = grantFund_.proposeExtraordinary(endBlock, targets_, values_, proposalCalldatas_, description);
        assertEq(proposalId, expectedProposalId);

        // https://github.com/ethereum/solidity/issues/6012
        (, address recipient, uint256 tokensRequested) = abi.decode(
            abi.encodePacked(bytes28(0), proposalCalldatas_[0]),
            (bytes32,address,uint256)
        );

        return TestProposalExtraordinary(proposalId, targets_, values_, proposalCalldatas_, description, recipient, tokensRequested, endBlock);
    }

    function _createProposalStandard(GrantFund grantFund_, address proposer_, address[] memory targets_, uint256[] memory values_, bytes[] memory proposalCalldatas_, string memory description) internal returns (TestProposal memory) {
        // generate expected proposal state
        uint256 expectedProposalId = grantFund_.hashProposal(targets_, values_, proposalCalldatas_, keccak256(bytes(description)));
        uint256 startBlock = block.number.toUint64() + grantFund_.votingDelay().toUint64();

        (, , , uint256 endBlock, , ) = grantFund_.getDistributionPeriodInfo(grantFund_.getDistributionId());

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
        uint256 proposalId = grantFund_.proposeStandard(targets_, values_, proposalCalldatas_, description);
        assertEq(proposalId, expectedProposalId);

        // https://github.com/ethereum/solidity/issues/6012
        (, address recipient, uint256 tokensRequested) = abi.decode(
            abi.encodePacked(bytes28(0), proposalCalldatas_[0]),
            (bytes32,address,uint256)
        );

        return TestProposal(proposalId, targets_, values_, proposalCalldatas_, description, recipient, tokensRequested);
    }

    function _createNProposals(GrantFund grantFund_, IAjnaToken token_, TestProposalParams[] memory testProposalParams_) internal returns (TestProposal[] memory) {
        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(token_);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        TestProposal[] memory testProposals = new TestProposal[](testProposalParams_.length);

        for (uint256 i = 0; i < testProposalParams_.length; ++i) {

            // generate description string
            string memory descriptionPartOne = "Proposal to transfer ";
            string memory descriptionPartTwo = Strings.toString(testProposalParams_[i].tokensRequested);
            string memory descriptionPartThree = " tokens to tester address";
            string memory description = string(abi.encodePacked(descriptionPartOne, descriptionPartTwo, descriptionPartThree));

            // generate calldata
            bytes[] memory proposalCalldata = new bytes[](1);
            proposalCalldata[0] = abi.encodeWithSignature(
                "transfer(address,uint256)",
                testProposalParams_[i].recipient,
                testProposalParams_[i].tokensRequested
            );

            TestProposal memory proposal = _createProposalStandard(grantFund_, testProposalParams_[i].recipient, ajnaTokenTargets, values, proposalCalldata, description);
            testProposals[i] = proposal;
        }
        return testProposals;
    }

    function _delegateVotes(IAjnaToken token_, address delegator_, address delegatee_) internal {
        changePrank(delegator_);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator_, address(0), delegatee_);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegatee_, 0, 50_000_000 * 1e18);
        token_.delegate(delegatee_);
    }

    function _selfDelegateVoters(IAjnaToken token_, address[] memory voters_) internal {
        for (uint256 i = 0; i < voters_.length; ++i) {
            _delegateVotes(token_, voters_[i], voters_[i]);
        }
    }

    /**
     * @notice Helper function to execute a standard funding mechanism proposal.
     */
    function _executeProposal(GrantFund grantFund_, IAjnaToken token_, TestProposal memory testProposal_) internal {
        // calculate starting balances
        uint256 voterStartingBalance = token_.balanceOf(testProposal_.recipient);
        uint256 growthFundStartingBalance = token_.balanceOf(address(grantFund_));

        // execute proposal
        changePrank(testProposal_.recipient);
        vm.expectEmit(true, true, false, true);
        emit ProposalExecuted(testProposal_.proposalId);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(grantFund_), testProposal_.recipient, testProposal_.tokensRequested);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(testProposal_.recipient, voterStartingBalance, voterStartingBalance + testProposal_.tokensRequested);
        grantFund_.executeStandard(testProposal_.targets, testProposal_.values, testProposal_.calldatas, keccak256(bytes(testProposal_.description)));

        // check ending token balances
        assertEq(token_.balanceOf(testProposal_.recipient), voterStartingBalance + testProposal_.tokensRequested);
        assertEq(token_.balanceOf(address(grantFund_)), growthFundStartingBalance - testProposal_.tokensRequested);
    }

    function _executeExtraordinaryProposal(GrantFund grantFund_, IAjnaToken token_, TestProposalExtraordinary memory testProposal_) internal {
        // calculate starting balances
        uint256 voterStartingBalance = token_.balanceOf(testProposal_.recipient);
        uint256 growthFundStartingBalance = token_.balanceOf(address(grantFund_));

        // execute proposal
        changePrank(testProposal_.recipient);
        vm.expectEmit(true, true, false, true);
        emit ProposalExecuted(testProposal_.proposalId);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(grantFund_), testProposal_.recipient, testProposal_.tokensRequested);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(testProposal_.recipient, voterStartingBalance, voterStartingBalance + testProposal_.tokensRequested);
        grantFund_.executeExtraordinary(testProposal_.targets, testProposal_.values, testProposal_.calldatas, keccak256(bytes(testProposal_.description)));

        // check ending token balances
        assertEq(token_.balanceOf(testProposal_.recipient), voterStartingBalance + testProposal_.tokensRequested);
        assertEq(token_.balanceOf(address(grantFund_)), growthFundStartingBalance - testProposal_.tokensRequested);
    }

    function _extraordinaryVote(GrantFund grantFund_, address voter_, uint256 proposalId_, uint8 support_) internal {
        uint256 votingWeight = grantFund_.getVotesWithParams(voter_, block.number, abi.encode(proposalId_));

        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, votingWeight, "");
        grantFund_.castVote(proposalId_, support_);
    }

    function _fundingVote(GrantFund grantFund_, address voter_, uint256 proposalId_, uint8 support_, int256 votesAllocated_) internal {
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
        grantFund_.castVoteWithReasonAndParams(proposalId_, support_, reason, params);
    }

    // Returns a random proposal Index from all proposals
    function _getRandomProposal(uint256 noOfProposals_) internal returns(uint256 proposal_) {
        // calculate random proposal Index between 0 and noOfProposals_
        proposal_ = uint256(keccak256(abi.encodePacked(block.number, block.difficulty))) % noOfProposals_;
        vm.roll(block.number + 1);
    }

    // Returns a voters address array with N voters 
    function _getVoters(uint256 noOfVoters_) internal returns(address[] memory) {
        address[] memory voters_ = new address[](noOfVoters_);
        for(uint i = 0; i < noOfVoters_; i++) {
            voters_[i] = makeAddr(string(abi.encodePacked("Voter", Strings.toString(i))));
        }
        return voters_;
    }

    // Transfers a random amount of tokens to N voters and self delegates votes
    function _getVotes(uint256 noOfVoters_, address[] memory voters_, IAjnaToken token_, address tokenDeployer_) internal returns(uint256[] memory) {
        uint256[] memory votes_ = new uint256[](noOfVoters_);
        for(uint i = 0; i < noOfVoters_; i++) {
            uint256 votes = _randomVote();
            changePrank(tokenDeployer_);
            token_.transfer(voters_[i], votes);
            changePrank(voters_[i]);
            token_.delegate(voters_[i]);
            votes_[i] = votes;
        }
        return votes_;
    }

    // Submits N Proposal with fixed token requested
    function _getProposals(uint256 noOfProposals_, GrantFund grantFund_, address proponent_, IAjnaToken token_) internal returns(TestProposal[] memory) {

        TestProposal[] memory proposals_ = new TestProposal[](noOfProposals_);

        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(token_);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            proponent_,
            1_000_000 * 1e18
        );

        for(uint i = 0; i < noOfProposals_; i++) {
            // generate proposal message 
            string memory description = string(abi.encodePacked("Proposal", Strings.toString(i)));
            proposals_[i] = _createProposalStandard(grantFund_, proponent_, ajnaTokenTargets, values, proposalCalldata, description); 
        }
        return proposals_;
    }

    function _getProposalListFromProposalIds(GrantFund grantFund_, uint256[] memory proposalIds_) internal view returns (GrantFund.Proposal[] memory) {
        GrantFund.Proposal[] memory proposals = new GrantFund.Proposal[](proposalIds_.length);
        for (uint256 i = 0; i < proposalIds_.length; ++i) {
            (
                proposals[i].proposalId,
                proposals[i].distributionId,
                proposals[i].votesReceived,
                proposals[i].tokensRequested,
                proposals[i].qvBudgetAllocated,
                proposals[i].executed
            ) = grantFund_.getProposalInfo(proposalIds_[i]);
        }
        return proposals;
    }

    // Submits N Extra Ordinary Proposals
    function _getNExtraOridinaryProposals(uint256 noOfProposals_, GrantFund grantFund_, address proponent_, IAjnaToken token_, uint256 tokenRequested_) internal returns(TestProposalExtraordinary[] memory) {
        TestProposalExtraordinary[] memory proposals_ = new TestProposalExtraordinary[](noOfProposals_);

        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(token_);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            proponent_,
            tokenRequested_
        );

        for(uint i = 0; i < noOfProposals_; i++) {
            // generate proposal message 
            string memory description = string(abi.encodePacked("Proposal", Strings.toString(i)));

            // submit proposal with 1 month end time
            proposals_[i] = _createProposalExtraordinary(grantFund_, proponent_, block.number + 216_000, ajnaTokenTargets, values, proposalCalldata, description);
        }
        return proposals_;
    }

    // Returns random votes for a user
    function _randomVote() internal returns (uint256 votes_) {
        // calculate random vote between 1 and 1.25 * 1e18
        votes_ = 1 + uint256(keccak256(abi.encodePacked(block.number, block.difficulty))) % (1.25 * 1e18);
        vm.roll(block.number + 1);
    }

    function _startDistributionPeriod(GrantFund grantFund_) internal {
        vm.expectEmit(true, true, false, true);
        emit QuarterlyDistributionStarted(grantFund_.getDistributionId() + 1, block.number, block.number + 648000);
        grantFund_.startNewDistributionPeriod();
    }

    function _transferAjnaTokens(IAjnaToken token_, address[] memory voters_, uint256 amount_, address tokenDeployer_) internal {
        changePrank(tokenDeployer_);
        for (uint256 i = 0; i < voters_.length; ++i) {
            token_.transfer(voters_[i], amount_);
        }
    }

    function _vote(GrantFund grantFund_, address voter_, uint256 proposalId_, uint8 support_, uint256 votingWeightSnapshotBlock_) internal {
        uint256 votingWeight = grantFund_.getVotes(voter_, votingWeightSnapshotBlock_);

        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, votingWeight, "");
        grantFund_.castVote(proposalId_, support_);
    }

}
