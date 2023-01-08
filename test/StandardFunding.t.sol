// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes }    from "@oz/governance/utils/IVotes.sol";
import { SafeCast }  from "@oz/utils/math/SafeCast.sol";

import { Funding }          from "../src/grants/base/Funding.sol";
import { GrantFund }        from "../src/grants/GrantFund.sol";
import { IStandardFunding } from "../src/grants/interfaces/IStandardFunding.sol";
import { Maths }            from "../src/grants/libraries/Maths.sol";

import { GrantFundTestHelper } from "./utils/GrantFundTestHelper.sol";
import { IAjnaToken }          from "./utils/IAjnaToken.sol";

contract StandardFundingGrantFundTest is GrantFundTestHelper {

    // used to cast 256 to uint64 to match emit expectations
    using SafeCast for uint256;

    IAjnaToken        internal  _token;
    IVotes            internal  _votingToken;
    GrantFund         internal  _grantFund;

    // Ajna token Holder at the Ajna contract creation on mainnet
    address internal _tokenDeployer  = 0x666cf594fB18622e1ddB91468309a7E194ccb799;
    address internal _tokenHolder1   = makeAddr("_tokenHolder1");
    address internal _tokenHolder2   = makeAddr("_tokenHolder2");
    address internal _tokenHolder3   = makeAddr("_tokenHolder3");
    address internal _tokenHolder4   = makeAddr("_tokenHolder4");
    address internal _tokenHolder5   = makeAddr("_tokenHolder5");
    address internal _tokenHolder6   = makeAddr("_tokenHolder6");
    address internal _tokenHolder7   = makeAddr("_tokenHolder7");
    address internal _tokenHolder8   = makeAddr("_tokenHolder8");
    address internal _tokenHolder9   = makeAddr("_tokenHolder9");
    address internal _tokenHolder10  = makeAddr("_tokenHolder10");
    address internal _tokenHolder11  = makeAddr("_tokenHolder11");
    address internal _tokenHolder12  = makeAddr("_tokenHolder12");
    address internal _tokenHolder13  = makeAddr("_tokenHolder13");
    address internal _tokenHolder14  = makeAddr("_tokenHolder14");
    address internal _tokenHolder15  = makeAddr("_tokenHolder15");

    address[] internal _votersArr = [
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

    // at this block on mainnet, all ajna tokens belongs to _tokenDeployer
    uint256 internal _startBlock      = 16354861;

    mapping (uint256 => uint256) internal noOfVotesOnProposal;
    uint256[] internal topTenProposalIds;
    uint256[] internal potentialProposalsSlate;
    uint256 treasury = 500_000_000 * 1e18;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), _startBlock);

        vm.startPrank(_tokenDeployer);

        // Ajna Token contract address on mainnet
        _token = IAjnaToken(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079);

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _grantFund = new GrantFund(_votingToken, treasury);

        // initial minter distributes tokens to test addresses
        _transferAjnaTokens(_token, _votersArr, 50_000_000 * 1e18, _tokenDeployer);

        // initial minter distributes treasury to grantFund
        _token.transfer(address(_grantFund), treasury);
    }

    /*************/
    /*** Tests ***/
    /*************/

    function testGetVotingPowerScreeningStage() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 50);

        // start distribution period
        _startDistributionPeriod(_grantFund);

        // check voting power after screening stage has started
        vm.roll(_startBlock + 100);

        uint256 votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Screening");
        assertEq(votingPower, 50_000_000 * 1e18);

        // skip forward 150 blocks and transfer some tokens after voting power was determined
        vm.roll(_startBlock + 150);

        changePrank(_tokenHolder1);
        _token.transfer(_tokenHolder2, 25_000_000 * 1e18);

        // check voting power is unchanged
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
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 50);

        // start distribution period
        _startDistributionPeriod(_grantFund);

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
        TestProposal memory proposal = _createProposalStandard(_grantFund, _tokenHolder1, ajnaTokenTargets, values, proposalCalldata, description);

        // screening period votes
        _vote(_grantFund, _tokenHolder1, proposal.proposalId, voteYes, 1);

        // skip forward to the funding stage
        vm.roll(_startBlock + 600_000);

        // check initial voting power
        uint256 votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Funding");
        assertEq(votingPower, 2_500_000_000_000_000 * 1e18);

        // check voting power won't change with token transfer to an address that didn't make it into the snapshot
        address nonVotingAddress = makeAddr("nonVotingAddress");
        changePrank(_tokenHolder1);
        _token.transfer(nonVotingAddress, 10_000_000 * 1e18);

        votingPower = _grantFund.getVotesWithParams(nonVotingAddress, block.number, "Funding");
        assertEq(votingPower, 0);
        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Funding");
        assertEq(votingPower, 2_500_000_000_000_000 * 1e18);

        _fundingVote(_grantFund, _tokenHolder1, proposal.proposalId, voteYes, 500_000_000_000_000 * 1e18);
        
        // voting power reduced when voted in funding stage
        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Funding");
        assertEq(votingPower, 2_000_000_000_000_000 * 1e18);
    }

    function testPropose() external {
        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        // Eth to transfer is non zero
        values[0] = 1;

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

        changePrank(_tokenHolder2);
        // Should revert if Propose of Governer Contract is called
        vm.expectRevert(Funding.InvalidProposal.selector);
        _grantFund.propose(ajnaTokenTargets, values, proposalCalldata, description);

        // should revert if target array is blank
        vm.expectRevert(Funding.InvalidProposal.selector);
        address[] memory targets;
        _grantFund.proposeStandard(targets, values, proposalCalldata, description);

        // Skips to funding period
        vm.roll(_startBlock + 576_002);
        // should revert to submit proposal
        vm.expectRevert(IStandardFunding.ScreeningPeriodEnded.selector);
        _grantFund.proposeStandard(ajnaTokenTargets, values, proposalCalldata, description);

        vm.roll(_startBlock + 10);

        // should revert if Eth transfer is not zero
        vm.expectRevert(Funding.InvalidValues.selector);
        _grantFund.proposeStandard(ajnaTokenTargets, values, proposalCalldata, description);

        // updating Eth value to transfer to 0
        values[0] = 0;

        // create and submit proposal
        TestProposal memory proposal = _createProposalStandard(_grantFund, _tokenHolder2, ajnaTokenTargets, values, proposalCalldata, description);
        
        // should revert if same proposal is proposed again
        vm.expectRevert(Funding.ProposalAlreadyExists.selector);
        _grantFund.proposeStandard(ajnaTokenTargets, values, proposalCalldata, description);
        
        vm.roll(_startBlock + 10);

        // check proposal status
        IGovernor.ProposalState proposalState = _grantFund.state(proposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // check proposal state
        (
            uint256 proposalId,
            uint256 distributionId,
            uint256 votesReceived,
            uint256 tokensRequested,
            int256 qvBudgetAllocated,
            bool executed
        ) = _grantFund.getProposalInfo(proposal.proposalId);

        assertEq(proposalId, proposal.proposalId);
        assertEq(distributionId, 1);
        assertEq(votesReceived, 0);
        assertEq(tokensRequested, 1 * 1e18);
        assertEq(qvBudgetAllocated, 0);
        assertFalse(executed);

        // should revert to find mechanism with invalid ProposalId
        vm.expectRevert(Funding.ProposalNotFound.selector);
        _grantFund.findMechanismOfProposal(0x223);

        // check findMechanism identifies it as a standard proposal
        assert(_grantFund.findMechanismOfProposal(proposalId) == Funding.FundingMechanism.Standard);
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
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 100);
        // start distribution period
        _startDistributionPeriod(_grantFund);
        _grantFund.getDistributionId();

        vm.roll(_startBlock + 200);

        TestProposalParams[] memory testProposalParams = new TestProposalParams[](2);
        testProposalParams[0] = TestProposalParams(_tokenHolder1, 9_000_000 * 1e18);
        testProposalParams[1] = TestProposalParams(_tokenHolder2, 20_000_000 * 1e18);

        TestProposal[] memory testProposals = _createNProposals(_grantFund, _token, testProposalParams);

        // ensure that user has not voted
        bool hasVoted = _grantFund.hasVoted(testProposals[0].proposalId, _tokenHolder1);
        assertFalse(hasVoted);

        _vote(_grantFund, _tokenHolder1, testProposals[0].proposalId, voteYes, 100);
        // check that user has voted
        hasVoted = _grantFund.hasVoted(testProposals[0].proposalId, _tokenHolder1);
        assertTrue(hasVoted);

        _vote(_grantFund, _tokenHolder2, testProposals[1].proposalId, voteYes, 100);
        hasVoted = _grantFund.hasVoted(testProposals[1].proposalId, _tokenHolder2);
        assertTrue(hasVoted);

        changePrank(_tokenHolder1);

        // Should revert if user tries to vote for two proposals in screening period
        vm.expectRevert(Funding.AlreadyVoted.selector);
        _grantFund.castVote(testProposals[1].proposalId, voteYes);

        // skip to funding period
        vm.roll(_startBlock + 600_000);

        // should be false if user has not voted in funding stage but voted in screening stage
        hasVoted = _grantFund.hasVoted(testProposals[1].proposalId, _tokenHolder1);
        assertFalse(hasVoted);

        _fundingVote(_grantFund, _tokenHolder1, testProposals[1].proposalId, voteYes, 500_000_000_000_000 * 1e18);
        // check if user vote is updated after voting in funding stage 
        hasVoted = _grantFund.hasVoted(testProposals[1].proposalId, _tokenHolder1);
        assertTrue(hasVoted);
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
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 150);

        // start distribution period
        _startDistributionPeriod(_grantFund);
        uint256 distributionId = _grantFund.getDistributionId();

        vm.roll(_startBlock + 200);

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
        GrantFund.Proposal[] memory screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        assertEq(screenedProposals.length, 10);

        // one of the non-current top 10 is moved up to the top spot
        _vote(_grantFund, _tokenHolder11, testProposals[10].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder12, testProposals[10].proposalId, voteYes, 100);

        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        assertEq(screenedProposals.length, 10);
        assertEq(screenedProposals[0].proposalId, testProposals[10].proposalId);
        assertEq(screenedProposals[0].votesReceived, 100_000_000 * 1e18);

        // another non-current top ten is moved up to the top spot
        _vote(_grantFund, _tokenHolder13, testProposals[11].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder14, testProposals[11].proposalId, voteYes, 100);
        _vote(_grantFund, _tokenHolder15, testProposals[11].proposalId, voteYes, 100);

        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
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

        (uint256 id, uint256 votesCast, uint256 startBlock, uint256 endBlock, , ) = _grantFund.getDistributionPeriodInfo(currentDistributionId);
        assertEq(id, currentDistributionId);
        assertEq(votesCast, 0);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + 648000);
        
        vm.roll(_startBlock + 100);
        currentDistributionId = _grantFund.getDistributionIdAtBlock(block.number - 1);
        assertEq(currentDistributionId, 1);

        // check a new distribution period can't be started if already active
        vm.expectRevert(IStandardFunding.DistributionPeriodStillActive.selector);
        _grantFund.startNewDistributionPeriod();

        // skip forward past the end of the distribution period to allow starting a new distribution
        vm.roll(_startBlock + 650_000);

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
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 150);

        // start distribution period
        _startDistributionPeriod(_grantFund);

        uint256 distributionId = _grantFund.getDistributionId();

        (, , , , uint256 gbc, ) = _grantFund.getDistributionPeriodInfo(distributionId);

        assertEq(gbc, 10_000_000 * 1e18);

        TestProposalParams[] memory testProposalParams = new TestProposalParams[](7);
        testProposalParams[0] = TestProposalParams(_tokenHolder1, 8_500_000 * 1e18);
        testProposalParams[1] = TestProposalParams(_tokenHolder2, 20_000_000 * 1e18);
        testProposalParams[2] = TestProposalParams(_tokenHolder3, 5_000_000 * 1e18);
        testProposalParams[3] = TestProposalParams(_tokenHolder4, 5_000_000 * 1e18);
        testProposalParams[4] = TestProposalParams(_tokenHolder5, 50_000 * 1e18);
        testProposalParams[5] = TestProposalParams(_tokenHolder6, 100_000 * 1e18);
        testProposalParams[6] = TestProposalParams(_tokenHolder7, 100_000 * 1e18);

        // create 7 proposals paying out tokens
        TestProposal[] memory testProposals = _createNProposals(_grantFund, _token, testProposalParams);
        assertEq(testProposals.length, 7);

        vm.roll(_startBlock + 200);

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
        vm.roll(_startBlock + 600_000);

        // check topTenProposals array is correct after screening period - only six should have advanced
        GrantFund.Proposal[] memory screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
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
        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        _fundingVote(_grantFund, _tokenHolder2, screenedProposals[1].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);
        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        _fundingVote(_grantFund, _tokenHolder3, screenedProposals[2].proposalId, voteYes, 1_250_000_000_000_000 * 1e18);
        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        _fundingVote(_grantFund, _tokenHolder3, screenedProposals[4].proposalId, voteYes, 1_250_000_000_000_000 * 1e18);
        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        _fundingVote(_grantFund, _tokenHolder4, screenedProposals[3].proposalId, voteYes, 2_000_000_000_000_000 * 1e18);
        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        _fundingVote(_grantFund, _tokenHolder4, screenedProposals[5].proposalId, voteNo, -500_000_000_000_000 * 1e18);
        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));

        vm.expectRevert(IStandardFunding.InsufficientBudget.selector);
        _grantFund.castVoteWithReasonAndParams(screenedProposals[3].proposalId, 1, "", abi.encode(2_500_000_000_000_000 * 1e18));

        changePrank(_tokenHolder5);
        vm.expectRevert(IStandardFunding.InsufficientBudget.selector);
        _grantFund.castVoteWithReasonAndParams(screenedProposals[3].proposalId, 0, "", abi.encode(-2_600_000_000_000_000 * 1e18));

        // check tokerHolder partial vote budget calculations
        _fundingVote(_grantFund, _tokenHolder5, screenedProposals[5].proposalId, voteNo, -500_000_000_000_000 * 1e18);
        screenedProposals = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));

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

        uint256[] memory potentialProposalSlate = new uint256[](2);
        potentialProposalSlate[0] = screenedProposals[0].proposalId;

        // including Proposal in potentialProposalSlate that is not in topTenProposal (funding Stage)
        potentialProposalSlate[1] = testProposals[6].proposalId;
        
        // ensure checkSlate won't allow if called before DistributionPeriod starts
        bool validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);

        // skip to the DistributionPeriod
        vm.roll(_startBlock + 650_000);

        // ensure checkSlate won't allow if slate has a proposal that is not in topTenProposal (funding Stage)
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);

        // Updating potential Proposal Slate to include proposal that is in topTenProposal (funding Stage)
        potentialProposalSlate[1] = screenedProposals[1].proposalId;

        // ensure checkSlate won't allow exceeding the GBC
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);
        (, , , , , bytes32 slateHash) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash, 0);

        // ensure checkSlate will allow a valid slate
        potentialProposalSlate = new uint256[](1);
        potentialProposalSlate[0] = screenedProposals[3].proposalId;
        vm.expectEmit(true, true, false, true);
        emit FundedSlateUpdated(distributionId, _grantFund.getSlateHash(potentialProposalSlate));
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);

        // should not update slate if current funding slate is same as potentialProposalSlate 
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);

        // check slate hash
        (, , , , , slateHash) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash, 0x53dc2b0b8c3787b3384472e1d449bb35e20089a01306e21d59ec6d080cdcd1a8);
        // check funded proposal slate matches expected state
        GrantFund.Proposal[] memory fundedProposalSlate = _getProposalListFromProposalIds(_grantFund, _grantFund.getFundedProposalSlate(distributionId, slateHash));
        assertEq(fundedProposalSlate.length, 1);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[3].proposalId);

        // ensure checkSlate will update the currentSlateHash when a superior slate is presented
        potentialProposalSlate = new uint256[](2);
        potentialProposalSlate[0] = screenedProposals[3].proposalId;
        potentialProposalSlate[1] = screenedProposals[4].proposalId;
        vm.expectEmit(true, true, false, true);
        emit FundedSlateUpdated(distributionId, _grantFund.getSlateHash(potentialProposalSlate));
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , , slateHash) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash, 0x1baa18a2d105ff81cc846882b7cc083ac252a82d2082db41156a83ae5d6a2436);
        // check funded proposal slate matches expected state
        fundedProposalSlate = _getProposalListFromProposalIds(_grantFund, _grantFund.getFundedProposalSlate(distributionId, slateHash));
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[3].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // ensure an additional update can be made to the optimized slate
        potentialProposalSlate = new uint256[](2);
        potentialProposalSlate[0] = screenedProposals[0].proposalId;
        potentialProposalSlate[1] = screenedProposals[4].proposalId;
        vm.expectEmit(true, true, false, true);
        emit FundedSlateUpdated(distributionId, _grantFund.getSlateHash(potentialProposalSlate));
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertTrue(validSlate);
        // check slate hash
        (, , , , , slateHash) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash, 0x6d2192bdd3e08d75d683185db5947cd199403513241eddfa5cf8a36256f27c40);
        // check funded proposal slate matches expected state
        fundedProposalSlate = _getProposalListFromProposalIds(_grantFund, _grantFund.getFundedProposalSlate(distributionId, slateHash));
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[0].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // check that a different slate which distributes more tokens (less than gbc), but has less votes won't pass
        potentialProposalSlate = new uint256[](2);
        potentialProposalSlate[0] = screenedProposals[2].proposalId;
        potentialProposalSlate[1] = screenedProposals[3].proposalId;
        validSlate = _grantFund.checkSlate(potentialProposalSlate, distributionId);
        assertFalse(validSlate);
        // check funded proposal slate wasn't updated
        (, , , , , slateHash) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash, 0x6d2192bdd3e08d75d683185db5947cd199403513241eddfa5cf8a36256f27c40);
        fundedProposalSlate = _getProposalListFromProposalIds(_grantFund, _grantFund.getFundedProposalSlate(distributionId, slateHash));
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[0].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // check can't execute proposals prior to the end of the challenge period
        vm.expectRevert(IStandardFunding.ExecuteProposalInvalid.selector);
        _grantFund.executeStandard(testProposals[0].targets, testProposals[0].values, testProposals[0].calldatas, keccak256(bytes(testProposals[0].description)));

        // should revert if user tries to claim reward in before challenge Period ends
        vm.expectRevert(IStandardFunding.ChallengePeriodNotEnded.selector);
        _grantFund.claimDelegateReward(distributionId);

        // skip to the end of the DistributionPeriod
        vm.roll(_startBlock + 700_000);

        // should revert if called execute method of governer contract
        vm.expectRevert(Funding.MethodNotImplemented.selector);
        _grantFund.execute(testProposals[0].targets, testProposals[0].values, testProposals[0].calldatas, keccak256(bytes(testProposals[0].description)));

        // execute funded proposals
        _executeProposal(_grantFund, _token, testProposals[0]);
        _executeProposal(_grantFund, _token, testProposals[4]);

        // check that shouldn't be able to execute unfunded proposals
        vm.expectRevert("Governor: proposal not successful");
        _grantFund.executeStandard(testProposals[1].targets, testProposals[1].values, testProposals[1].calldatas, keccak256(bytes(testProposals[1].description)));

        // check that shouldn't be able to execute a proposal twice
        vm.expectRevert("Governor: proposal not successful");
        _grantFund.executeStandard(testProposals[0].targets, testProposals[0].values, testProposals[0].calldatas, keccak256(bytes(testProposals[0].description)));

        // Claim delegate reward for all delegatees
        _claimDelegateReward(
            {
                grantFund_:        _grantFund,
                voter_:            _tokenHolder1,
                distributionId_:   distributionId,
                claimedReward_:    238095.238095238095238095 * 1e18
            }
        );
        _claimDelegateReward(
            {
                grantFund_:        _grantFund,
                voter_:            _tokenHolder2,
                distributionId_:   distributionId,
                claimedReward_:    238095.238095238095238095 * 1e18
            }
        );
        _claimDelegateReward(
            {
                grantFund_:        _grantFund,
                voter_:            _tokenHolder3,
                distributionId_:   distributionId,
                claimedReward_:    238095.238095238095238095 * 1e18
            }
        );
        _claimDelegateReward(
            {
                grantFund_:        _grantFund,
                voter_:            _tokenHolder4,
                distributionId_:   distributionId,
                claimedReward_:    238095.238095238095238095 * 1e18
            }
        );
        _claimDelegateReward(
            {
                grantFund_:        _grantFund,
                voter_:            _tokenHolder5,
                distributionId_:   distributionId,
                claimedReward_:    47619.047619047619047619 * 1e18
            }
        );

        // should revert as _tokenHolder5 already claimed his reward
        vm.expectRevert(IStandardFunding.RewardAlreadyClaimed.selector);
        _grantFund.claimDelegateReward(distributionId);

        // transfers 0 ajna Token as _tokenHolder6 has not participated in funding stage
        _claimDelegateReward(
            {
                grantFund_:        _grantFund,
                voter_:            _tokenHolder6,
                distributionId_:   distributionId,
                claimedReward_:    0
            }
        );

        // should revert as _tokenHolder14 has not participated in screening stage
        changePrank(_tokenHolder14);
        vm.expectRevert(IStandardFunding.DelegateRewardInvalid.selector);
        _grantFund.claimDelegateReward(distributionId);
    }

    /**
     *  @notice Test GBC calculations for 4 consecutive distributions.
     */ 
    function testMultipleDistribution() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 150);

        // start first distribution
        _startDistributionPeriod(_grantFund);

        uint256 distributionId = _grantFund.getDistributionId();

        (, , , , uint256 gbc_distribution1, ) = _grantFund.getDistributionPeriodInfo(distributionId);

        assertEq(gbc_distribution1, 10_000_000 * 1e18);
        
        TestProposalParams[] memory testProposalParams_distribution1 = new TestProposalParams[](1);
        testProposalParams_distribution1[0] = TestProposalParams(_tokenHolder1, 8_500_000 * 1e18);

        // create 1 proposal paying out tokens
        TestProposal[] memory testProposals_distribution1 = _createNProposals(_grantFund, _token, testProposalParams_distribution1);
        assertEq(testProposals_distribution1.length, 1);

        vm.roll(_startBlock + 200);

        // screening period votes
        _vote(_grantFund, _tokenHolder1, testProposals_distribution1[0].proposalId, voteYes, 100);

        // skip time to move from screening period to funding period
        vm.roll(_startBlock + 600_000);

        // check topTenProposals array is correct after screening period - only 1 should have advanced
        GrantFund.Proposal[] memory screenedProposals_distribution1 = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId));
        assertEq(screenedProposals_distribution1.length, 1);

        // funding period votes
        _fundingVote(_grantFund, _tokenHolder1, screenedProposals_distribution1[0].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);

        // skip to the Challenge period
        vm.roll(_startBlock + 650_000);

        uint256[] memory potentialProposalSlate = new uint256[](1);
        potentialProposalSlate[0] = screenedProposals_distribution1[0].proposalId;

        // checkSlate
        _grantFund.checkSlate(potentialProposalSlate, distributionId);

        // skip to the end of Challenge period
        vm.roll(_startBlock + 700_000);

        // execute funded proposals
        _executeProposal(_grantFund, _token, testProposals_distribution1[0]);

        // start second distribution
        _startDistributionPeriod(_grantFund);

        uint256 distributionId2 = _grantFund.getDistributionId();

        (, , , , uint256 gbc_distribution2, ) = _grantFund.getDistributionPeriodInfo(distributionId2);

        assertEq(gbc_distribution2, 9_830_000 * 1e18);
        
        TestProposalParams[] memory testProposalParams_distribution2 = new TestProposalParams[](1);
        testProposalParams_distribution2[0] = TestProposalParams(_tokenHolder1, 8_200_000 * 1e18);

        // create 1 proposal paying out tokens
        TestProposal[] memory testProposals_distribution2 = _createNProposals(_grantFund, _token, testProposalParams_distribution2);
        assertEq(testProposals_distribution2.length, 1);

        vm.roll(_startBlock + 700_200);

        // screening period votes
        _vote(_grantFund, _tokenHolder1, testProposals_distribution2[0].proposalId, voteYes, 700_100);

        // skip time to move from screening period to funding period
        vm.roll(_startBlock + 1_300_000);

        // check topTenProposals array is correct after screening period - only 1 should have advanced
        GrantFund.Proposal[] memory screenedProposals_distribution2 = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId2));
        assertEq(screenedProposals_distribution2.length, 1);

        // funding period votes
        _fundingVote(_grantFund, _tokenHolder1, screenedProposals_distribution2[0].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);

        // skip to the Challenge period
        vm.roll(_startBlock + 1_350_000);

        uint256[] memory potentialProposalSlate_distribution2 = new uint256[](1);
        potentialProposalSlate_distribution2[0] = screenedProposals_distribution2[0].proposalId;

        // checkSlate
        _grantFund.checkSlate(potentialProposalSlate_distribution2, distributionId2);

        // start third distribution before executing proposals of second distribution
        _startDistributionPeriod(_grantFund);

        uint256 distributionId3 = _grantFund.getDistributionId();

        (, , , , uint256 gbc_distribution3, ) = _grantFund.getDistributionPeriodInfo(distributionId3);

        assertEq(gbc_distribution3, 9_633_400 * 1e18);

        // skip to the end of Challenge period
        vm.roll(_startBlock + 1_400_000);

        // execute funded proposals
        _executeProposal(_grantFund, _token, testProposals_distribution2[0]);
        
        TestProposalParams[] memory testProposalParams_distribution3 = new TestProposalParams[](1);
        testProposalParams_distribution3[0] = TestProposalParams(_tokenHolder1, 7_000_000 * 1e18);

        // create 1 proposal paying out tokens
        TestProposal[] memory testProposals_distribution3 = _createNProposals(_grantFund, _token, testProposalParams_distribution3);
        assertEq(testProposals_distribution3.length, 1);

        vm.roll(_startBlock + 1_400_200);

        // screening period votes
        _vote(_grantFund, _tokenHolder1, testProposals_distribution3[0].proposalId, voteYes, 1_400_100);

        // skip time to move from screening period to funding period
        vm.roll(_startBlock + 1_990_000);

        // check topTenProposals array is correct after screening period - only 1 should have advanced
        GrantFund.Proposal[] memory screenedProposals_distribution3 = _getProposalListFromProposalIds(_grantFund, _grantFund.getTopTenProposals(distributionId3));
        assertEq(screenedProposals_distribution3.length, 1);

        // funding period votes
        _fundingVote(_grantFund, _tokenHolder1, screenedProposals_distribution3[0].proposalId, voteYes, 2_500_000_000_000_000 * 1e18);

        // skip to the Challenge period
        vm.roll(_startBlock + 2_000_000);

        uint256[] memory potentialProposalSlate_distribution3 = new uint256[](1);
        potentialProposalSlate_distribution3[0] = screenedProposals_distribution3[0].proposalId;

        // checkSlate
        _grantFund.checkSlate(potentialProposalSlate_distribution3, distributionId3);

        // skip to the end of Challenge period
        vm.roll(_startBlock + 2_100_000);

        // execute funded proposals
        _executeProposal(_grantFund, _token, testProposals_distribution3[0]);

        // start third distribution
        _startDistributionPeriod(_grantFund);

        uint256 distributionId4 = _grantFund.getDistributionId();

        (, , , , uint256 gbc_distribution4, ) = _grantFund.getDistributionPeriodInfo(distributionId4);

        assertEq(gbc_distribution4, 9_526_000 * 1e18);
    }

    function testGovernerViewMethods() external {

        uint256 delay = _grantFund.votingDelay();
        assertEq(delay, 0);

        uint256 quorum = _grantFund.quorum(block.number);
        assertEq(quorum, 0);

        string memory countingMode = _grantFund.COUNTING_MODE();
        assertEq(countingMode, "support=bravo&quorum=for,abstain");

        uint256 votingPeriod = _grantFund.votingPeriod();
        assertEq(votingPeriod, 0);
    }

    function testFuzzTopTenProposalandDelegateReward(uint256 noOfVoters_, uint256 noOfProposals_) external {

        /******************************/
        /*** Top ten proposals fuzz ***/
        /******************************/

        uint256 noOfVoters = bound(noOfVoters_, 1, 500);
        uint256 noOfProposals = bound(noOfProposals_, 1, 50);

        vm.roll(_startBlock + 20);

        // Initialize N voter addresses 
        address[] memory voters = _getVoters(noOfVoters);
        assertEq(voters.length, noOfVoters);

        // Transfer random ajna tokens to all voters and self delegate
        uint256[] memory votes = _getVotes(noOfVoters, voters, _token, _tokenDeployer);
        assertEq(votes.length, noOfVoters);

        vm.roll(block.number + 100);

        _startDistributionPeriod(_grantFund);

        vm.roll(block.number + 100);

        // ensure user gets the vote for screening stage
        for(uint i = 0; i < noOfVoters; i++) {
            assertEq(votes[i], _grantFund.getVotesWithParams(voters[i], block.number - 1, "Screening"));
        }

        uint256 distributionId = _grantFund.getDistributionId();

        // submit N proposals
        TestProposal[] memory proposals = _getProposals(noOfProposals, _grantFund, _tokenHolder1, _token);

        // Each voter votes on a random proposal from all Proposals
        for(uint i = 0; i < noOfVoters; i++) {
            uint256 randomProposalIndex = _getRandomProposal(noOfProposals);

            uint256 randomProposalId = proposals[randomProposalIndex].proposalId;

            noOfVotesOnProposal[randomProposalId] += votes[i];

            changePrank(voters[i]);
            _grantFund.castVote(randomProposalId, voteYes);
        }

        // calculate top 10 proposals based on total vote casted on each proposal
        for(uint i = 0; i < noOfProposals; i++) {
            uint256 currentProposalId = proposals[i].proposalId;
            uint256 votesOnCurrentProposal = noOfVotesOnProposal[currentProposalId];
            uint256 lengthOfArray = topTenProposalIds.length;

            // only add proposals having atleast a vote
            if (votesOnCurrentProposal > 0) {

                // if there are less than 10 proposals in topTenProposalIds , add current proposals and sort topTenProposalIds based on Votes
                if (lengthOfArray < 10) {
                    topTenProposalIds.push(currentProposalId);

                    // ensure if there are more than 1 proposalId in topTenProposalIds to sort  
                    if(topTenProposalIds.length > 1) {
                        _insertionSortProposalsByVotes(topTenProposalIds); 
                    }
                }

                // if there are 10 proposals in topTenProposalIds, check new proposal has more votes than the last proposal in topTenProposalIds
                else if( noOfVotesOnProposal[topTenProposalIds[lengthOfArray - 1]] <  votesOnCurrentProposal) {

                    // remove last proposal with least no of vote in topTenProposalIds
                    topTenProposalIds.pop();

                    // add new proposal with more votes than last
                    topTenProposalIds.push(currentProposalId);

                    // sort topTenProposalIds
                    _insertionSortProposalsByVotes(topTenProposalIds);
                }
            }
        }
        
        // get top ten proposals from contract
        uint256[] memory topTenProposalIdsFromContract = _grantFund.getTopTenProposals(distributionId);

        // ensure the no of proposals are correct
        assertEq(topTenProposalIds.length, topTenProposalIdsFromContract.length);

        for (uint i = 0; i < topTenProposalIds.length; i++) {
            // ensure that each proposal in topTenProposalIdsFromContract is correct
            assertEq(topTenProposalIds[i], topTenProposalIdsFromContract[i]);
        }

        /******************************/
        /*** Delegate rewards fuzz  ***/
        /******************************/

        // skip to funding stage
        vm.roll(block.number + 600_000);
        
        uint256 totalBudgetAllocated;

        // try to allocalate budget to all top ten proposals i.e. all are in final check slate
        for(uint i = 0; i < noOfVoters; i++) {
            // get proposal Id of proposal to vote
            uint256 proposalId = topTenProposalIds[i % topTenProposalIds.length];

            // check if proposalId is already there in potential proposal slate
            if (!_checkElementExist(proposalId, potentialProposalsSlate)) {
                // add proposalId in potential proposal slate for check slate
                potentialProposalsSlate.push(proposalId);
            }

            // calculate and allocate all qvBudget of the voter to the proposal
            uint256 budgetAllocated = Maths.wpow(votes[i], 2);
            totalBudgetAllocated += budgetAllocated;
            _fundingVote(_grantFund, voters[i], proposalId, voteYes, int256(budgetAllocated));
        }

        // skip to challenge period
        vm.roll(block.number + 50_000);

        // check current slate (slate will only contain proposals that have budget allocated to them prior)
        _grantFund.checkSlate(potentialProposalsSlate, distributionId);

        // skip to end of challenge period
        vm.roll(block.number + 100_000);

        // gbc = 2% of treasury
        uint256 gbc = treasury / 50;
        
        uint256 totalDelegationReward;

        // claim delegate reward for each voter
        for(uint i = 0; i < noOfVoters; i++) {
            uint256 budgetAllocated = Maths.wpow(votes[i], 2);

            // calculate delegate reward for each voter
            uint256 reward = Maths.wdiv(Maths.wmul(gbc, budgetAllocated), totalBudgetAllocated) / 10; 
            totalDelegationReward += reward; 

            // check whether reward calculated is correct
            _claimDelegateReward(
                {
                    grantFund_:        _grantFund,
                    voter_:            voters[i],
                    distributionId_:   distributionId,
                    claimedReward_:    reward
                }
            );
        }

        // ensure total delegation reward is less than equals to 10% of gbc
        assertGe(gbc / 10, totalDelegationReward);
    }

    // helper method that sort proposals based on votes on them
    function _insertionSortProposalsByVotes(uint256[] storage arr) internal {
        for (uint i = 1; i < arr.length; i++) {
            uint256 proposalId = arr[i];
            uint256 votesReceivedOnProposal = noOfVotesOnProposal[proposalId];
            uint j = i;

            while (j > 0 && votesReceivedOnProposal > noOfVotesOnProposal[arr[j-1]]) {
                // swap values if left item < right item
                uint256 temp = arr[j - 1];
                arr[j - 1] = arr[j];
                arr[j] = temp;

                j--;
            }
        }
    }
}



