// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../src/AjnaToken.sol";
import "../src/GrantFund.sol";
import "../src/interfaces/IStandardFunding.sol";
import "../src/base/Funding.sol";

import "./GrantFundTestHelper.sol";

import "@oz/governance/IGovernor.sol";
import "@oz/governance/utils/IVotes.sol";
import "@oz/utils/math/SafeCast.sol";
import "@std/StdJson.sol";
import "@std/Test.sol";

contract StandardFundingGrantFundTest is GrantFundTestHelper {

    // used to cast 256 to uint64 to match emit expectations
    using SafeCast for uint256;
    using stdJson for string;

    AjnaToken          internal  _token;
    IVotes             internal  _votingToken;
    GrantFund         internal  _grantFund;

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

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _grantFund = new GrantFund(_votingToken);

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

        // initial minter distributes treasury to grantFund
        _token.transfer(address(_grantFund), 500_000_000 * 1e18);
    }

    /*************/
    /*** Tests ***/
    /*************/

    function testGetVotingPowerScreeningStage() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        // check voting power before screening stage has started
        vm.roll(50);

        uint256 votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Screening");
        assertEq(votingPower, 0);

        // skip forward 50 blocks to ensure voters made it into the voting power snapshot
        vm.roll(100);

        // start distribution period
        _startDistributionPeriod(_grantFund);

        // check voting power
        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Screening");
        assertEq(votingPower, 50_000_000 * 1e18);

        // check voting power won't change with token transfer to an address that didn't make it into the snapshot
        address nonVotingAddress = makeAddr("nonVotingAddress");
        changePrank(_tokenHolder1);
        _token.transfer(nonVotingAddress, 10_000_000 * 1e18);

        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Screening");
        assertEq(votingPower, 50_000_000 * 1e18);
        votingPower = _grantFund.getVotesWithParams(nonVotingAddress, block.number, "Screening");
        assertEq(votingPower, 0);
    }

    function testGetVotingPowerFundingStage() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(50);

        // start distribution period
        _startDistributionPeriod(_grantFund);

        // TODO: a single proposal is submitted and screened

        // skip forward to the funding stage
        vm.roll(600_000);

        // check initial voting power
        uint256 votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Funding");
        assertEq(votingPower, 2_500_000_000_000_000 * 1e18);

        // check voting power won't change with token transfer to an address that didn't make it into the snapshot
        address nonVotingAddress = makeAddr("nonVotingAddress");
        changePrank(_tokenHolder1);
        _token.transfer(nonVotingAddress, 10_000_000 * 1e18);

        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Funding");
        assertEq(votingPower, 2_500_000_000_000_000 * 1e18);
        votingPower = _grantFund.getVotesWithParams(nonVotingAddress, block.number, "Funding");
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
        _startDistributionPeriod(_grantFund);

        // create and submit proposal
        TestProposal memory proposal = _createProposalStandard(_grantFund, _tokenHolder2, ajnaTokenTargets, values, proposalCalldata, description);

        vm.roll(10);

        // check proposal status
        IGovernor.ProposalState proposalState = _grantFund.state(proposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // check proposal state
        (
            uint256 proposalId,
            uint256 distributionId,
            uint256 votesReceived,
            uint256 tokensRequested,
            int256 fundingReceived,
            bool executed
        ) = _grantFund.getProposalInfo(proposal.proposalId);

        assertEq(proposalId, proposal.proposalId);
        assertEq(distributionId, 1);
        assertEq(votesReceived, 0);
        assertEq(tokensRequested, 1 * 1e18);
        assertEq(fundingReceived, 0);
        assertFalse(executed);

        // check findMechanism identifies it as a standard proposal
        assertEq(_grantFund.findMechanismOfProposal(proposalId), 0);
    }

    function testInvalidProposalCalldata() external {
        // start distribution period
        _startDistributionPeriod(_grantFund);

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
            address(_grantFund),
            proposalTokenAmount
        );

        // generate proposal message
        string memory description = "Proposal for Ajna token burn from the growth fund";

        // create proposal should revert since invalid burn operation was attempted
        vm.expectRevert(Funding.InvalidSignature.selector);
        _grantFund.proposeStandard(targets, values, proposalCalldata, description);
    }

    function testInvalidProposalTarget() external {
        // start distribution period
        _startDistributionPeriod(_grantFund);

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
        vm.expectRevert(Funding.InvalidTarget.selector);
        _grantFund.proposeStandard(targets, values, proposalCalldata, description);
    }

    function testHasVoted() external {
        // TODO: FINISH IMPLEMENTING
    }

    function testMaximumQuarterlyDistribution() external {
        uint256 maximumQuarterlyDistribution = _grantFund.maximumQuarterlyDistribution();

        // distribution should be 2% of starting amount (500_000_000), or 10_000_000
        assertEq(maximumQuarterlyDistribution, 10_000_000 * 1e18);
    }

    /**
     *  @notice 14 voters consider 18 different proposals. 10 Make it through to the funding stage.
     */
    function testScreenProposalsCheckSorting() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(150);

        // start distribution period
        _startDistributionPeriod(_grantFund);
        uint256 distributionId = _grantFund.getDistributionId();

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

        TestProposal[] memory testProposals = _createNProposals(_grantFund, _token, testProposalParams);

        // TODO: why was this 300 necessary?
        emit log_uint(_grantFund.proposalDeadline(testProposals[0].proposalId));
        emit log_uint(block.number);
        vm.roll(300);

        // screen proposals
        _vote(_grantFund, _tokenHolder1, testProposals[0].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder2, testProposals[1].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder3, testProposals[2].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder4, testProposals[3].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder5, testProposals[4].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder6, testProposals[5].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder7, testProposals[6].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder8, testProposals[7].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder9, testProposals[8].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder10, testProposals[9].proposalId, voteYes, 100);

        // check top ten proposals
        GrantFund.Proposal[] memory screenedProposals = _grantFund.getTopTenProposals(distributionId);
        assertEq(screenedProposals.length, 10);

        // one of the non-current top 10 is moved up to the top spot
        _vote(_grantFund, _tokenHolder11, testProposals[10].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder12, testProposals[10].proposalId, voteYes, 100);

        screenedProposals = _grantFund.getTopTenProposals(distributionId);
        assertEq(screenedProposals.length, 10);
        assertEq(screenedProposals[0].proposalId, testProposals[10].proposalId);
        assertEq(screenedProposals[0].votesReceived, 100_000_000 * 1e18);

        // another non-current top ten is moved up to the top spot
        _vote(_grantFund, _tokenHolder13, testProposals[11].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder14, testProposals[11].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder15, testProposals[11].proposalId, voteYes, 100);

        screenedProposals = _grantFund.getTopTenProposals(distributionId);
        assertEq(screenedProposals.length, 10);
        assertEq(screenedProposals[0].proposalId, testProposals[11].proposalId);
        assertEq(screenedProposals[0].votesReceived, 150_000_000 * 1e18);
        assertEq(screenedProposals[1].proposalId, testProposals[10].proposalId);
        assertEq(screenedProposals[1].votesReceived, 100_000_000 * 1e18);

        // should revert if voter attempts to cast a screeningVote twice
        changePrank(_tokenHolder15);
        vm.expectRevert(Funding.AlreadyVoted.selector);
        _grantFund.castVote(testProposals[11].proposalId, voteYes);
    }

    function testStartNewDistributionPeriod() external {
        uint256 currentDistributionId = _grantFund.getDistributionId();
        assertEq(currentDistributionId, 0);

        _startDistributionPeriod(_grantFund);
        currentDistributionId = _grantFund.getDistributionId();
        assertEq(currentDistributionId, 1);

        (uint256 id, uint256 votesCast, uint256 startBlock, uint256 endBlock, ) = _grantFund.getDistributionPeriodInfo(currentDistributionId);
        assertEq(id, currentDistributionId);
        assertEq(votesCast, 0);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + 648000);

        // check a new distribution period can't be started if already active
        vm.expectRevert(IStandardFunding.DistributionPeriodStillActive.selector);
        _grantFund.startNewDistributionPeriod();

        // skip forward past the end of the distribution period to allow starting anew
        vm.roll(650_000);

        _startDistributionPeriod(_grantFund);
        currentDistributionId = _grantFund.getDistributionId();
        assertEq(currentDistributionId, 2);
    }

    /**
     *  @notice Integration test of 7 proposals submitted, with 6 passing the screening stage. Five potential funding slates are tested.
     *  @dev    Maximum quarterly distribution is 10_000_000.
     *  @dev    Funded slate is executed.
     *  @dev    Reverts:
     *              - IStandardFunding.InsufficientBudget
     *              - IStandardFunding.ExecuteProposalInvalid
     *              - "Governor: proposal not successful"
     */
    function testDistributionPeriodEndToEnd() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(150);

        // start distribution period
        _startDistributionPeriod(_grantFund);

        uint256 distributionId = _grantFund.getDistributionId();

        TestProposalParams[] memory testProposalParams = new TestProposalParams[](7);
        testProposalParams[0] = TestProposalParams(_tokenHolder1, 9_000_000 * 1e18);
        testProposalParams[1] = TestProposalParams(_tokenHolder2, 20_000_000 * 1e18);
        testProposalParams[2] = TestProposalParams(_tokenHolder3, 5_000_000 * 1e18);
        testProposalParams[3] = TestProposalParams(_tokenHolder4, 5_000_000 * 1e18);
        testProposalParams[4] = TestProposalParams(_tokenHolder5, 50_000 * 1e18);
        testProposalParams[5] = TestProposalParams(_tokenHolder6, 100_000 * 1e18);
        testProposalParams[6] = TestProposalParams(_tokenHolder7, 100_000 * 1e18);

        // create 7 proposals paying out tokens
        TestProposal[] memory testProposals = _createNProposals(_grantFund, _token, testProposalParams);
        assertEq(testProposals.length, 7);

        vm.roll(200);

        // screening period votes
        _vote(_grantFund, _tokenHolder1, testProposals[0].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder2, testProposals[0].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder3, testProposals[1].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder4, testProposals[1].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder5, testProposals[2].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder6, testProposals[2].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder7, testProposals[3].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder8, testProposals[0].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder9, testProposals[4].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder10, testProposals[5].proposalId, voteYes, 100);

        // skip time to move from screening period to funding period
        vm.roll(600_000);

        // check topTenProposals array is correct after screening period - only four should have advanced
        GrantFund.Proposal[] memory screenedProposals = _grantFund.getTopTenProposals(distributionId);
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
        _fundingVote(_grantFund, _tokenHolder1, screenedProposals[0].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);
        screenedProposals = _grantFund.getTopTenProposals(distributionId);
        _fundingVote(_grantFund, _tokenHolder2, screenedProposals[1].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);
        screenedProposals = _grantFund.getTopTenProposals(distributionId);
        _fundingVote(_grantFund, _tokenHolder3, screenedProposals[2].proposalId, voteYes, 1_250_000_000_000_000 * 1e18);
        screenedProposals = _grantFund.getTopTenProposals(distributionId);
        _fundingVote(_grantFund, _tokenHolder3, screenedProposals[4].proposalId, voteYes, 1_250_000_000_000_000 * 1e18);
        screenedProposals = _grantFund.getTopTenProposals(distributionId);
        _fundingVote(_grantFund, _tokenHolder4, screenedProposals[3].proposalId, voteYes, 2_000_000_000_000_000 * 1e18);
        screenedProposals = _grantFund.getTopTenProposals(distributionId);
        _fundingVote(_grantFund, _tokenHolder4, screenedProposals[5].proposalId, voteNo, -500_000_000_000_000 * 1e18);
        screenedProposals = _grantFund.getTopTenProposals(distributionId);

        vm.expectRevert(IStandardFunding.InsufficientBudget.selector);
        _grantFund.castVoteWithReasonAndParams(screenedProposals[3].proposalId, 1, "", abi.encode(2_500_000_000_000_000 * 1e18));

        // check tokerHolder partial vote budget calculations
        _fundingVote(_grantFund, _tokenHolder5, screenedProposals[5].proposalId, voteNo, -500_000_000_000_000 * 1e18);
        screenedProposals = _grantFund.getTopTenProposals(distributionId);

        // check remaining votes available to the above token holders
        (uint256 voterWeight, int256 budgetRemaining) = _grantFund.getVoterInfo(distributionId, _tokenHolder1);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        (voterWeight, budgetRemaining) = _grantFund.getVoterInfo(distributionId, _tokenHolder2);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        (voterWeight, budgetRemaining) = _grantFund.getVoterInfo(distributionId, _tokenHolder3);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        (voterWeight, budgetRemaining) = _grantFund.getVoterInfo(distributionId, _tokenHolder4);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 0);
        assertEq(uint256(budgetRemaining), _grantFund.getVotesWithParams(_tokenHolder4, block.number, bytes("Funding")));
        (voterWeight, budgetRemaining) = _grantFund.getVoterInfo(distributionId, _tokenHolder5);
        assertEq(voterWeight, 2_500_000_000_000_000 * 1e18);
        assertEq(budgetRemaining, 2_000_000_000_000_000 * 1e18);
        assertEq(uint256(budgetRemaining), _grantFund.getVotesWithParams(_tokenHolder5, block.number, bytes("Funding")));

        // skip to the DistributionPeriod
        vm.roll(650_000);

        GrantFund.Proposal[] memory potentialProposalSlate = new GrantFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[0];
        potentialProposalSlate[1] = screenedProposals[1];

        // ensure checkSlate won't allow exceeding the GBC
        bool validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);
        (, , , , bytes32 slateHash1) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash1, 0);

        // ensure checkSlate will allow a valid slate
        potentialProposalSlate = new GrantFund.Proposal[](1);
        potentialProposalSlate[0] = screenedProposals[3];
        vm.expectEmit(true, true, false, true);
        emit FundedSlateUpdated(distributionId, _grantFund.getSlateHash(potentialProposalSlate));
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , bytes32 slateHash2) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash2, 0x8546b85d326f37e382f7191b8634030f1a99e83e5fffee168d362bdd80cb0ee7);
        // check funded proposal slate matches expected state
        GrantFund.Proposal[] memory fundedProposalSlate = _grantFund.getFundedProposalSlate(distributionId, slateHash2);
        assertEq(fundedProposalSlate.length, 1);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[3].proposalId);

        // ensure checkSlate will update the currentSlateHash when a superior slate is presented
        potentialProposalSlate = new GrantFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[3];
        potentialProposalSlate[1] = screenedProposals[4];
        vm.expectEmit(true, true, false, true);
        emit FundedSlateUpdated(distributionId, _grantFund.getSlateHash(potentialProposalSlate));
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , bytes32 slateHash3) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash3, 0xc62d17691538dd00f228329f7b485088e3a4853db966dd6e7becc975d3e00442);
        // check funded proposal slate matches expected state
        fundedProposalSlate = _grantFund.getFundedProposalSlate(distributionId, slateHash3);
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[3].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // ensure an additional update can be made to the optimized slate
        potentialProposalSlate = new GrantFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[0];
        potentialProposalSlate[1] = screenedProposals[4];
        vm.expectEmit(true, true, false, true);
        emit FundedSlateUpdated(distributionId, _grantFund.getSlateHash(potentialProposalSlate));
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , bytes32 slateHash4) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash4, 0xfa74749b75fb2b65ee0f757da034d5c89dc50efef96ce210ac70ee479a631006);
        // check funded proposal slate matches expected state
        fundedProposalSlate = _grantFund.getFundedProposalSlate(distributionId, slateHash4);
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[0].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // check that a different slate which distributes more tokens (less than gbc), but has less votes won't pass
        potentialProposalSlate = new GrantFund.Proposal[](2);
        potentialProposalSlate[0] = screenedProposals[2];
        potentialProposalSlate[1] = screenedProposals[3];
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);
        // check funded proposal slate wasn't updated
        fundedProposalSlate = _grantFund.getFundedProposalSlate(distributionId, slateHash4);
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[0].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // check can't execute proposals prior to the end of the challenge period
        vm.expectRevert(IStandardFunding.ExecuteProposalInvalid.selector);
        _grantFund.executeStandard(testProposals[0].targets, testProposals[0].values, testProposals[0].calldatas, keccak256(bytes(testProposals[0].description)));

        // skip to the end of the DistributionPeriod
        vm.roll(700_000);

        // execute funded proposals
        _executeProposal(_grantFund, _token, testProposals[0]);
        _executeProposal(_grantFund, _token, testProposals[4]);

        // check that shouldn't be able to execute unfunded proposals
        vm.expectRevert("Governor: proposal not successful");
        _grantFund.executeStandard(testProposals[1].targets, testProposals[1].values, testProposals[1].calldatas, keccak256(bytes(testProposals[1].description)));

        // check that shouldn't be able to execute a proposal twice
        vm.expectRevert("Governor: proposal not successful");
        _grantFund.executeStandard(testProposals[0].targets, testProposals[0].values, testProposals[0].calldatas, keccak256(bytes(testProposals[0].description)));
    }

}
