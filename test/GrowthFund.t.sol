// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { AjnaToken } from "../src/BaseToken.sol";
import { GrowthFund } from "../src/GrowthFund.sol";

import { SigUtils } from "./utils/SigUtils.sol";

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes } from "@oz/governance/utils/IVotes.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

contract GrowthFundTest is Test {

    // used to cast 256 to uint64 to match emit expectations
    using SafeCast for uint256;

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

    uint256 _initialAjnaTokenSupply   = 2_000_000_000 * 1e18;

    // TODO: replace with selectors from Governor interface?
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
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    function setUp() external {
        vm.startPrank(_tokenDeployer);
        _token = new AjnaToken(_tokenHolder1);

        _sigUtils = new SigUtils(_token.DOMAIN_SEPARATOR());

        // initial minter distributes tokens to test addresses
        changePrank(_tokenHolder1);
        _token.transfer(_tokenHolder2, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder3, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder4, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder5, 50_000_000 * 1e18);

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _growthFund = new GrowthFund(_votingToken);
    }

    /*****************************/
    /*** Test Helper Functions ***/
    /*****************************/

    // TODO: finish implementing 
    function _createProposal(address target_) internal {}

    function _delegateVotes(address delegator_, address delegatee_) internal {
        changePrank(delegator_);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator_, address(0), delegatee_);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegatee_, 0, 50_000_000 * 1e18);
        _token.delegate(delegatee_);
    }

    function _vote(address voter_, uint256 proposalId_, uint8 support_, uint256 votingWeightSnapshotBlock_) internal {
        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, _growthFund.getVotes(address(voter_), votingWeightSnapshotBlock_), "");
        _growthFund.castVote(proposalId_, support_);
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

    function testPropose() external {
        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(_token);

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

        // generate expected proposal state
        uint256 expectedProposalId = _growthFund.hashProposal(ajnaTokenTargets, values, proposalCalldata, keccak256(bytes(description)));
        uint256 startBlock = block.number.toUint64() + _growthFund.votingDelay().toUint64();
        uint256 endBlock   = startBlock + _growthFund.votingPeriod().toUint64();

        // submit proposal
        changePrank(_tokenHolder2);
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            expectedProposalId,
            _tokenHolder2,
            ajnaTokenTargets,
            values,
            new string[](ajnaTokenTargets.length),
            proposalCalldata,
            startBlock,
            endBlock,
            description
        );
        uint256 proposalId = _growthFund.propose(ajnaTokenTargets, values, proposalCalldata, description);
        assertEq(proposalId, expectedProposalId);

        vm.roll(10);

        // check proposal state
        IGovernor.ProposalState proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));
    }

    // TODO: implement more granular testing
    // function testVoteOnProposal() external {}

    function testVoteAndExecuteProposal() external {
        // tokenholders self delegate their tokens to enable voting on the proposal
        _delegateVotes(_tokenHolder2, _tokenHolder2);
        _delegateVotes(_tokenHolder3, _tokenHolder3);
        _delegateVotes(_tokenHolder4, _tokenHolder4);

        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(_token);

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

        // generate expected proposal state
        uint256 expectedProposalId = _growthFund.hashProposal(ajnaTokenTargets, values, proposalCalldata, keccak256(bytes(description)));
        uint256 startBlock = block.number.toUint64() + _growthFund.votingDelay().toUint64();
        uint256 endBlock   = startBlock + _growthFund.votingPeriod().toUint64();

        // submit proposal
        changePrank(_tokenHolder2);
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            expectedProposalId,
            _tokenHolder2,
            ajnaTokenTargets,
            values,
            new string[](ajnaTokenTargets.length),
            proposalCalldata,
            startBlock,
            endBlock,
            description
        );
        uint256 proposalId = _growthFund.propose(ajnaTokenTargets, values, proposalCalldata, description);
        assertEq(proposalId, expectedProposalId);

        vm.roll(110);

        // check proposal state
        IGovernor.ProposalState proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // _tokenHolder2 and _tokenHolder3 vote for (1), _tokenHolder4 vote against (0)
        _vote(_tokenHolder2, proposalId, 1, 100);
        _vote(_tokenHolder3, proposalId, 1, 100);
        _vote(_tokenHolder4, proposalId, 0, 100);

        // TODO: count votes

        proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // skip to the end of the voting period
        vm.roll(46000);
        proposalState = _growthFund.state(proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Succeeded));

        // execute proposal
    }

    function testQuorum() external {
        uint256 pastBlock = 10;

        // skip forward 100 blocks
        vm.roll(100);
        assertEq((_initialAjnaTokenSupply * 4) / 100, _growthFund.quorum(pastBlock));
    }

    function testUpdateQuorum() external {}

    function testVotingDelay() external {}


}
