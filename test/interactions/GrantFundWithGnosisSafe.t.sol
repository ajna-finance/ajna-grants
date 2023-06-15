// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { Strings }  from "@oz/utils/Strings.sol";

import { GrantFund }        from "../../src/grants/GrantFund.sol";
import { IGrantFundState }  from "../../src/grants/interfaces/IGrantFundState.sol";

import "./interfaces.sol";
import { GrantFundTestHelper } from "../utils/GrantFundTestHelper.sol";
import { IAjnaToken }          from "../utils/IAjnaToken.sol";

contract GrantFundWithGnosisSafe is GrantFundTestHelper {

    IGnosisSafeFactory internal _gnosisSafeFactory;
    IGnosisSafe        internal _gnosisSafe;

    IAjnaToken         internal _token;
    GrantFund          internal _grantFund;

    // Ajna token Holder at the Ajna contract creation on mainnet
    address internal _tokenDeployer  = 0x666cf594fB18622e1ddB91468309a7E194ccb799;
    
    struct MultiSigOwner {
        address walletAddress;
        uint256 privateKey;
    }

    struct Proposals {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        bytes32 descriptionHash;
        uint256 proposalId;
    }

    address[] internal _votersArr;

    uint256 _treasury = 500_000_000 * 1e18;

    uint256 _nonces = 0;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        address gnosisSafeFactoryAddress = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2; // mainnet gnosisSafeFactory contract address
        _gnosisSafeFactory = IGnosisSafeFactory(gnosisSafeFactoryAddress);

        address singletonAddress  = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552; // mainnet singleton contract address

        // deploy gnosis safe
        address gnosisSafeAddress = _gnosisSafeFactory.createProxy(singletonAddress, "");

        _gnosisSafe = IGnosisSafe(gnosisSafeAddress);

        (_grantFund, _token) = _deployAndFundGrantFund(_tokenDeployer, _treasury, _votersArr, 0);

        // transfer tokens to gnosis safe
        changePrank(_tokenDeployer);
        _token.transfer(gnosisSafeAddress, 25_000_000 * 1e18);
    }

    function testGrantFundWithMultiSigWallet() external {
        MultiSigOwner[] memory multiSigOwners = new MultiSigOwner[](3);

        (multiSigOwners[0].walletAddress, multiSigOwners[0].privateKey) = makeAddrAndKey("_multiSigOwner1");
        (multiSigOwners[1].walletAddress, multiSigOwners[1].privateKey) = makeAddrAndKey("_multiSigOwner2");
        (multiSigOwners[2].walletAddress, multiSigOwners[2].privateKey) = makeAddrAndKey("_multiSigOwner3");

        address[] memory owners = new address[](3);
        owners[0] = multiSigOwners[0].walletAddress;
        owners[1] = multiSigOwners[1].walletAddress;
        owners[2] = multiSigOwners[2].walletAddress;

        // Setup gnosis safe with 3 owners and 2 threshold to execute transaction
        _gnosisSafe.setup(owners, 2, address(0), "", address(0), address(0), 0, payable(address(0)));

        // self delegate votes
        bytes memory callData = abi.encodeWithSignature("delegate(address)", address(_gnosisSafe));
        _executeTransaction(address(_token), callData, multiSigOwners);

        vm.roll(block.number + 100);

        // Start distribution period
        _startDistributionPeriod(_grantFund);

        uint24 distributionId = _grantFund.getDistributionId();

        // generate proposals for distribution
        Proposals[] memory proposals = _generateProposals(2);

        // propose first proposal
        callData = abi.encodeWithSignature("propose(address[],uint256[],bytes[],string)", proposals[0].targets, proposals[0].values, proposals[0].calldatas, proposals[0].description);
        _executeTransaction(address(_grantFund), callData, multiSigOwners);

        // propose second proposal
        callData = abi.encodeWithSignature("propose(address[],uint256[],bytes[],string)", proposals[1].targets, proposals[1].values, proposals[1].calldatas, proposals[1].description);
        _executeTransaction(address(_grantFund), callData, multiSigOwners);

        // skip to screening stage
        vm.roll(block.number + 100);

        // construct vote params
        IGrantFundState.ScreeningVoteParams[] memory screeningVoteParams = new IGrantFundState.ScreeningVoteParams[](1);
        screeningVoteParams[0].proposalId = proposals[0].proposalId;
        screeningVoteParams[0].votes      = 20_000_000 * 1e18;

        // cast screening vote
        callData = abi.encodeWithSignature("screeningVote((uint256,uint256)[])", screeningVoteParams);
        _executeTransaction(address(_grantFund), callData, multiSigOwners);

        // skip to funding stage
        vm.roll(block.number + 550_000);

        // construct vote params
        IGrantFundState.FundingVoteParams[] memory fundingVoteParams = new IGrantFundState.FundingVoteParams[](1);
        fundingVoteParams[0].proposalId = proposals[0].proposalId;
        fundingVoteParams[0].votesUsed  = 20_000_000 * 1e18;

        // cast funding vote 
        callData = abi.encodeWithSignature("fundingVote((uint256,int256)[])", fundingVoteParams);
        _executeTransaction(address(_grantFund), callData, multiSigOwners);

        // skip to the Challenge period
        vm.roll(block.number + 50_000);

        // construct potential proposal slate
        uint256[] memory potentialProposalSlate = new uint256[](1);
        potentialProposalSlate[0] = proposals[0].proposalId;

        // update slate
        callData = abi.encodeWithSignature("updateSlate(uint256[],uint24)", potentialProposalSlate, distributionId);
        _executeTransaction(address(_grantFund), callData, multiSigOwners);

        // skip to the end of distribution period
        vm.roll(block.number + 100_000);

        // execute proposal
        callData = abi.encodeWithSignature("execute(address[],uint256[],bytes[],bytes32)", proposals[0].targets, proposals[0].values, proposals[0].calldatas, proposals[0].descriptionHash);
        _executeTransaction(address(_grantFund), callData, multiSigOwners);

        // claim delegate reward
        callData = abi.encodeWithSignature("claimDelegateReward(uint24)", distributionId);
        _executeTransaction(address(_grantFund), callData, multiSigOwners);
    }

    function _executeTransaction(address contractAddress, bytes memory callData, MultiSigOwner[] memory multiSigOwners) internal {
        bytes32 transactionHash = _gnosisSafe.getTransactionHash(contractAddress, 0, callData, IGnosisSafe.Operation.Call, 0, 0, 0, address(0), address(0), _nonces++);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(multiSigOwners[0].privateKey, transactionHash);
        bytes memory signature1 = abi.encodePacked(r, s, v);

        (v, r, s) = vm.sign(multiSigOwners[1].privateKey, transactionHash);
        bytes memory signature2 = abi.encodePacked(r, s, v);

        bytes memory signatures = abi.encodePacked(signature1, signature2);
        _gnosisSafe.execTransaction(contractAddress, 0, callData, IGnosisSafe.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures);

    }

    function _generateProposals(uint256 noOfProposals_) internal view returns(Proposals[] memory) {
        Proposals[] memory proposals_ = new Proposals[](noOfProposals_);

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
            address(_gnosisSafe),
            1_000_000 * 1e18
        );

        for(uint i = 0; i < noOfProposals_; i++) {
            // generate proposal message 
            string memory description = string(abi.encodePacked("Proposal", Strings.toString(i)));
            bytes32 descriptionHash   = _grantFund.getDescriptionHash(description);
            uint256 proposalId = _grantFund.hashProposal(ajnaTokenTargets, values, proposalCalldata, descriptionHash);
            proposals_[i] = Proposals(ajnaTokenTargets, values, proposalCalldata, description, descriptionHash, proposalId);
        }
        return proposals_;
    }

}