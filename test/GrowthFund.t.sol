// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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
        _tokenHolder14
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

        // initial minter distributes treasury to growthFund
        _token.transfer(address(_growthFund), 500_000_000 * 1e18);
    }

    // expects a list of Proposal structs
    // filepath expected to be defined from root
    function loadProposalSlateJSON(string memory filePath) internal returns (IGrowthFund.Proposal[] memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, filePath);

        string memory json = vm.readFile(path);
        bytes memory encodedProposals = vm.parseJson(json, ".Proposals");

        (IGrowthFund.Proposal[] memory proposals) = abi.decode(encodedProposals, (IGrowthFund.Proposal[]));
        return proposals;
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

    function testInvalidProposeCalldata() external {
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

    function testMaximumQuarterlyDistribution() external {
        uint256 maximumQuarterlyDistribution = _growthFund.maximumQuarterlyDistribution();

        // distribution should be 2% of starting amount (500_000_000), or 10_000_000
        assertEq(maximumQuarterlyDistribution, 10_000_000 * 1e18);
    }

    /**
     *  @notice 4 voters consider 15 different proposals. 10 Make it through to the funding stage.
     */
    function xtestScreenProposalsCheckSorting() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // // create 15 proposals paying out tokens to _tokenHolder2
        // TestProposal[] memory testProposals = _createNProposals(_growthFund, _token, 15, _tokenHolder2);
        // assertEq(testProposals.length, 15);

        // vm.roll(110);

        // // screening period votes
        // _vote(_growthFund, _tokenHolder2, testProposals[0].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder3, testProposals[1].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder4, testProposals[2].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder5, testProposals[3].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder6, testProposals[4].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder7, testProposals[5].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder8, testProposals[6].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder9, testProposals[7].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder10, testProposals[8].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder11, testProposals[9].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder12, testProposals[1].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder13, testProposals[1].proposalId, 1, 100);
        // _vote(_growthFund, _tokenHolder14, testProposals[5].proposalId, 1, 100);

        // // check topTenProposals array
        // GrowthFund.Proposal[] memory proposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        // assertEq(proposals.length, 10);
        // assertEq(proposals[0].proposalId, testProposals[1].proposalId);
        // assertEq(proposals[0].votesReceived, 150_000_000 * 1e18);

        // assertEq(proposals[1].proposalId, testProposals[5].proposalId);
        // assertEq(proposals[1].votesReceived, 100_000_000 * 1e18);
    }

    // TODO: remove this?
    function testFundingStage() external {
        // TODO: allocate funding votes and check that state matches the fixtures

        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

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
        assertEq(endBlock, block.number + _growthFund.distributionPeriodLength());

        // check a new distribution period can't be started if already active
        vm.expectRevert(IGrowthFund.DistributionPeriodStillActive.selector);
        _growthFund.startNewDistributionPeriod();

        // skip forward past the end of the distribution period to allow starting anew
        vm.roll(300_000);

        _startDistributionPeriod(_growthFund);
        currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 2);
    }

    /**
     *  @notice Integration test of 5 proposals submitted, with 3 passing the screening stage. There should be two potential proposal slates after funding.
     *  @dev    Maximum quarterly distribution is 10_000_000.
     *  @dev    Funded slate is executed.
     */
    function testDistributionPeriodEndToEnd() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

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

        // create 6 proposals paying out tokens
        TestProposal[] memory testProposals = _createNProposals(_growthFund, _token, testProposalParams);
        assertEq(testProposals.length, 7);

        vm.roll(110);

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
        vm.roll(100_000);

        // check topTenProposals array is correct after screening period - only four should have advanced
        GrowthFund.Proposal[] memory screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
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
        _fundingVote(_growthFund, _tokenHolder1, screenedProposals[0].proposalId, voteYes, 250_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        _fundingVote(_growthFund, _tokenHolder2, screenedProposals[1].proposalId, voteYes, 250_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        _fundingVote(_growthFund, _tokenHolder3, screenedProposals[2].proposalId, voteYes, 125_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        _fundingVote(_growthFund, _tokenHolder3, screenedProposals[4].proposalId, voteYes, 125_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        _fundingVote(_growthFund, _tokenHolder4, screenedProposals[3].proposalId, voteYes, 200_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());
        _fundingVote(_growthFund, _tokenHolder4, screenedProposals[5].proposalId, voteNo, -50_000_000 * 1e18);
        screenedProposals = _growthFund.getTopTenProposals(_growthFund.getDistributionId());

        // skip to the DistributionPeriod
        vm.roll(200_000);

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
        assertEq(slateHash2, 0xbaecea49d532511a6bbc6ca382353d6a7cc116a987c058e4c86023f5d5166b5f);
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
        assertEq(slateHash3, 0xb99a61b06ff11e483096c15eaece1c4c16bdf9529d766136a057d46d0f53c232);
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
        assertEq(slateHash4, 0x206d2831dfe1629370693fb401dc5bec8cdd48a54da24f8b9720489287c8d850);
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
        // check slate hash
        (, , , , bytes32 slateHash5) = _growthFund.getDistributionPeriodInfo(distributionId);
        assertEq(slateHash5, slateHash4);
        // check funded proposal slate matches expected state
        fundedProposalSlate = _growthFund.getFundedProposalSlate(distributionId, slateHash5);
        assertEq(fundedProposalSlate.length, 2);
        assertEq(fundedProposalSlate[0].proposalId, screenedProposals[0].proposalId);
        assertEq(fundedProposalSlate[1].proposalId, screenedProposals[4].proposalId);

        // skip to the end of the DistributionPeriod
        vm.roll(250_000);

        // execute funded proposals
        _executeProposal(_growthFund, _token, testProposals[0]);
        _executeProposal(_growthFund, _token, testProposals[4]);
    }

    function xtestCheckSlateFixture() external {
        IGrowthFund.Proposal[] memory proposals = loadProposalSlateJSON("/test/fixtures/FundedSlate.json");

        // check that the slate returns false if screening period hasn't occured
        assertEq(_growthFund.checkSlate(proposals, _growthFund.maximumQuarterlyDistribution()), false);

        // start distribution period
        _startDistributionPeriod(_growthFund);

        // skip time to move to the distribution period
        vm.roll(200_000);

        bool slateStatus = _growthFund.checkSlate(proposals, _growthFund.maximumQuarterlyDistribution());
        assertEq(slateStatus, true);
    }

    // TODO: finish implementing
    function testSlateHash() external {
        IGrowthFund.Proposal[] memory proposals = loadProposalSlateJSON("/test/fixtures/FundedSlate.json");

        bytes32 slateHash = _growthFund.getSlateHash(proposals);
        assertEq(slateHash, 0x782d39817b3256245278e90dcc253aec40e6834480269e4442be665f6f2944a9);

        // check a similar slate results in a different hash
    }


    function testQuorum() external {
        uint256 pastBlock = 10;

        // skip forward 100 blocks
        vm.roll(100);
        assertEq((_initialAjnaTokenSupply * 4) / 100, _growthFund.quorum(pastBlock));
    }

    // TODO: move this into the voting tests?
    function testVotingDelay() external {}


}
