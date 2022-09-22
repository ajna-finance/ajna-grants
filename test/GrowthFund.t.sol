// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { AjnaToken } from "../src/BaseToken.sol";
import { GrowthFund } from "../src/GrowthFund.sol";
import { IGrowthFund } from "../src/interfaces/IGrowthFund.sol";

import { SigUtils } from "./utils/SigUtils.sol";
import { GrowthFundTestHelper } from "./GrowthFundTestHelper.sol";

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings } from "@oz/utils/Strings.sol"; // used for createNProposals

contract GrowthFundTest is GrowthFundTestHelper {

    // used to cast 256 to uint64 to match emit expectations
    using SafeCast for uint256;
    using Strings for string;

    AjnaToken  internal  _token;
    IVotes     internal  _votingToken;
    GrowthFund internal  _growthFund;
    SigUtils   internal  _sigUtils;

    address internal _tokenDeployer  = makeAddr("tokenDeployer");
    address internal _tokenHolder1   = makeAddr("_tokenHolder1");
    address internal _tokenHolder2   = makeAddr("_tokenHolder2");
    address internal _tokenHolder3   = makeAddr("_tokenHolder3");
    address internal _tokenHolder4   = makeAddr("_tokenHolder4");
    address internal _tokenHolder5   = makeAddr("_tokenHolder5");
    address internal _tokenHolder6   = makeAddr("_tokenHolder6");
    address internal _tokenHolder7   = makeAddr("_tokenHolder7");
    address internal _tokenHolder8   = makeAddr("_tokenHolder8");
    address internal _tokenHolder9   = makeAddr("_tokenHolder9");
    address internal _tokenHolder10   = makeAddr("_tokenHolder10");
    address internal _tokenHolder11   = makeAddr("_tokenHolder11");
    address internal _tokenHolder12   = makeAddr("_tokenHolder12");
    address internal _tokenHolder13   = makeAddr("_tokenHolder13");
    address internal _tokenHolder14   = makeAddr("_tokenHolder14");

    uint256 _initialAjnaTokenSupply   = 2_000_000_000 * 1e18;

    function setUp() external {
        vm.startPrank(_tokenDeployer);
        _token = new AjnaToken(_tokenHolder1);

        _sigUtils = new SigUtils(_token.DOMAIN_SEPARATOR());

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _growthFund = new GrowthFund(_votingToken);

        // initial minter distributes tokens to test addresses
        changePrank(_tokenHolder1);
        _token.transfer(_tokenHolder2, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder3, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder4, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder5, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder6, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder7, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder8, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder9, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder10, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder11, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder12, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder13, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder14, 50_000_000 * 1e18);

        // initial minter distributes treasury to growthFund
        _token.transfer(address(_growthFund), 500_000_000 * 1e18);
    }

    /*************/
    /*** Tests ***/
    /*************/

    function testGetVotingPower() external {
        uint256 pastBlock = 10;

        // skip forward 100 blocks
        vm.roll(100);
        assertEq(block.number, 100);

        uint256 votingPower = _growthFund.getVotes(address(_tokenHolder2), pastBlock);

        assertEq(votingPower, 0);

        // _tokenHolder2 self delegates
        _delegateVotes(_token, _tokenHolder2, _tokenHolder2);

        // skip forward 10 blocks
        vm.roll(110);
        assertEq(block.number, 110);

        votingPower = _growthFund.getVotes(address(_tokenHolder2), 100);
        assertEq(votingPower, 50_000_000 * 1e18);

        uint256 _votingTokenPowerViaInterface = _votingToken.getVotes(_tokenHolder2);
        assertGt(_votingTokenPowerViaInterface, 0);
    }

    function testGetVotingPowerScreeningStage() external {

    }

    function testGetVotingPowerFundingStage() external {

    }

    function testPropose() external {
        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder2,
            1 * 1e18
        );

        // generate proposal message 
        string memory description = "Proposal for Ajna token transfer to tester address";

        // create and submit proposal
        TestProposal memory proposal = _createProposal(_growthFund, _tokenHolder2, ajnaTokenTargets, values, proposalCalldata, description);

        vm.roll(10);

        // check proposal state
        IGovernor.ProposalState proposalState = _growthFund.state(proposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));
    }

    function testProposeTooManyTokens() external {

    }

    function testProposeInvalidCalldatas() external {

    }

    // disabled this test due to vote implementation overrides
    // works with a standard OZ.governor implementation
    function xtestVoteAndExecuteProposal() external {
        // tokenholders self delegate their tokens to enable voting on the proposal
        _delegateVotes(_token, _tokenHolder2, _tokenHolder2);
        _delegateVotes(_token, _tokenHolder3, _tokenHolder3);
        _delegateVotes(_token, _tokenHolder4, _tokenHolder4);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        uint256 proposalTokenAmount = 1 * 1e18;
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder2,
            proposalTokenAmount
        );

        // generate proposal message
        string memory description = "Proposal for Ajna token transfer to tester address";

        // create and submit proposal
        TestProposal memory proposal = _createProposal(_growthFund, _tokenHolder2, ajnaTokenTargets, values, proposalCalldata, description);
        uint256 proposalId = proposal.proposalId;

        vm.roll(110);

        // check proposal state
        IGovernor.ProposalState proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // _tokenHolder2 and _tokenHolder3 vote for (1), _tokenHolder4 vote against (0)
        _vote(_growthFund, _tokenHolder2, proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder3, proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder4, proposalId, 0, 100);

        // TODO: count vote status

        proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // TODO: switch to using _growthFund.votingPeriod() instead of hardcoded blocks to roll forward to
        // skip to the end of the voting period
        vm.roll(46000);

        // check proposal was succesful after deadline and with quorum reached
        proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Succeeded));

        assertEq(_token.balanceOf(_tokenHolder2), 50_000_000 * 1e18);
        assertEq(_token.balanceOf(address(_growthFund)), 500_000_000 * 1e18);

        // execute proposal
        vm.expectEmit(true, true, false, true);
        emit ProposalExecuted(proposalId);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_growthFund), _tokenHolder2, proposalTokenAmount);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(_tokenHolder2, 50_000_000 * 1e18, 50_000_001 * 1e18); 
        _growthFund.execute(ajnaTokenTargets, values, proposalCalldata, keccak256(bytes(description)));

        // check balances changes
        assertEq(_token.balanceOf(_tokenHolder2), 50_000_001 * 1e18);
        assertEq(_token.balanceOf(address(_growthFund)), 499_999_999 * 1e18);
    }

    /**
     *  @notice 4 voters consider 15 different proposals. 10 Make it through to the funding stage.
     */    
    function testScreenProposalsCheckSorting() external {
        // tokenholders self delegate their tokens to enable voting on the proposal
        _delegateVotes(_token, _tokenHolder2, _tokenHolder2);
        _delegateVotes(_token, _tokenHolder3, _tokenHolder3);
        _delegateVotes(_token, _tokenHolder4, _tokenHolder4);
        _delegateVotes(_token, _tokenHolder5, _tokenHolder5);
        _delegateVotes(_token, _tokenHolder6, _tokenHolder6);
        _delegateVotes(_token, _tokenHolder7, _tokenHolder7);
        _delegateVotes(_token, _tokenHolder8, _tokenHolder8);
        _delegateVotes(_token, _tokenHolder9, _tokenHolder9);
        _delegateVotes(_token, _tokenHolder10, _tokenHolder10);
        _delegateVotes(_token, _tokenHolder11, _tokenHolder11);
        _delegateVotes(_token, _tokenHolder12, _tokenHolder12);
        _delegateVotes(_token, _tokenHolder13, _tokenHolder13);
        _delegateVotes(_token, _tokenHolder14, _tokenHolder14);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // create 15 proposals paying out tokens to _tokenHolder2
        TestProposal[] memory testProposals = _createNProposals(_growthFund, _token, 15, _tokenHolder2);
        assertEq(testProposals.length, 15);

        vm.roll(110);

        // TODO: add additional duplicate votes to some of the proposals
        // screening period votes
        _vote(_growthFund, _tokenHolder2, testProposals[0].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder3, testProposals[1].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder4, testProposals[2].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder5, testProposals[3].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder6, testProposals[4].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder7, testProposals[5].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder8, testProposals[6].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder9, testProposals[7].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder10, testProposals[8].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder11, testProposals[9].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder12, testProposals[1].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder13, testProposals[1].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder14, testProposals[5].proposalId, 1, 100);

        // check topTenProposals array
        GrowthFund.Proposal[] memory proposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        assertEq(proposals.length, 10);
        assertEq(proposals[0].proposalId, testProposals[1].proposalId);
        assertEq(proposals[0].votesReceived, 150_000_000 * 1e18);

        assertEq(proposals[1].proposalId, testProposals[5].proposalId);
        assertEq(proposals[1].votesReceived, 100_000_000 * 1e18);
    }

    function testAllocateBudgetToTopTen() external {
        // tokenholders self delegate their tokens to enable voting on the proposal
        _delegateVotes(_token, _tokenHolder2, _tokenHolder2);
        _delegateVotes(_token, _tokenHolder3, _tokenHolder3);
        _delegateVotes(_token, _tokenHolder4, _tokenHolder4);
        _delegateVotes(_token, _tokenHolder5, _tokenHolder5);
        _delegateVotes(_token, _tokenHolder6, _tokenHolder6);
        _delegateVotes(_token, _tokenHolder7, _tokenHolder7);
        _delegateVotes(_token, _tokenHolder8, _tokenHolder8);
        _delegateVotes(_token, _tokenHolder9, _tokenHolder9);
        _delegateVotes(_token, _tokenHolder10, _tokenHolder10);
        _delegateVotes(_token, _tokenHolder11, _tokenHolder11);
        _delegateVotes(_token, _tokenHolder12, _tokenHolder12);
        _delegateVotes(_token, _tokenHolder13, _tokenHolder13);
        _delegateVotes(_token, _tokenHolder14, _tokenHolder14);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // create 15 proposals paying out tokens to _tokenHolder2
        TestProposal[] memory testProposals = _createNProposals(_growthFund, _token, 15, _tokenHolder2);
        assertEq(testProposals.length, 15);

        vm.roll(110);

        // screening period votes
        _vote(_growthFund, _tokenHolder2, testProposals[0].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder3, testProposals[1].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder4, testProposals[2].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder5, testProposals[3].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder6, testProposals[4].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder7, testProposals[5].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder8, testProposals[6].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder9, testProposals[7].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder10, testProposals[8].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder11, testProposals[9].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder12, testProposals[1].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder13, testProposals[1].proposalId, 1, 100);
        _vote(_growthFund, _tokenHolder14, testProposals[5].proposalId, 1, 100);

        // check topTenProposals array is correct after screening period
        GrowthFund.Proposal[] memory screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        assertEq(screenedProposals.length, 10);
        assertEq(screenedProposals[0].proposalId, testProposals[1].proposalId);
        assertEq(screenedProposals[0].votesReceived, 150_000_000 * 1e18);

        assertEq(screenedProposals[1].proposalId, testProposals[5].proposalId);
        assertEq(screenedProposals[1].votesReceived, 100_000_000 * 1e18);

        // skip time to move from screening period to funding period
        vm.roll(100_000);

        // tokenHolder2 partialy votes in support of funded proposal 1
        _fundingVote(_growthFund, _tokenHolder2, screenedProposals[0].proposalId, 1, 2 * 1e18, 100);

        // check proposal state
        (uint256 proposalId, uint256 distributionId, uint256 votesReceived, int256 tokensRequested, int256 fundingReceived, bool succeeded, bool executed) = _growthFund.getProposalInfo(screenedProposals[0].proposalId);
        assertEq(proposalId, testProposals[1].proposalId);
        assertEq(distributionId, _growthFund.getDistributionId());
        assertEq(votesReceived, 150_000_000 * 1e18);
        assertEq(tokensRequested, 2 * 1e18);
        assertEq(fundingReceived, 2 * 1e18);
        assertEq(succeeded, true);
        assertEq(executed, false);

        // TODO: add checks for voting weight
        // check voter info
        (, int256 budgetRemaining, ) = _growthFund.getVoterInfo(_growthFund.getDistributionId(), _tokenHolder2);
        assertEq(budgetRemaining, (50_000_000 * 1e18) ** 2 - 2 * 1e18);

        // tokenHolder 2 partially votes against proposal 2
        _fundingVote(_growthFund, _tokenHolder2, screenedProposals[1].proposalId, 0, -25 * 1e18, 100);

        (proposalId, distributionId, votesReceived, tokensRequested, fundingReceived, succeeded, executed) = _growthFund.getProposalInfo(screenedProposals[1].proposalId);
        assertEq(proposalId, testProposals[5].proposalId);
        assertEq(distributionId, _growthFund.getDistributionId());
        assertEq(votesReceived, 100_000_000 * 1e18);
        assertEq(tokensRequested, 6 * 1e18);
        assertEq(fundingReceived, -25 * 1e18);
        assertEq(succeeded, false);
        assertEq(executed, false);

        // check voter info
        (, budgetRemaining, ) = _growthFund.getVoterInfo(_growthFund.getDistributionId(), _tokenHolder2);
        assertEq(budgetRemaining, (50_000_000 * 1e18) ** 2 - 27 * 1e18);

        // tokenHolder 3 places entire budget in support of proposal 3 ensuring it meets it's request amount
        _fundingVote(_growthFund, _tokenHolder3, screenedProposals[2].proposalId, 1, 7 * 1e18, 100);

        (proposalId, distributionId, votesReceived, tokensRequested, fundingReceived, succeeded, executed) = _growthFund.getProposalInfo(screenedProposals[2].proposalId);
        assertEq(proposalId, testProposals[6].proposalId);
        assertEq(distributionId, _growthFund.getDistributionId());
        assertEq(votesReceived, 50_000_000 * 1e18);
        assertEq(tokensRequested, 7 * 1e18);
        assertEq(fundingReceived, 7 * 1e18);
        assertEq(succeeded, true);
        assertEq(executed, false);

        // check voter info
        (, budgetRemaining, ) = _growthFund.getVoterInfo(_growthFund.getDistributionId(), _tokenHolder3);
        assertEq(budgetRemaining, (50_000_000 * 1e18) ** 2 - 7 * 1e18);

        // skip to the endo f the DistributionPeriod
        vm.roll(200_000);

        // check DistributionPeriod info
        (, uint256 tokensDistributed, , , , bool distributionExecuted) = _growthFund.getDistributionPeriodInfo(_growthFund.getDistributionId());
        assertEq(tokensDistributed, 0 * 1e18);
        assertEq(distributionExecuted, false);

        uint256 tokensBurned = _growthFund.maximumQuarterlyDistribution() - 9 * 1e18;

        // finalize the distribution
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_growthFund), address(0), tokensBurned);
        vm.expectEmit(true, true, false, true);
        emit FinalizeDistribution(distributionId, tokensBurned);
        _growthFund.finalizeDistribution();

        // check DistributionPeriod info
        (, tokensDistributed, , , , distributionExecuted) = _growthFund.getDistributionPeriodInfo(_growthFund.getDistributionId());
        assertEq(tokensDistributed, 9 * 1e18);
        assertEq(distributionExecuted, true);

        // execute the two successful proposals, and check for revert of unsuccesful proposal

        // execute first successful proposal
        TestProposal memory testProposal = testProposals[1];
        vm.expectEmit(true, true, false, true);
        emit ProposalExecuted(testProposal.proposalId);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_growthFund), testProposal.recipient, testProposal.tokensRequested);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(testProposal.recipient, 50_000_000 * 1e18, 50_000_000 * 1e18 + testProposal.tokensRequested); 
        _growthFund.execute(testProposal.targets, testProposal.values, testProposal.calldatas, keccak256(bytes(testProposal.description)));
        assertEq(_token.balanceOf(testProposal.recipient), 50_000_002 * 1e18);

        // execute second successful proposal
        testProposal = testProposals[6];
        vm.expectEmit(true, true, false, true);
        emit ProposalExecuted(testProposal.proposalId);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_growthFund), testProposal.recipient, testProposal.tokensRequested);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(testProposal.recipient, 50_000_002 * 1e18, 50_000_002 * 1e18 + testProposal.tokensRequested); 
        _growthFund.execute(testProposal.targets, testProposal.values, testProposal.calldatas, keccak256(bytes(testProposal.description)));
        assertEq(_token.balanceOf(testProposal.recipient), 50_000_009 * 1e18);

        // executing unfunded proposal should fail
        testProposal = testProposals[5];
        vm.expectRevert(IGrowthFund.ProposalNotFunded.selector);
        _growthFund.execute(testProposal.targets, testProposal.values, testProposal.calldatas, keccak256(bytes(testProposal.description)));

        // executing proposal that didn't make it through screening should fail
        testProposal = testProposals[10];
        vm.expectRevert(IGrowthFund.ProposalNotFunded.selector);
        _growthFund.execute(testProposal.targets, testProposal.values, testProposal.calldatas, keccak256(bytes(testProposal.description)));
    }

    function testFundingVoteAllVotesAllocated() external {

    }

    function testStartNewDistributionPeriod() external {
        uint256 currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 0);

        _startDistributionPeriod(_growthFund);
        currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 1);

        (uint256 id, uint256 tokensDistributed, uint256 votesCast, uint256 startBlock, uint256 endBlock, bool executed) = _growthFund.getDistributionPeriodInfo(currentDistributionId);
        assertEq(id, currentDistributionId);
        assertEq(tokensDistributed, 0);
        assertEq(votesCast, 0);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + _growthFund.distributionPeriodLength());
        assertEq(executed, false);
    }

    function testFinalizeDistribution() external {

    }

    function testSetMaximumQuarterlyTokenDistribution() external {

    }

    function testQuorum() external {
        uint256 pastBlock = 10;

        // skip forward 100 blocks
        vm.roll(100);
        assertEq((_initialAjnaTokenSupply * 4) / 100, _growthFund.quorum(pastBlock));
    }

    function testUpdateSettings() external {}

    function testUpdateQuorum() external {}

    // TODO: move this into the voting tests?
    function testVotingDelay() external {}


}
