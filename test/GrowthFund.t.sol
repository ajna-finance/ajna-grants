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

    function testFundingStage() external {
        // TODO: allocate funding votes and check that state matches the fixtures
    }

    function testStartNewDistributionPeriod() external {
        uint256 currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 0);

        _startDistributionPeriod(_growthFund);
        currentDistributionId = _growthFund.getDistributionId();
        assertEq(currentDistributionId, 1);

        (uint256 id, uint256 votesCast, uint256 startBlock, uint256 endBlock, bool executed) = _growthFund.getDistributionPeriodInfo(currentDistributionId);
        assertEq(id, currentDistributionId);
        assertEq(votesCast, 0);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + _growthFund.distributionPeriodLength());
        assertEq(executed, false);
    }

    function testCheckSlate() external {
        IGrowthFund.Proposal[] memory proposals = loadProposalSlateJSON("/test/fixtures/FundedSlate.json");

        // check that the slate returns false if period hasn't started
        assertEq(_growthFund.checkSlate(proposals, _growthFund.maximumQuarterlyDistribution()), false);

        _startDistributionPeriod(_growthFund);


    }

    function testCheckSlateInvalid() external {

    }

    function testFinalizeDistribution() external {

    }

    function testFinalizeDistributionInvalid() external {

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
