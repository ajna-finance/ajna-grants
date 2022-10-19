// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { AjnaToken } from "../src/AjnaToken.sol";
import { GrowthFund } from "../src/GrowthFund.sol";
import { IGrowthFund } from "../src/interfaces/IGrowthFund.sol";

import { SigUtils } from "./utils/SigUtils.sol";
import { GrowthFundTestHelper } from "./GrowthFundTestHelper.sol";

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { stdJson } from "@std/StdJson.sol";

contract GrowthFundTest is GrowthFundTestHelper {

    // used to cast 256 to uint64 to match emit expectations
    using SafeCast for uint256;
    using stdJson for string;

    AjnaToken          internal  _token;
    IVotes             internal  _votingToken;
    GrowthFund         internal  _growthFund;
    SigUtils           internal  _sigUtils;

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
    address internal _tokenHolder15   = makeAddr("_tokenHolder15");

    address[] internal _selfDelegatedVotersArr = [
        _tokenHolder1,
        _tokenHolder2,
        _tokenHolder3,
        _tokenHolder4,
        _tokenHolder5,
        _tokenHolder6,
        _tokenHolder7,
        _tokenHolder8,
        _tokenHolder9,
        _tokenHolder10,
        _tokenHolder11,
        _tokenHolder12,
        _tokenHolder13,
        _tokenHolder14,
        _tokenHolder15
    ];

    uint256 _initialAjnaTokenSupply   = 2_000_000_000 * 1e18;

    function setUp() external {
        vm.startPrank(_tokenDeployer);
        _token = new AjnaToken(_tokenDeployer);

        _sigUtils = new SigUtils(_token.DOMAIN_SEPARATOR());

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _growthFund = new GrowthFund(_votingToken);

        // TODO: replace with for loop -> test address initializer method that created array and transfers tokens given n?
        // initial minter distributes tokens to test addresses
        changePrank(_tokenDeployer);
        _token.transfer(_tokenHolder1, 50_000_000 * 1e18);
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
        _token.transfer(_tokenHolder15, 50_000_000 * 1e18);

        // initial minter distributes treasury to growthFund
        _token.transfer(address(_growthFund), 500_000_000 * 1e18);
    }

    /*************/
    /*** Tests ***/
    /*************/

    function testGetVotingPowerScreeningStage() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        // check voting power before screening stage has started
        vm.roll(50);

        uint256 votingPower = _growthFund.getVotesWithParams(_tokenHolder1, block.number, "Screening");
        assertEq(votingPower, 0);

        // skip forward 50 blocks to ensure voters made it into the voting power snapshot
        vm.roll(100);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // check voting power
        votingPower = _growthFund.getVotesWithParams(_tokenHolder1, block.number, "Screening");
        assertEq(votingPower, 50_000_000 * 1e18);

        // check voting power won't change with token transfer to an address that didn't make it into the snapshot
        address nonVotingAddress = makeAddr("nonVotingAddress");
        changePrank(_tokenHolder1);
        _token.transfer(nonVotingAddress, 10_000_000 * 1e18);

        votingPower = _growthFund.getVotesWithParams(_tokenHolder1, block.number, "Screening");
        assertEq(votingPower, 50_000_000 * 1e18);
        votingPower = _growthFund.getVotesWithParams(nonVotingAddress, block.number, "Screening");
        assertEq(votingPower, 0);
    }

    function testGetVotingPowerFundingStage() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(50);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // TODO: a single proposal is submitted and screened

        // skip forward to the funding stage
        vm.roll(600_000);

        // check initial voting power
        uint256 votingPower = _growthFund.getVotesWithParams(_tokenHolder1, block.number, "Funding");
        assertEq(votingPower, 2_500_000_000_000_000 * 1e18);

        // check voting power won't change with token transfer to an address that didn't make it into the snapshot
        address nonVotingAddress = makeAddr("nonVotingAddress");
        changePrank(_tokenHolder1);
        _token.transfer(nonVotingAddress, 10_000_000 * 1e18);

        votingPower = _growthFund.getVotesWithParams(_tokenHolder1, block.number, "Funding");
        assertEq(votingPower, 2_500_000_000_000_000 * 1e18);
        votingPower = _growthFund.getVotesWithParams(nonVotingAddress, block.number, "Funding");
        assertEq(votingPower, 0);

        // TODO: check voting power decreases with funding votes cast -> will need to generate single test proposal
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

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // create and submit proposal
        TestProposal memory proposal = _createProposal(_growthFund, _tokenHolder2, ajnaTokenTargets, values, proposalCalldata, description);

        vm.roll(10);

        // check proposal status
        IGovernor.ProposalState proposalState = _growthFund.state(proposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // check proposal state
        (
            uint256 proposalId,
            uint256 distributionId,
            uint256 votesReceived,
            uint256 tokensRequested,
            int256 fundingReceived,
            bool succeeded,
            bool executed
        ) = _growthFund.getProposalInfo(proposal.proposalId);

        assertEq(proposalId, proposal.proposalId);
        assertEq(distributionId, 1);
        assertEq(votesReceived, 0);
        assertEq(tokensRequested, 1 * 1e18);
        assertEq(fundingReceived, 0);
        assertEq(succeeded, false);
        assertEq(executed, false);
    }

    function testInvalidProposal() external {
        // generate proposal targets
        address[] memory targets = new address[](2);
        targets[0] = _tokenHolder1;
        targets[1] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            1 * 1e18
        );

        // generate proposal message
        string memory description = "Proposal for Ajna token transfer to tester address";

        // create proposal should revert since multiple targets were listed
        vm.expectRevert(IGrowthFund.InvalidProposal.selector);
        _growthFund.propose(targets, values, proposalCalldata, description);
    }

    function testInvalidProposalCalldata() external {
        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        uint256 proposalTokenAmount = 1 * 1e18;
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "burn(address,uint256)",
            address(_growthFund),
            proposalTokenAmount
        );

        // generate proposal message
        string memory description = "Proposal for Ajna token burn from the growth fund";

        // create proposal should revert since invalid burn operation was attempted
        vm.expectRevert(IGrowthFund.InvalidSignature.selector);
        _growthFund.propose(targets, values, proposalCalldata, description);
    }

    function testInvalidProposalTarget() external {
        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = _tokenHolder1;

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            1 * 1e18
        );

        // generate proposal message
        string memory description = "Proposal for Ajna token transfer to tester address";

        // create proposal should revert since a non Ajna token contract target was used
        vm.expectRevert(IGrowthFund.InvalidTarget.selector);
        _growthFund.propose(targets, values, proposalCalldata, description);
    }

    function testMaximumQuarterlyDistribution() external {
        uint256 maximumQuarterlyDistribution = _growthFund.maximumQuarterlyDistribution();

        // distribution should be 2% of starting amount (500_000_000), or 10_000_000
        assertEq(maximumQuarterlyDistribution, 10_000_000 * 1e18);
    }

    // TODO: check negative votes - second fixture?
    /**
     *  @notice 14 voters consider 18 different proposals. 10 Make it through to the funding stage.
     */
    function testScreenProposalsCheckSorting() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(150);

        // start distribution period
        _startDistributionPeriod(_growthFund);
        uint256 distributionId = _growthFund.getDistributionId();

        vm.roll(200);

        TestProposalParams[] memory testProposalParams = new TestProposalParams[](15);
        testProposalParams[0] = TestProposalParams(_tokenHolder1, 9_000_000 * 1e18);
        testProposalParams[1] = TestProposalParams(_tokenHolder2, 20_000_000 * 1e18);
        testProposalParams[2] = TestProposalParams(_tokenHolder3, 5_000_000 * 1e18);
        testProposalParams[3] = TestProposalParams(_tokenHolder4, 5_000_000 * 1e18);
        testProposalParams[4] = TestProposalParams(_tokenHolder5, 50_000 * 1e18);
        testProposalParams[5] = TestProposalParams(_tokenHolder6, 100_000 * 1e18);
        testProposalParams[6] = TestProposalParams(_tokenHolder7, 100_000 * 1e18);
        testProposalParams[7] = TestProposalParams(_tokenHolder8, 100_000 * 1e18);
        testProposalParams[8] = TestProposalParams(_tokenHolder9, 100_000 * 1e18);
        testProposalParams[9] = TestProposalParams(_tokenHolder10, 100_000 * 1e18);
        testProposalParams[10] = TestProposalParams(_tokenHolder11, 100_000 * 1e18);
        testProposalParams[11] = TestProposalParams(_tokenHolder12, 100_000 * 1e18);
        testProposalParams[12] = TestProposalParams(_tokenHolder13, 100_000 * 1e18);
        testProposalParams[13] = TestProposalParams(_tokenHolder14, 100_000 * 1e18);

        TestProposal[] memory testProposals = _createNProposals(_growthFund, _token, testProposalParams);

        // TODO: why was this 300 necessary?
        emit log_uint(_growthFund.proposalDeadline(testProposals[0].proposalId));
        emit log_uint(block.number);
        vm.roll(300);

        // screen proposals
        _vote(_growthFund, _tokenHolder1, testProposals[0].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder2, testProposals[1].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder3, testProposals[2].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder4, testProposals[3].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder5, testProposals[4].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder6, testProposals[5].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder7, testProposals[6].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder8, testProposals[7].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder9, testProposals[8].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder10, testProposals[9].proposalId, voteYes, 100);

        // check top ten proposals
        GrowthFund.Proposal[] memory screenedProposals = _growthFund.getTopTenProposals(distributionId);
        assertEq(screenedProposals.length, 10);

        // one of the non-current top 10 is moved up to the top spot
        _vote(_growthFund, _tokenHolder11, testProposals[10].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder12, testProposals[10].proposalId, voteYes, 100);

        screenedProposals = _growthFund.getTopTenProposals(distributionId);
        assertEq(screenedProposals.length, 10);
        assertEq(screenedProposals[0].proposalId, testProposals[10].proposalId);
        assertEq(screenedProposals[0].votesReceived, 100_000_000 * 1e18);

        // another non-current top ten is moved up to the top spot
        _vote(_growthFund, _tokenHolder13, testProposals[11].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder14, testProposals[11].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder15, testProposals[11].proposalId, voteYes, 100);

        screenedProposals = _growthFund.getTopTenProposals(distributionId);
        assertEq(screenedProposals.length, 10);
        assertEq(screenedProposals[0].proposalId, testProposals[11].proposalId);
        assertEq(screenedProposals[0].votesReceived, 150_000_000 * 1e18);
        assertEq(screenedProposals[1].proposalId, testProposals[10].proposalId);
        assertEq(screenedProposals[1].votesReceived, 100_000_000 * 1e18);

        // should revert if voter attempts to cast a screeningVote twice
        changePrank(_tokenHolder15);
        vm.expectRevert(IGrowthFund.AlreadyVoted.selector);
        _growthFund.castVote(testProposals[11].proposalId, voteYes);
    }

    function testStartNewDistributionPeriod() external {
        uint256 currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 0);

        _startDistributionPeriod(_growthFund);
        currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 1);

        (uint256 id, uint256 votesCast, uint256 startBlock, uint256 endBlock, ) = _growthFund.getDistributionPeriodInfo(currentDistributionId);
        assertEq(id, currentDistributionId);
        assertEq(votesCast, 0);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + _growthFund.DISTRIBUTION_PERIOD_LENGTH());

        // check a new distribution period can't be started if already active
        vm.expectRevert(IGrowthFund.DistributionPeriodStillActive.selector);
        _growthFund.startNewDistributionPeriod();

        // skip forward past the end of the distribution period to allow starting anew
        vm.roll(650_000);

        _startDistributionPeriod(_growthFund);
        currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 2);
    }

    /**
     *  @notice Integration test of 7 proposals submitted, with 6 passing the screening stage. Five potential funding slates are tested.
     *  @dev    Maximum quarterly distribution is 10_000_000.
     *  @dev    Funded slate is executed.
     *  @dev    Reverts:
     *              - IGrowthFund.InsufficientBudget
     *              - IGrowthFund.ProposalNotFunded
     *              - IGrowthFund.ExecuteProposalInvalid
     */
    function testDistributionPeriodEndToEnd() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(150);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        uint256 distributionId = _growthFund.getDistributionId();

        TestProposalParams[] memory testProposalParams = new TestProposalParams[](7);
        testProposalParams[0] = TestProposalParams(_tokenHolder1, 9_000_000 * 1e18);
        testProposalParams[1] = TestProposalParams(_tokenHolder2, 20_000_000 * 1e18);
        testProposalParams[2] = TestProposalParams(_tokenHolder3, 5_000_000 * 1e18);
        testProposalParams[3] = TestProposalParams(_tokenHolder4, 5_000_000 * 1e18);
        testProposalParams[4] = TestProposalParams(_tokenHolder5, 50_000 * 1e18);
        testProposalParams[5] = TestProposalParams(_tokenHolder6, 100_000 * 1e18);
        testProposalParams[6] = TestProposalParams(_tokenHolder7, 100_000 * 1e18);

        // create 7 proposals paying out tokens
        TestProposal[] memory testProposals = _createNProposals(_growthFund, _token, testProposalParams);
        assertEq(testProposals.length, 7);

        vm.roll(200);

        // screening period votes
        _vote(_growthFund, _tokenHolder1, testProposals[0].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder2, testProposals[0].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder3, testProposals[1].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder4, testProposals[1].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder5, testProposals[2].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder6, testProposals[2].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder7, testProposals[3].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder8, testProposals[0].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder9, testProposals[4].proposalId, voteYes, 100);
        _vote(_growthFund, _tokenHolder10, testProposals[5].proposalId, voteYes, 100);

        // skip time to move from screening period to funding period
        vm.roll(600_000);

        // check topTenProposals array is correct after screening period - only four should have advanced
        GrowthFund.Proposal[] memory screenedProposals = _growthFund.getTopTenProposals(distributionId);
        assertEq(screenedProposals.length, 6);
        assertEq(screenedProposals[0].proposalId, testProposals[0].proposalId);
        assertEq(screenedProposals[0].votesReceived, 150_000_000 * 1e18);
        assertEq(screenedProposals[1].proposalId, testProposals[1].proposalId);
        assertEq(screenedProposals[1].votesReceived, 100_000_000 * 1e18);
        assertEq(screenedProposals[2].proposalId, testProposals[2].proposalId);
        assertEq(screenedProposals[2].votesReceived, 100_000_000 * 1e18);
        assertEq(screenedProposals[3].proposalId, testProposals[3].proposalId);
        assertEq(screenedProposals[3].votesReceived, 50_000_000 * 1e18);
        assertEq(screenedProposals[4].proposalId, testProposals[4].proposalId);
        assertEq(screenedProposals[4].votesReceived, 50_000_000 * 1e18);
        assertEq(screenedProposals[5].proposalId, testProposals[5].proposalId);
        assertEq(screenedProposals[5].votesReceived, 50_000_000 * 1e18);

        // funding period votes for two competing slates, 1, or 2 and 3
        _fundingVote(_growthFund, _tokenHolder1, screenedProposals[0].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(distributionId);
        _fundingVote(_growthFund, _tokenHolder2, screenedProposals[1].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(distributionId);
        _fundingVote(_growthFund, _tokenHolder3, screenedProposals[2].proposalId, voteYes, 1_250_000_000_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(distributionId);
        _fundingVote(_growthFund, _tokenHolder3, screenedProposals[4].proposalId, voteYes, 1_250_000_000_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(distributionId);
        _fundingVote(_growthFund, _tokenHolder4, screenedProposals[3].proposalId, voteYes, 2_000_000_000_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(distributionId);
        _fundingVote(_growthFund, _tokenHolder4, screenedProposals[5].proposalId, voteNo, -500_000_000_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(distributionId);

        vm.expectRevert(IGrowthFund.InsufficientBudget.selector);
        _growthFund.castVoteWithReasonAndParams(screenedProposals[3].proposalId, 1, "", abi.encode(2_500_000_000_000_000 * 1e18));

        // check tokerHolder partial vote budget calculations
        _fundingVote(_growthFund, _tokenHolder5, screenedProposals[5].proposalId, voteNo, -500_000_000_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(distributionId);

        // check remaining votes available to the above token holders
        (uint256 voterWeight, int256 budgetRemaining) = _growthFund.getVoterInfo(distributionId, _tokenHolder1);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        (voterWeight, budgetRemaining) = _growthFund.getVoterInfo(distributionId, _tokenHolder2);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        (voterWeight, budgetRemaining) = _growthFund.getVoterInfo(distributionId, _tokenHolder3);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        (voterWeight, budgetRemaining) = _growthFund.getVoterInfo(distributionId, _tokenHolder4);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        assertEq(uint256(budgetRemaining), _growthFund.getVotesWithParams(_tokenHolder4, block.number, bytes("Funding")));
        (voterWeight, budgetRemaining) = _growthFund.getVoterInfo(distributionId, _tokenHolder5);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 2_000_000_000_000_000 * 1e18);
        assertEq(uint256(budgetRemaining), _growthFund.getVotesWithParams(_tokenHolder5, block.number, bytes("Funding")));

        // skip to the DistributionPeriod
        vm.roll(650_000);

        GrowthFund.Proposal[] memory potentialProposalSlate = new GrowthFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[0];
        potentialProposalSlate[1] = screenedProposals[1];

        // ensure checkSlate won't allow exceeding the GBC
        bool validSlate = _growthFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);
        (, , , , bytes32 slateHash1) = _growthFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash1, 0);

        // ensure checkSlate will allow a valid slate
        potentialProposalSlate = new GrowthFund.Proposal[](1);
        potentialProposalSlate[0] = screenedProposals[3];
        validSlate = _growthFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , bytes32 slateHash2) = _growthFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash2, 0x66add00dcf55b40812c015cb43f6448e193756eb92a1bad6ccdf330bdf247d07);
        // check funded proposal slate matches expected state
        GrowthFund.Proposal[] memory fundedProposalSlate = _growthFund.getFundedProposalSlate(distributionId, slateHash2);
        assertEq(fundedProposalSlate.length, 1);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[3].proposalId);

        // ensure checkSlate will update the currentSlateHash when a superior slate is presented
        potentialProposalSlate = new GrowthFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[3];
        potentialProposalSlate[1] = screenedProposals[4];
        validSlate = _growthFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , bytes32 slateHash3) = _growthFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash3, 0x7bcdbd18e8ffe0a1ca31429dd71072cb9455bf1135902f06c2154a8729dfcfc4);
        // check funded proposal slate matches expected state
        fundedProposalSlate = _growthFund.getFundedProposalSlate(distributionId, slateHash3);
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[3].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // ensure an additional update can be made to the optimized slate
        potentialProposalSlate = new GrowthFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[0];
        potentialProposalSlate[1] = screenedProposals[4];
        validSlate = _growthFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , bytes32 slateHash4) = _growthFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash4, 0x6a0dd1a8da53d04b863aed7ff5c62423d7d05eeb956899bf7679b79e68464d28);
        // check funded proposal slate matches expected state
        fundedProposalSlate = _growthFund.getFundedProposalSlate(distributionId, slateHash4);
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[0].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // check that a different slate which distributes more tokens (less than gbc), but has less votes won't pass
        potentialProposalSlate = new GrowthFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[2];
        potentialProposalSlate[1] = screenedProposals[3];
        validSlate = _growthFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);
        // check funded proposal slate wasn't updated
        fundedProposalSlate = _growthFund.getFundedProposalSlate(distributionId, slateHash4);
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[0].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // skip to the end of the DistributionPeriod
        vm.roll(700_000);

        // execute funded proposals
        _executeProposal(_growthFund, _token, testProposals[0]);
        _executeProposal(_growthFund, _token, testProposals[4]);

        // check that shouldn't be able to execute unfunded proposals
        vm.expectRevert(IGrowthFund.ProposalNotFunded.selector);
        _growthFund.execute(testProposals[1].targets, testProposals[1].values, testProposals[1].calldatas, keccak256(bytes(testProposals[1].description)));

        // check that shouldn't be able to execute a proposal twice
        vm.expectRevert(IGrowthFund.ExecuteProposalInvalid.selector);
        _growthFund.execute(testProposals[0].targets, testProposals[0].values, testProposals[0].calldatas, keccak256(bytes(testProposals[0].description)));
    }

    // TODO: finish implementing
    function xtestSlateHash() external {
        IGrowthFund.Proposal[] memory proposals = _loadProposalSlateJSON("/test/fixtures/FundedSlate.json");

        bytes32 slateHash = _growthFund.getSlateHash(proposals);
        assertEq(slateHash, 0x782d39817b3256245278e90dcc253aec40e6834480269e4442be665f6f2944a9);

        // check a similar slate results in a different hash
    }

}
