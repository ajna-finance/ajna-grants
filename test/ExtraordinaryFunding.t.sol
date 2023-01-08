// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IGovernor } from "@oz/governance/IGovernor.sol";
import { IVotes }    from "@oz/governance/utils/IVotes.sol";


import { Funding }               from "../src/grants/base/Funding.sol";
import { GrantFund }             from "../src/grants/GrantFund.sol";
import { IExtraordinaryFunding } from "../src/grants/interfaces/IExtraordinaryFunding.sol";

import { GrantFundTestHelper } from "./utils/GrantFundTestHelper.sol";
import { IAjnaToken }          from "./utils/IAjnaToken.sol";

contract ExtraordinaryFundingGrantFundTest is GrantFundTestHelper {

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
    address internal _tokenHolder10   = makeAddr("_tokenHolder10");
    address internal _tokenHolder11   = makeAddr("_tokenHolder11");
    address internal _tokenHolder12   = makeAddr("_tokenHolder12");
    address internal _tokenHolder13   = makeAddr("_tokenHolder13");
    address internal _tokenHolder14   = makeAddr("_tokenHolder14");
    address internal _tokenHolder15   = makeAddr("_tokenHolder15");
    address internal _tokenHolder16   = makeAddr("_tokenHolder16");
    address internal _tokenHolder17   = makeAddr("_tokenHolder17");
    address internal _tokenHolder18   = makeAddr("_tokenHolder18");
    address internal _tokenHolder19   = makeAddr("_tokenHolder19");
    address internal _tokenHolder20   = makeAddr("_tokenHolder20");
    address internal _tokenHolder21   = makeAddr("_tokenHolder21");
    address internal _tokenHolder22   = makeAddr("_tokenHolder22");
    address internal _tokenHolder23   = makeAddr("_tokenHolder23");
    address internal _tokenHolder24   = makeAddr("_tokenHolder24");

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
        _tokenHolder15,
        _tokenHolder16,
        _tokenHolder17,
        _tokenHolder18,
        _tokenHolder19,
        _tokenHolder20,
        _tokenHolder21,
        _tokenHolder22,
        _tokenHolder23,
        _tokenHolder24
    ];

    uint256 _initialAjnaTokenSupply   = 2_000_000_000 * 1e18;

    // at this block on mainnet, all ajna tokens belongs to _tokenDeployer
    uint256 internal _startBlock      = 16354861;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), _startBlock);

        vm.startPrank(_tokenDeployer);

        // Ajna Token contract address on mainnet
        _token = IAjnaToken(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079);

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _grantFund = new GrantFund(_votingToken, 500_000_000 * 1e18);

        // initial minter distributes tokens to test addresses
        _transferAjnaTokens(_token, _votersArr, 50_000_000 * 1e18, _tokenDeployer);

        // initial minter distributes treasury to grantFund
        _token.transfer(address(_grantFund), 500_000_000 * 1e18);
    }

    function testGetVotingPowerExtraordinary() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 50);

        // check voting power is 0 whenn no proposal is available for voting
        uint256 votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number - 1, "");
        assertEq(votingPower, 0);

        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            50_000_000 * 1e18
        );

        // create and submit proposal
        TestProposalExtraordinary memory testProposal = _createProposalExtraordinary(
            _grantFund,
            _tokenHolder1,
            block.number + 100_000,
            targets,
            values,
            calldatas,
            "Extraordinary Proposal for Ajna token transfer to tester address"
        );

        // check voting power is greater than 0 for extant proposal
        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, abi.encode(testProposal.proposalId));
        assertEq(votingPower, 50_000_000 * 1e18);
    }

    function testGetVotingPowerDelegateTokens() external {
        // token holder 1 self delegates
        _delegateVotes(_token, _tokenHolder1, _tokenHolder1);
        _delegateVotes(_token, _tokenHolder2, _tokenHolder2);

        vm.roll(_startBlock + 17);

        // check voting power is 0 whenn no proposal is available for voting
        uint256 votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number - 1, "");
        assertEq(votingPower, 0);

        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            50_000_000 * 1e18
        );

        // voter transfers some of their tokens after the snapshot block
        vm.roll(_startBlock + 25);
        changePrank(_tokenHolder1);
        _token.transfer(_tokenHolder2, 25_000_000 * 1e18);

        // create and submit proposal at block 50
        vm.roll(_startBlock + 50);
        TestProposalExtraordinary memory testProposal = _createProposalExtraordinary(
            _grantFund,
            _tokenHolder1,
            block.number + 100_000,
            targets,
            values,
            calldatas,
            "Extraordinary Proposal for Ajna token transfer to tester address"
        );

        // check voting power at vote start
        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, abi.encode(testProposal.proposalId));
        assertEq(votingPower, 25_000_000 * 1e18);

        vm.roll(_startBlock + 100);

        // token holder transfers their remaining delegated tokens to a different address after vote start
        changePrank(_tokenHolder1);
        _token.transfer(_tokenHolder2, 20_000_000 * 1e18);

        // check voting power of tokenHolder1 matches minimum of snapshot period
        votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, abi.encode(testProposal.proposalId));
        assertEq(votingPower, 25_000_000 * 1e18);

        // check voting power of tokenHolder2 is 50_000_000, since received tokens during the snapshot period need to be redelegated
        votingPower = _grantFund.getVotesWithParams(_tokenHolder2, block.number, abi.encode(testProposal.proposalId));
        assertEq(votingPower, 50_000_000 * 1e18);

        // check voting power of tokenHolder3 is 0, since they missed the snapshot
        votingPower = _grantFund.getVotesWithParams(_tokenHolder3, block.number, abi.encode(testProposal.proposalId));
        assertEq(votingPower, 0);
    }

    function testGetMinimumThresholdPercentage() external {
        // default threshold percentage is 50
        uint256 minimumThresholdPercentage = _grantFund.getMinimumThresholdPercentage();
        assertEq(minimumThresholdPercentage, 0.500000000000000000 * 1e18);
    }

    /** 
     * @notice Calculate the number of tokens equivalent to various percentages assuming a treasury balance of 500,000,000.
     */
    function testGetSliceOfNonTreasury() external {
        uint256 percentageRequested = 0.100000000000000000 * 1e18;
        uint256 percentageOfTreasury = _grantFund.getSliceOfNonTreasury(percentageRequested);
        assertEq(percentageOfTreasury, 150_000_000 * 1e18);

        percentageRequested = 0.055000000000000000 * 1e18;
        percentageOfTreasury = _grantFund.getSliceOfNonTreasury(percentageRequested);
        assertEq(percentageOfTreasury, 82_500_000 * 1e18);
    }

    function testProposeExtraordinary() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 100);

        // set proposal params
        uint256 endBlockParam = block.number + 100_000;
        uint256 tokensRequestedParam = 50_000_000 * 1e18;

        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            tokensRequestedParam
        );

        // create and submit proposal
        TestProposalExtraordinary memory testProposal = _createProposalExtraordinary(
            _grantFund,
            _tokenHolder1,
            endBlockParam,
            targets,
            values,
            calldatas,
            "Extraordinary Proposal for Ajna token transfer to tester address"
        );

        // check proposal status
        IGovernor.ProposalState proposalState = _grantFund.state(testProposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // check proposal state
        (
            uint256 proposalId,
            uint256 tokensRequested,
            uint256 startBlock,
            uint256 endBlock,
            uint256 votesReceived,
            bool succeeded,
            bool executed
        ) = _grantFund.getExtraordinaryProposalInfo(testProposal.proposalId);

        assertEq(proposalId, testProposal.proposalId);
        assertEq(tokensRequested, tokensRequestedParam);
        assertEq(tokensRequested, testProposal.tokensRequested);
        assertEq(startBlock, block.number);
        assertEq(endBlock, endBlockParam);
        assertEq(votesReceived, 0);
        assertFalse(succeeded);
        assertFalse(executed);

        // should revert is same proposal is being proposed
        vm.expectRevert(Funding.ProposalAlreadyExists.selector);
        _grantFund.proposeExtraordinary(endBlockParam, targets, values, calldatas, "Extraordinary Proposal for Ajna token transfer to tester address");

        // check findMechanism identifies it as an extraOrdinary proposal
        assert(_grantFund.findMechanismOfProposal(proposalId) == Funding.FundingMechanism.Extraordinary);
    }

    function testProposeExtraordinaryInvalid() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 100);

        // set proposal params
        uint256 endBlockParam = block.number + 100_000;

        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // check can't request more than minium threshold amount of tokens
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            500_000_000 * 1e18
        );

        vm.expectRevert(IExtraordinaryFunding.ExtraordinaryFundingProposalInvalid.selector);
        _grantFund.proposeExtraordinary(endBlockParam, targets, values, calldatas, "proposal for excessive transfer");

        // check can't invoke with invalid calldata
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "burn(address,uint256)",
            _tokenHolder1,
            50_000_000 * 1e18
        );

        vm.expectRevert(Funding.InvalidSignature.selector);
        _grantFund.proposeExtraordinary(endBlockParam, targets, values, calldatas, "burn extraordinary");

        // check can't submit proposal with end block higher than limit
        endBlockParam = block.number + 500_000;

        // check can't request more than minium threshold amount of tokens
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            50_000_000 * 1e18
        );
        vm.expectRevert(IExtraordinaryFunding.ExtraordinaryFundingProposalInvalid.selector);
        _grantFund.proposeExtraordinary(endBlockParam, targets, values, calldatas, "proposal for excessive transfer");
    }

    function testProposeAndExecuteExtraordinary() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _votersArr);

        vm.roll(_startBlock + 100);

        // set proposal params
        uint256 endBlockParam = block.number + 100_000;
        uint256 tokensRequestedParam = 50_000_000 * 1e18;

        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            50_000_000 * 1e18
        );

        // create and submit proposal
        TestProposalExtraordinary memory testProposal = _createProposalExtraordinary(
            _grantFund,
            _tokenHolder1,
            endBlockParam,
            targets,
            values,
            calldatas,
            "Extraordinary Proposal for Ajna token transfer to tester address"
        );

        vm.roll(_startBlock + 150);

        // check can't execute unsuccessful proposal
        vm.expectRevert(IExtraordinaryFunding.ExecuteExtraordinaryProposalInvalid.selector);
        _grantFund.executeExtraordinary(testProposal.targets, testProposal.values, testProposal.calldatas, keccak256(bytes(testProposal.description)));

        // check proposal status
        IGovernor.ProposalState proposalState = _grantFund.state(testProposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // token holders vote on the proposal to pass it
        _extraordinaryVote(_grantFund, _tokenHolder1, testProposal.proposalId, 1);

        // should revert if user tries to vote again
        vm.expectRevert(Funding.AlreadyVoted.selector);
        _grantFund.castVote(testProposal.proposalId, 1);

        // partial votes should leave the proposal as active, not succeed
        proposalState = _grantFund.state(testProposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // additional votes push the proposal over the threshold
        _extraordinaryVote(_grantFund, _tokenHolder2, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder3, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder4, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder5, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder6, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder7, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder8, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder9, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder10, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder11, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder12, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder13, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder14, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder15, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder16, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder17, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder18, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder19, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder20, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder21, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder22, testProposal.proposalId, 1);
        _extraordinaryVote(_grantFund, _tokenHolder23, testProposal.proposalId, 1);

        // check proposal status
        proposalState = _grantFund.state(testProposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

        // check proposal state
        (
            uint256 proposalId,
            uint256 tokensRequested,
            ,
            ,
            uint256 votesReceived,
            bool succeeded,
            bool executed
        ) = _grantFund.getExtraordinaryProposalInfo(testProposal.proposalId);
        assertEq(proposalId, testProposal.proposalId);
        assertEq(tokensRequested, tokensRequestedParam);
        assertEq(votesReceived, 23 * 50_000_000 * 1e18);
        assertFalse(succeeded);
        assertFalse(executed);

        // minimum threshold percentage should be at default levels before the succesful proposal is executed
        uint256 minimumThresholdPercentage = _grantFund.getMinimumThresholdPercentage();
        assertEq(minimumThresholdPercentage, 0.500000000000000000 * 1e18);

        vm.roll(_startBlock + 200_000);

        // ensure user has not voted
        bool hasVoted = _grantFund.hasVoted(proposalId, _tokenHolder24);
        assertFalse(hasVoted);
        
        changePrank(_tokenHolder24);
        // Should revert if user tries to vote after proposal's end block
        vm.expectRevert(IExtraordinaryFunding.ExtraordinaryFundingProposalInactive.selector);
        _grantFund.castVote(proposalId, voteYes);

        // execute proposal
        _executeExtraordinaryProposal(_grantFund, _token, testProposal);

        // check state updated as expected
        proposalState = _grantFund.state(testProposal.proposalId);
        assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Executed));
        (
            ,
            ,
            ,
            ,
            votesReceived,
            succeeded,
            executed
        ) = _grantFund.getExtraordinaryProposalInfo(testProposal.proposalId);
        assertEq(votesReceived, 23 * 50_000_000 * 1e18);
        assertTrue(succeeded);
        assertTrue(executed);

        // check tokens transferred to the recipient address
        assertEq(_token.balanceOf(_tokenHolder1), 100_000_000 * 1e18);
        assertEq(_token.balanceOf(address(_grantFund)), 450_000_000 * 1e18);

        // check can't execute proposal twice
        vm.expectRevert(IExtraordinaryFunding.ExecuteExtraordinaryProposalInvalid.selector);
        _grantFund.executeExtraordinary(testProposal.targets, testProposal.values, testProposal.calldatas, keccak256(bytes(testProposal.description)));

        // minimum threshold percentage should increase after the succesful proposal is executed
        minimumThresholdPercentage = _grantFund.getMinimumThresholdPercentage();
        assertEq(minimumThresholdPercentage, 0.550000000000000000 * 1e18);
    }

    function testFuzzExtraordinaryFunding(uint256 noOfVoters_, uint256 noOfProposals_) external {
        uint256 noOfVoters = bound(noOfVoters_, 1, 100);
        uint256 noOfProposals = bound(noOfProposals_, 1, 10);

        // self delegate
        _selfDelegateVoters(_token, _votersArr);
        address[] memory voters = _getVoters(noOfVoters);

        // transfer remaining amount of total ajna supply to voters 
        uint256 amountToTransfer = 300_000_000 * 1e18 / noOfVoters;

        _transferAjnaTokens(_token, voters, amountToTransfer, _tokenDeployer);

        // self delegate votes
        for(uint i = 0; i < noOfVoters; i++) {
            changePrank(voters[i]);
            _token.delegate(voters[i]);
        }

        vm.roll(_startBlock + 100);

        // set token required to be 10% of treasury
        uint256 tokenRequested = 500_000_000 * 1e18 / 10;

        // create and submit N Extra Ordinary proposals 
        TestProposalExtraordinary[] memory testProposal =  _getNExtraOridinaryProposals(noOfProposals, _grantFund, _tokenHolder1, _token, tokenRequested);

        // each tokenHolder(fixed in setup) votes on all proposals
        for(uint i = 0; i < _votersArr.length; i++) {
            for(uint j = 0; j < noOfProposals; j++) {
                _extraordinaryVote(_grantFund, _votersArr[i], testProposal[j].proposalId, voteYes);
            }
        }   

        // each voter(fuzzed) votes on all proposals
        for(uint i = 0; i < noOfVoters; i++) {
            for(uint j = 0; j < noOfProposals; j++) {
                _extraordinaryVote(_grantFund, voters[i], testProposal[j].proposalId, voteYes);
            }
        }

        vm.roll(_startBlock + 240_000);

        // execute all proposals
        for(uint i = 0; i < noOfProposals; i++) {
            /* first 7 proposals are executed successfully and from 8th proposal each one will fail
             as non-treasury amount and minimum threshold increases with each proposal execution */
            if (i >= 7) {
                // check state has been marked as Defeated
                assertEq(uint8(_grantFund.state(testProposal[i].proposalId)), uint8(IGovernor.ProposalState.Defeated));

                vm.expectRevert(IExtraordinaryFunding.ExecuteExtraordinaryProposalInvalid.selector);
                _grantFund.executeExtraordinary(testProposal[i].targets, testProposal[i].values, testProposal[i].calldatas, keccak256(bytes(testProposal[i].description)));
            }
            else {
                _executeExtraordinaryProposal(_grantFund, _token, testProposal[i]);

                // check state is updated to Executed after proposal is executed
                assertEq(uint8(_grantFund.state(testProposal[i].proposalId)), uint8(IGovernor.ProposalState.Executed));
            }
        }
        
    }

}
