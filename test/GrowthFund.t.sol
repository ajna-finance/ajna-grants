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

contract GrowthFundTest is Test {

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

    /*****************************/
    /*** Test Helper Functions ***/
    /*****************************/

    // TODO: finish implementing 
    function _createProposal(address proposer_, address[] memory targets_, uint256[] memory values_, bytes[] memory proposalCalldatas_, string memory description) internal returns (uint256) {
        // generate expected proposal state
        uint256 expectedProposalId = _growthFund.hashProposal(targets_, values_, proposalCalldatas_, keccak256(bytes(description)));
        uint256 startBlock = block.number.toUint64() + _growthFund.votingDelay().toUint64();
        uint256 endBlock   = startBlock + _growthFund.votingPeriod().toUint64();

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
        uint256 proposalId = _growthFund.propose(targets_, values_, proposalCalldatas_, description);
        assertEq(proposalId, expectedProposalId);

        return proposalId;
    }

    // TODO: make token receivers dynamic as well?
    function _createNProposals(uint n, address tokenReceiver_) internal returns (uint256[] memory) {
        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        uint256[] memory returnProposalIds = new uint256[](n);

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

            uint256 proposalId = _createProposal(tokenReceiver_, ajnaTokenTargets, values, proposalCalldata, description);
            returnProposalIds[i - 1] = proposalId;

        }
        return returnProposalIds;
    }

    function _delegateVotes(address delegator_, address delegatee_) internal {
        changePrank(delegator_);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator_, address(0), delegatee_);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegatee_, 0, 50_000_000 * 1e18);
        _token.delegate(delegatee_);
    }

    function _startDistributionPeriod() internal {
        vm.expectEmit(true, true, false, true);
        emit QuarterlyDistributionStarted(1, block.number, block.number + _growthFund.distributionPeriodLength());
        _growthFund.startNewDistributionPeriod();
    }

    function _vote(address voter_, uint256 proposalId_, uint8 support_, uint256 votingWeightSnapshotBlock_) internal {
        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, _growthFund.getVotes(address(voter_), votingWeightSnapshotBlock_), "");
        _growthFund.castVote(proposalId_, support_);
    }

    function _fundingVote(address voter_, uint256 proposalId_, uint8 support_, int256 votesAllocated_, uint256) internal {
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
        _growthFund.castVoteWithReasonAndParams(proposalId_, support_, reason, params);
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
        _delegateVotes(_tokenHolder2, _tokenHolder2);

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
        uint256 proposalId = _createProposal(_tokenHolder2, ajnaTokenTargets, values, proposalCalldata, description);

        vm.roll(10);

        // check proposal state
        IGovernor.ProposalState proposalState = _growthFund.state(proposalId);
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
        _delegateVotes(_tokenHolder2, _tokenHolder2);
        _delegateVotes(_tokenHolder3, _tokenHolder3);
        _delegateVotes(_tokenHolder4, _tokenHolder4);

        // start distribution period
        _startDistributionPeriod();

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
        uint256 proposalId = _createProposal(_tokenHolder2, ajnaTokenTargets, values, proposalCalldata, description);

        vm.roll(110);

        // check proposal state
        IGovernor.ProposalState proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // _tokenHolder2 and _tokenHolder3 vote for (1), _tokenHolder4 vote against (0)
        _vote(_tokenHolder2, proposalId, 1, 100);
        _vote(_tokenHolder3, proposalId, 1, 100);
        _vote(_tokenHolder4, proposalId, 0, 100);

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
        _delegateVotes(_tokenHolder2, _tokenHolder2);
        _delegateVotes(_tokenHolder3, _tokenHolder3);
        _delegateVotes(_tokenHolder4, _tokenHolder4);
        _delegateVotes(_tokenHolder5, _tokenHolder5);
        _delegateVotes(_tokenHolder6, _tokenHolder6);
        _delegateVotes(_tokenHolder7, _tokenHolder7);
        _delegateVotes(_tokenHolder8, _tokenHolder8);
        _delegateVotes(_tokenHolder9, _tokenHolder9);
        _delegateVotes(_tokenHolder10, _tokenHolder10);
        _delegateVotes(_tokenHolder11, _tokenHolder11);
        _delegateVotes(_tokenHolder12, _tokenHolder12);
        _delegateVotes(_tokenHolder13, _tokenHolder13);
        _delegateVotes(_tokenHolder14, _tokenHolder14);

        // start distribution period
        _startDistributionPeriod();

        // create 15 proposals paying out tokens to _tokenHolder2
        uint256[] memory proposalIds = _createNProposals(15, _tokenHolder2);
        assertEq(proposalIds.length, 15);

        vm.roll(110);

        // TODO: add additional duplicate votes to some of the proposals
        // screening period votes
        _vote(_tokenHolder2, proposalIds[0], 1, 100);
        _vote(_tokenHolder3, proposalIds[1], 1, 100);
        _vote(_tokenHolder4, proposalIds[2], 1, 100);
        _vote(_tokenHolder5, proposalIds[3], 1, 100);
        _vote(_tokenHolder6, proposalIds[4], 1, 100);
        _vote(_tokenHolder7, proposalIds[5], 1, 100);
        _vote(_tokenHolder8, proposalIds[6], 1, 100);
        _vote(_tokenHolder9, proposalIds[7], 1, 100);
        _vote(_tokenHolder10, proposalIds[8], 1, 100);
        _vote(_tokenHolder11, proposalIds[9], 1, 100);
        _vote(_tokenHolder12, proposalIds[1], 1, 100);
        _vote(_tokenHolder13, proposalIds[1], 1, 100);
        _vote(_tokenHolder14, proposalIds[5], 1, 100);

        // check topTenProposals array
        GrowthFund.Proposal[] memory proposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        assertEq(proposals.length, 10);
        assertEq(proposals[0].proposalId, proposalIds[1]);
        assertEq(proposals[0].votesReceived, 150_000_000 * 1e18);

        assertEq(proposals[1].proposalId, proposalIds[5]);
        assertEq(proposals[1].votesReceived, 100_000_000 * 1e18);
    }

    function testAllocateBudgetToTopTen() external {
        // tokenholders self delegate their tokens to enable voting on the proposal
        _delegateVotes(_tokenHolder2, _tokenHolder2);
        _delegateVotes(_tokenHolder3, _tokenHolder3);
        _delegateVotes(_tokenHolder4, _tokenHolder4);
        _delegateVotes(_tokenHolder5, _tokenHolder5);
        _delegateVotes(_tokenHolder6, _tokenHolder6);
        _delegateVotes(_tokenHolder7, _tokenHolder7);
        _delegateVotes(_tokenHolder8, _tokenHolder8);
        _delegateVotes(_tokenHolder9, _tokenHolder9);
        _delegateVotes(_tokenHolder10, _tokenHolder10);
        _delegateVotes(_tokenHolder11, _tokenHolder11);
        _delegateVotes(_tokenHolder12, _tokenHolder12);
        _delegateVotes(_tokenHolder13, _tokenHolder13);
        _delegateVotes(_tokenHolder14, _tokenHolder14);

        // start distribution period
        _startDistributionPeriod();

        // create 15 proposals paying out tokens to _tokenHolder2
        uint256[] memory proposalIds = _createNProposals(15, _tokenHolder2);
        assertEq(proposalIds.length, 15);

        vm.roll(110);

        // screening period votes
        _vote(_tokenHolder2, proposalIds[0], 1, 100);
        _vote(_tokenHolder3, proposalIds[1], 1, 100);
        _vote(_tokenHolder4, proposalIds[2], 1, 100);
        _vote(_tokenHolder5, proposalIds[3], 1, 100);
        _vote(_tokenHolder6, proposalIds[4], 1, 100);
        _vote(_tokenHolder7, proposalIds[5], 1, 100);
        _vote(_tokenHolder8, proposalIds[6], 1, 100);
        _vote(_tokenHolder9, proposalIds[7], 1, 100);
        _vote(_tokenHolder10, proposalIds[8], 1, 100);
        _vote(_tokenHolder11, proposalIds[9], 1, 100);
        _vote(_tokenHolder12, proposalIds[1], 1, 100);
        _vote(_tokenHolder13, proposalIds[1], 1, 100);
        _vote(_tokenHolder14, proposalIds[5], 1, 100);

        // check topTenProposals array is correct after screening period
        GrowthFund.Proposal[] memory screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        assertEq(screenedProposals.length, 10);
        assertEq(screenedProposals[0].proposalId, proposalIds[1]);
        assertEq(screenedProposals[0].votesReceived, 150_000_000 * 1e18);

        assertEq(screenedProposals[1].proposalId, proposalIds[5]);
        assertEq(screenedProposals[1].votesReceived, 100_000_000 * 1e18);

        // skip time to move from screening period to funding period
        vm.roll(100_000);

        // tokenHolder2 partialy votes in support of funded proposal 1
        _fundingVote(_tokenHolder2, screenedProposals[0].proposalId, 1, 2 * 1e18, 100);

        // check proposal state
        (uint256 proposalId, uint256 distributionId, uint256 votesReceived, int256 tokensRequested, int256 fundingReceived, bool succeeded, bool executed) = _growthFund.getProposalInfo(screenedProposals[0].proposalId);
        assertEq(proposalId, proposalIds[1]);
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
        _fundingVote(_tokenHolder2, screenedProposals[1].proposalId, 0, -25 * 1e18, 100);

        (proposalId, distributionId, votesReceived, tokensRequested, fundingReceived, succeeded, executed) = _growthFund.getProposalInfo(screenedProposals[1].proposalId);
        assertEq(proposalId, proposalIds[5]);
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
        _fundingVote(_tokenHolder3, screenedProposals[2].proposalId, 1, 7 * 1e18, 100);

        (proposalId, distributionId, votesReceived, tokensRequested, fundingReceived, succeeded, executed) = _growthFund.getProposalInfo(screenedProposals[2].proposalId);
        assertEq(proposalId, proposalIds[6]);
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

        // TODO: execute the two successful proposals
        // _growthFund.execute(ajnaTokenTargets, values, proposalCalldata, keccak256(bytes(description)));

    }

    function testStartNewDistributionPeriod() external {
        uint256 currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 0);

        _startDistributionPeriod();
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
