// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings }  from "@oz/utils/Strings.sol"; // used for createNProposals
import { Test }     from "@std/Test.sol";

import { GrantFund }             from "../../src/grants/GrantFund.sol";
import { IFunding }              from "../../src/grants/interfaces/IFunding.sol";
import { IExtraordinaryFunding } from "../../src/grants/interfaces/IExtraordinaryFunding.sol";
import { IStandardFunding }      from "../../src/grants/interfaces/IStandardFunding.sol";
import { Maths }                 from "../../src/grants/libraries/Maths.sol";

import { IAjnaToken }       from "./IAjnaToken.sol";
import { TestAjnaToken }    from "./harness/TestAjnaToken.sol";

abstract contract GrantFundTestHelper is Test {

    using SafeCast for uint256;
    using Strings for string;

    /*************************/
    /*** Ajna Token Events ***/
    /*************************/

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    event Transfer(address indexed from, address indexed to, uint256 value);

    /*************************/
    /*** Grant Fund Events ***/
    /*************************/

    event DelegateRewardClaimed(address indexed delegateeAddress_, uint256 indexed distributionId_, uint256 rewardClaimed_);
    event FundTreasury(uint256 amount, uint256 treasuryBalance);
    event FundedSlateUpdated(uint256 indexed distributionId_, bytes32 indexed fundedSlateHash_);
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
    event QuarterlyDistributionStarted(uint256 indexed distributionId_, uint256 startBlock_, uint256 endBlock_);
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    /***********************/
    /*** Testing Structs ***/
    /***********************/

    struct GeneratedTestProposalParams {
        address target;
        uint256 value;
        bytes calldatas;
        address recipient;
        uint256 tokensRequested;
    }

    struct TestProposal {
        uint256 proposalId;
        uint24 distributionId;
        string description;
        uint256 totalTokensRequested;
        uint256 blockAtCreation; // block number of test proposal creation
        GeneratedTestProposalParams[] params;
    }

    struct TestProposalExtraordinary {
        uint256 proposalId;
        address proposer;
        string description;
        uint256 startBlock;
        uint256 endBlock;
        uint256 totalTokensRequested;
        uint256 treasuryBalanceAtSubmission;
        uint256 minimumThresholdPercentageAtSubmission;
        uint256 treasuryBalanceAtExecution;
        uint256 ajnaTotalSupplyAtExecution;
        uint256 minimumThresholdPercentageAtExecution;
        GeneratedTestProposalParams[] params;
    }

    struct TestProposalParams {
        address recipient;
        uint256 tokensRequested;
    }

    uint8 voteNo = 0;
    uint8 voteYes = 1;

    /***********************/
    /*** Setup Functions ***/
    /***********************/

    function _deployAndFundGrantFund(address tokenDeployer_, uint256 treasury_, address[] memory initialVoters_, uint256 initialVoterBalance_) internal returns (GrantFund grantFund_, IAjnaToken token_) {
        vm.startPrank(tokenDeployer_);

        // deploy ajna token
        TestAjnaToken token = new TestAjnaToken();

        token_ = IAjnaToken(address(token));
        token_.mint(tokenDeployer_, 1_000_000_000 * 1e18);

        // deploy grant fund contract
        grantFund_ = new GrantFund(address(token));

        // initial minter distributes treasury to grantFund
        changePrank(tokenDeployer_);
        token_.approve(address(grantFund_), treasury_);
        grantFund_.fundTreasury(treasury_);

        if (initialVoters_.length != 0) {
            // initial minter distributes tokens to test addresses
            _transferAjnaTokens(token_, initialVoters_, initialVoterBalance_, tokenDeployer_);
        }
    }

    /****************************/
    /*** Ajna Token Functions ***/
    /****************************/

    function _delegateVotes(IAjnaToken token_, address delegator_, address delegatee_, uint256 tokensDelegated_) internal {
        changePrank(delegator_);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator_, address(0), delegatee_);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegatee_, 0, tokensDelegated_);
        token_.delegate(delegatee_);
    }

    function _selfDelegateVoters(IAjnaToken token_, address[] memory voters_) internal {
        for (uint256 i = 0; i < voters_.length; ++i) {
            uint256 tokenBalance = token_.balanceOf(voters_[i]);
            _delegateVotes(token_, voters_[i], voters_[i], tokenBalance);
        }
    }

    function _transferAjnaTokens(IAjnaToken token_, address[] memory voters_, uint256 amount_, address tokenDeployer_) internal {
        changePrank(tokenDeployer_);
        for (uint256 i = 0; i < voters_.length; ++i) {
            token_.transfer(voters_[i], amount_);
        }
    }

    /************************************/
    /*** Delegation Rewards Functions ***/
    /************************************/

    function _claimDelegateReward(GrantFund grantFund_, address voter_, uint24 distributionId_, uint256 claimedReward_) internal {
        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit DelegateRewardClaimed(voter_, distributionId_, claimedReward_);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(grantFund_), voter_, claimedReward_);
        grantFund_.claimDelegateReward(distributionId_);
    }

    function _claimZeroDelegateReward(GrantFund grantFund_, address voter_, uint24 distributionId_, uint256 claimedReward_) internal {
        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit DelegateRewardClaimed(voter_, distributionId_, claimedReward_);
        grantFund_.claimDelegateReward(distributionId_);
    }

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    function _startDistributionPeriod(GrantFund grantFund_) internal returns (uint24 distributionId) {
        vm.expectEmit(true, true, false, true);
        emit QuarterlyDistributionStarted(grantFund_.getDistributionId() + 1, block.number, block.number + 648000);
        distributionId = grantFund_.startNewDistributionPeriod();
    }

    function _getDistributionFundsAvailable(uint256 surplus, uint256 treasury) internal pure returns (uint256 fundsAvailable_) {
        fundsAvailable_ = Maths.wmul(.03 * 1e18, treasury + surplus);
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    function _createProposalExtraordinary(
        GrantFund grantFund_,
        address proposer_,
        uint256 endBlock,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description
    ) internal returns (TestProposalExtraordinary memory) {
        // generate expected proposal state
        uint256 expectedProposalId = grantFund_.hashProposal(
            targets_,
            values_,
            calldatas_,
            grantFund_.getDescriptionHashExtraordinary(description, proposer_)
        );
        uint256 startBlock = block.number;

        // submit proposal
        changePrank(proposer_);
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            expectedProposalId,
            proposer_,
            targets_,
            values_,
            new string[](targets_.length),
            calldatas_,
            startBlock,
            endBlock,
            description
        );
        uint256 proposalId = grantFund_.proposeExtraordinary(endBlock, targets_, values_, calldatas_, description);
        assertEq(proposalId, expectedProposalId);

        (
            GeneratedTestProposalParams[] memory params,
            uint256 totalTokensRequested
        ) = _getGeneratedTestProposalParamsFromParams(targets_, values_, calldatas_);

        return TestProposalExtraordinary(
            proposalId,
            proposer_,
            description,
            block.number,
            endBlock,
            totalTokensRequested,
            grantFund_.treasury(),
            grantFund_.getMinimumThresholdPercentage(),
            0,
            0,
            0,
            params
        );
    }

    function _createProposalStandard(GrantFund grantFund_, address proposer_, address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, string memory description) internal returns (TestProposal memory) {
        // generate expected proposal state
        uint256 expectedProposalId = grantFund_.hashProposal(targets_, values_, calldatas_, keccak256(abi.encode(keccak256(bytes("Standard Funding: ")), keccak256(bytes(description)))));
        uint256 startBlock = block.number.toUint64();
        uint24 distributionId = grantFund_.getDistributionId();

        (, , uint48 endBlock, , , ) = grantFund_.getDistributionPeriodInfo(distributionId);

        // submit proposal
        changePrank(proposer_);
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            expectedProposalId,
            proposer_,
            targets_,
            values_,
            new string[](targets_.length),
            calldatas_,
            startBlock,
            endBlock,
            description
        );
        uint256 proposalId = grantFund_.proposeStandard(targets_, values_, calldatas_, description);
        assertEq(proposalId, expectedProposalId);

        return _createTestProposalStandard(distributionId, proposalId, targets_, values_, calldatas_, description);
    }

    function _createNProposals(GrantFund grantFund_, IAjnaToken token_, TestProposalParams[] memory testProposalParams_) internal returns (TestProposal[] memory) {
        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(token_);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        TestProposal[] memory testProposals = new TestProposal[](testProposalParams_.length);

        for (uint256 i = 0; i < testProposalParams_.length; ++i) {
            // generate description string from data
            string memory descriptionPartOne = "Proposal to transfer ";
            string memory descriptionPartTwo = Strings.toString(testProposalParams_[i].tokensRequested);
            string memory descriptionPartThree = " tokens to recipient ";
            string memory descriptionPartFour = Strings.toHexString(testProposalParams_[i].recipient);
            string memory description = string(abi.encodePacked(descriptionPartOne, descriptionPartTwo, descriptionPartThree, descriptionPartFour));

            // generate calldata
            bytes[] memory proposalCalldata = new bytes[](1);
            proposalCalldata[0] = abi.encodeWithSignature(
                "transfer(address,uint256)",
                testProposalParams_[i].recipient,
                testProposalParams_[i].tokensRequested
            );

            TestProposal memory proposal = _createProposalStandard(grantFund_, testProposalParams_[i].recipient, ajnaTokenTargets, values, proposalCalldata, description);
            testProposals[i] = proposal;
        }
        return testProposals;
    }

    // return a TestProposal struct containing the state of a created proposal
    function _createTestProposalStandard(uint24 distributionId_, uint256 proposalId_, address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, string memory description) internal view returns (TestProposal memory proposal_) {
        (GeneratedTestProposalParams[] memory params, uint256 totalTokensRequested) = _getGeneratedTestProposalParamsFromParams(targets_, values_, calldatas_);
        proposal_ = TestProposal(proposalId_, distributionId_, description, totalTokensRequested, block.number, params);
    }

    /**
     * @notice Helper function to execute a standard funding mechanism proposal.
     */
    function _executeProposal(GrantFund grantFund_, IAjnaToken token_, TestProposal memory testProposal_) internal {
        // have the first recipient in the list of params execute the proposal, and check their balance change
        address recipient = testProposal_.params[0].recipient;

        // calculate starting balances
        uint256 voterStartingBalance = token_.balanceOf(recipient);
        uint256 growthFundStartingBalance = token_.balanceOf(address(grantFund_));

        bytes32 descriptionHash = grantFund_.getDescriptionHashStandard(testProposal_.description);

        // get parameters from test proposal required for execution
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
        ) = _getParamsFromGeneratedTestProposalParams(token_, testProposal_.params);

        // execute proposal
        changePrank(recipient);
        vm.expectEmit(true, true, false, true);
        emit ProposalExecuted(testProposal_.proposalId);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(grantFund_), recipient, testProposal_.totalTokensRequested);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(recipient, voterStartingBalance, voterStartingBalance + testProposal_.totalTokensRequested);
        grantFund_.executeStandard(targets, values, calldatas, descriptionHash);

        // check ending token balances
        assertEq(token_.balanceOf(recipient), voterStartingBalance + testProposal_.totalTokensRequested);
        assertEq(token_.balanceOf(address(grantFund_)), growthFundStartingBalance - testProposal_.totalTokensRequested);
    }

    function _executeExtraordinaryProposal(GrantFund grantFund_, IAjnaToken token_, TestProposalExtraordinary memory testProposal_) internal {
        // calculate starting balances
        uint256 growthFundStartingBalance = token_.balanceOf(address(grantFund_));
        uint256 totalTokensRequested = 0;
        bytes32 descriptionHash = grantFund_.getDescriptionHashExtraordinary(testProposal_.description, testProposal_.proposer);

        changePrank(testProposal_.proposer);

        vm.expectEmit(true, true, false, true);
        emit ProposalExecuted(testProposal_.proposalId);

        uint256 numberOfParams = testProposal_.params.length;

        address[] memory targets = new address[](numberOfParams);
        uint256[] memory values = new uint256[](numberOfParams);
        bytes[] memory calldatas = new bytes[](numberOfParams); 

        // log out each successive transfer event, calculate total tokens requested, and create expected arrays for each parameter
        for (uint256 i = 0; i < numberOfParams; ++i) {
            GeneratedTestProposalParams memory param = testProposal_.params[i];
            totalTokensRequested += param.tokensRequested;

            uint256 currentVoterBalance = token_.balanceOf(param.recipient);

            // create separate arrays for each parameter
            targets[i] = address(token_);
            values[i] = 0;
            calldatas[i] = param.calldatas;

            vm.expectEmit(true, true, false, true);
            emit Transfer(address(grantFund_), param.recipient, param.tokensRequested);
            vm.expectEmit(true, true, false, true);
            emit DelegateVotesChanged(param.recipient, currentVoterBalance, currentVoterBalance + param.tokensRequested);
        }

        // execute proposal
        grantFund_.executeExtraordinary(targets, values, calldatas, descriptionHash);

        // check grant fund token balance change
        assertEq(token_.balanceOf(address(grantFund_)), growthFundStartingBalance - totalTokensRequested);
    }

    function _getParamsFromGeneratedTestProposalParams(IAjnaToken token_, GeneratedTestProposalParams[] memory params_) internal pure returns(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, uint256 totalTokensRequested_) {
        uint256 numberOfParams = params_.length;

        targets_ = new address[](numberOfParams);
        values_ = new uint256[](numberOfParams);
        calldatas_ = new bytes[](numberOfParams);

        // create expected arrays for each parameter
        for (uint256 i = 0; i < numberOfParams; ++i) {
            GeneratedTestProposalParams memory param = params_[i];

            // accumulate additional tokens requested
            totalTokensRequested_ += param.tokensRequested;

            // create separate arrays for each parameter
            targets_[i] = address(token_);
            values_[i] = 0;
            calldatas_[i] = param.calldatas;
        }
    }

    function _getGeneratedTestProposalParamsFromParams(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_) internal pure returns(GeneratedTestProposalParams[] memory params_, uint256 totalTokensRequested_) {
        uint256 numberOfParams = targets_.length;

        params_ = new GeneratedTestProposalParams[](numberOfParams);

        // create expected arrays for each parameter
        for (uint256 i = 0; i < numberOfParams; ++i) {
            // https://github.com/ethereum/solidity/issues/6012
            (, address recipient, uint256 tokensRequested) = abi.decode(
                abi.encodePacked(bytes28(0), calldatas_[i]),
                (bytes32,address,uint256)
            );

            totalTokensRequested_ += tokensRequested;

            params_[i] = GeneratedTestProposalParams(targets_[i], values_[i], calldatas_[i], recipient, tokensRequested);
        }
    }

    // Returns a random proposal Index from all proposals
    function _getRandomProposal(uint256 noOfProposals_) internal returns(uint256 proposal_) {
        // calculate random proposal Index between 0 and noOfProposals_
        proposal_ = uint256(keccak256(abi.encodePacked(block.number, block.prevrandao))) % noOfProposals_;
        vm.roll(block.number + 1);
    }

    // Submits N Proposal with fixed token requested
    function _getProposals(uint256 noOfProposals_, GrantFund grantFund_, address proponent_, IAjnaToken token_) internal returns(TestProposal[] memory) {

        TestProposal[] memory proposals_ = new TestProposal[](noOfProposals_);

        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(token_);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            proponent_,
            1_000_000 * 1e18
        );

        for(uint i = 0; i < noOfProposals_; i++) {
            // generate proposal message 
            string memory description = string(abi.encodePacked("Proposal", Strings.toString(i)));
            proposals_[i] = _createProposalStandard(grantFund_, proponent_, ajnaTokenTargets, values, proposalCalldata, description); 
        }
        return proposals_;
    }

    function _getProposalListFromProposalIds(GrantFund grantFund_, uint256[] memory proposalIds_) internal view returns (GrantFund.Proposal[] memory) {
        GrantFund.Proposal[] memory proposals = new GrantFund.Proposal[](proposalIds_.length);
        for (uint256 i = 0; i < proposalIds_.length; ++i) {
            (
                proposals[i].proposalId,
                proposals[i].distributionId,
                proposals[i].votesReceived,
                proposals[i].tokensRequested,
                proposals[i].fundingVotesReceived,
                proposals[i].executed
            ) = grantFund_.getProposalInfo(proposalIds_[i]);
        }
        return proposals;
    }

    // Submits N Extra Ordinary Proposals
    function _getNExtraOridinaryProposals(uint256 noOfProposals_, GrantFund grantFund_, address proponent_, IAjnaToken token_, uint256 tokenRequested_) internal returns(TestProposalExtraordinary[] memory) {
        TestProposalExtraordinary[] memory proposals_ = new TestProposalExtraordinary[](noOfProposals_);

        // generate proposal targets
        address[] memory ajnaTokenTargets = new address[](1);
        ajnaTokenTargets[0] = address(token_);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory proposalCalldata = new bytes[](1);
        proposalCalldata[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            proponent_,
            tokenRequested_
        );

        for(uint i = 0; i < noOfProposals_; i++) {
            // generate proposal message 
            string memory description = string(abi.encodePacked("Proposal", Strings.toString(i)));

            // submit proposal with 1 month end time
            proposals_[i] = _createProposalExtraordinary(grantFund_, proponent_, block.number + 216_000, ajnaTokenTargets, values, proposalCalldata, description);
        }
        return proposals_;
    }

    function generateProposalParams(address ajnaToken_, TestProposalParams[] memory testProposalParams_) internal view
        returns(
            address[] memory targets_,
            uint256[] memory values_,
            bytes[] memory calldatas_,
            string memory description_
        ) {

        uint256 numParams = testProposalParams_.length;
        targets_ = new address[](numParams);
        values_ = new uint256[](numParams);
        calldatas_ = new bytes[](numParams);

        // generate description string
        string memory descriptionPartOne = "Proposal to transfer ";
        string memory descriptionPartTwo;

        for (uint256 i = 0; i < numParams; ++i) {
            targets_[i] = ajnaToken_;
            values_[i] = 0;
            calldatas_[i] = abi.encodeWithSignature(
                "transfer(address,uint256)",
                testProposalParams_[i].recipient,
                testProposalParams_[i].tokensRequested
            );
            descriptionPartTwo = string.concat(descriptionPartTwo, Strings.toString(testProposalParams_[i].tokensRequested));
            descriptionPartTwo = string.concat(descriptionPartTwo, " tokens to recipient: ");
            descriptionPartTwo = string.concat(descriptionPartTwo, Strings.toHexString(uint160(testProposalParams_[i].recipient), 20));
            descriptionPartTwo = string.concat(descriptionPartTwo, ", ");

            // generate a random nonce to add to the description string to avoid collisions
            uint256 randomNonce = uint256(keccak256(abi.encodePacked(block.number, block.prevrandao))) % 100;
            descriptionPartTwo = string.concat(descriptionPartTwo, Strings.toString(randomNonce));
        }
        description_ = string(abi.encodePacked(descriptionPartOne, descriptionPartTwo));
    }

    // check for duplicate proposalIds in the provided array
    function hasDuplicates(
        uint256[] memory proposalIds_
    ) public pure returns (bool) {
        uint256 numProposals = proposalIds_.length;

        for (uint i = 0; i < numProposals; ) {
            for (uint j = i + 1; j < numProposals; ) {
                if (proposalIds_[i] == proposalIds_[j]) return true;

                unchecked { ++j; }
            }

            unchecked { ++i; }

        }
        return false;
    }

    function getTokensRequestedInFundedSlate(GrantFund grantFund_, bytes32 slateHash_) public view returns (uint256 tokensRequested_) {
        uint256[] memory fundedProposals = grantFund_.getFundedProposalSlate(slateHash_);
        for (uint256 i = 0; i < fundedProposals.length; ++i) {
            (, , , uint128 tokensRequested, int128 fundingVotesReceived, ) = grantFund_.getProposalInfo(fundedProposals[i]);
            if (fundingVotesReceived > 0) {
                tokensRequested_ += tokensRequested;
            }
        }
    }

    function getSurplusTokensInDistribution(GrantFund grantFund_, uint24 distributionId_) public view returns (uint256 surplus_) {
        (, , , uint128 fundsAvailable, , bytes32 topSlateHash) = grantFund_.getDistributionPeriodInfo(distributionId_);
        uint256 tokensRequested = getTokensRequestedInFundedSlate(grantFund_, topSlateHash);
        surplus_ = fundsAvailable - tokensRequested;
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    function _extraordinaryVote(GrantFund grantFund_, address voter_, uint256 proposalId_, uint8 support_) internal {
        uint256 votingWeight = grantFund_.getVotesExtraordinary(voter_, proposalId_);

        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, votingWeight, "");
        grantFund_.voteExtraordinary(proposalId_);
    }

    function _findProposalIndex(
        uint256 proposalId_,
        uint256[] memory array_
    ) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array
        int256 arrayLength = int256(array_.length);

        for (int256 i = 0; i < arrayLength;) {
            // slither-disable-next-line incorrect-equality
            if (array_[uint256(i)] == proposalId_) {
                index_ = i;
                break;
            }

            unchecked { ++i; }
        }
    }

    function _findProposalIndexOfVotesCast(
        uint256 proposalId_,
        IStandardFunding.FundingVoteParams[] memory voteParams_
    ) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array

        // since we are converting from uint256 to int256, we can safely assume that the value will not overflow
        int256 numVotesCast = int256(voteParams_.length);
        for (int256 i = 0; i < numVotesCast; ) {
            // slither-disable-next-line incorrect-equality
            if (voteParams_[uint256(i)].proposalId == proposalId_) {
                index_ = i;
                break;
            }

            unchecked { ++i; }
        }
    }

    function _fundingVote(GrantFund grantFund_, address voter_, uint256 proposalId_, uint8 support_, int256 votesAllocated_) internal {
        // convert negative votes to account for budget expenditure and check emit value
        uint256 voteAllocatedEmit;
        if (votesAllocated_ < 0) {
            voteAllocatedEmit = uint256(votesAllocated_ * -1);
        }
        else {
            voteAllocatedEmit = uint256(votesAllocated_);
        }

        // construct vote params
        IStandardFunding.FundingVoteParams[] memory params = new IStandardFunding.FundingVoteParams[](1);
        params[0].proposalId = proposalId_;
        params[0].votesUsed = votesAllocated_;

        // cast funding vote
        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support_, voteAllocatedEmit, "");
        grantFund_.fundingVote(params);
    }

    function _fundingVoteMulti(GrantFund grantFund_, IStandardFunding.FundingVoteParams[] memory voteParams_, address voter_) internal {
        for (uint256 i = 0; i < voteParams_.length; ++i) {
            uint8 support = voteParams_[i].votesUsed < 0 ? 0 : 1;
            vm.expectEmit(true, true, false, true);
            emit VoteCast(voter_, voteParams_[i].proposalId, support, uint256(Maths.abs(voteParams_[i].votesUsed)), "");
        }
        changePrank(voter_);
        grantFund_.fundingVote(voteParams_);
    }

    function _fundingVoteNoLog(GrantFund grantFund_, address voter_, uint256 proposalId_, int256 votesAllocated_) internal {
        // construct vote params
        IStandardFunding.FundingVoteParams[] memory params = new IStandardFunding.FundingVoteParams[](1);
        params[0].proposalId = proposalId_;
        params[0].votesUsed = votesAllocated_;

        // cast funding vote
        changePrank(voter_);
        grantFund_.fundingVote(params);
    }

    function _screeningVote(GrantFund grantFund_, address voter_, uint256 proposalId_, uint256 votesAllocated_) internal {
        uint8 support = 1; // can only vote yes in the screening stage

        // construct vote params
        IStandardFunding.ScreeningVoteParams[] memory params = new IStandardFunding.ScreeningVoteParams[](1);
        params[0].proposalId = proposalId_;
        params[0].votes = votesAllocated_;

        changePrank(voter_);
        vm.expectEmit(true, true, false, true);
        emit VoteCast(voter_, proposalId_, support, votesAllocated_, "");
        grantFund_.screeningVote(params);
    }

    function _screeningVote(GrantFund grantFund_, IStandardFunding.ScreeningVoteParams[] memory voteParams_, address voter_) internal {
        for (uint256 i = 0; i < voteParams_.length; ++i) {
            vm.expectEmit(true, true, false, true);
            emit VoteCast(voter_, voteParams_[i].proposalId, 1, voteParams_[i].votes, "");
        }
        changePrank(voter_);
        grantFund_.screeningVote(voteParams_);
    }

    function _screeningVoteNoLog(GrantFund grantFund_, address voter_, uint256 proposalId_, uint256 votesAllocated_) internal {
        // construct vote params
        IStandardFunding.ScreeningVoteParams[] memory params = new IStandardFunding.ScreeningVoteParams[](1);
        params[0].proposalId = proposalId_;
        params[0].votes = votesAllocated_;

        changePrank(voter_);
        grantFund_.screeningVote(params);
    }

    // Transfers a random amount of tokens to N voters and self delegates votes
    function _setVotingPower(uint256 noOfVoters_, address[] memory voters_, IAjnaToken token_, address tokenDeployer_) internal returns(uint256[] memory) {
        uint256[] memory votes_ = new uint256[](noOfVoters_);
        for(uint i = 0; i < noOfVoters_; i++) {
            uint256 votes = _randomVote();
            changePrank(tokenDeployer_);
            token_.transfer(voters_[i], votes);
            changePrank(voters_[i]);
            token_.delegate(voters_[i]);
            votes_[i] = votes;
        }
        return votes_;
    }

    // Returns a voters address array with N voters 
    function _getVoters(uint256 noOfVoters_) internal returns(address[] memory) {
        address[] memory voters_ = new address[](noOfVoters_);
        for(uint i = 0; i < noOfVoters_; i++) {
            voters_[i] = makeAddr(string(abi.encodePacked("Voter", Strings.toString(i))));
        }
        return voters_;
    }

    function _getScreeningVotes(GrantFund grantFund_, address voter_) internal view returns (uint256 votes) {
        votes = grantFund_.getVotesScreening(grantFund_.getDistributionId(), voter_);
    }

    function _getFundingVotes(GrantFund grantFund_, address voter_) internal view returns (uint256 votes) {
        votes = grantFund_.getVotesFunding(grantFund_.getDistributionId(), voter_);
    }

    // Returns random votes for a user
    function _randomVote() internal returns (uint256 votes_) {
        // calculate random vote between 1 and 1.25 * 1e18
        votes_ = 1 + uint256(keccak256(abi.encodePacked(block.number, block.prevrandao))) % (1.25 * 1e18);
        vm.roll(block.number + 1);
    }

    /***************/
    /*** Asserts ***/
    /***************/

    function assertInsufficientVotingPowerRevert(GrantFund grantFund_, address voter_, uint256 proposalId_, int256 votesAllocated_) internal {
        vm.expectRevert(IStandardFunding.InsufficientVotingPower.selector);
        _fundingVoteNoLog(grantFund_, voter_, proposalId_, votesAllocated_);
    }

    function assertInsufficientRemainingVotingPowerRevert(GrantFund grantFund_, address voter_, uint256 proposalId_, int256 votesAllocated_) internal {
        vm.expectRevert(IStandardFunding.InsufficientRemainingVotingPower.selector);
        _fundingVoteNoLog(grantFund_, voter_, proposalId_, votesAllocated_);
    }

    function assertFundingVoteInvalidVoteRevert(GrantFund grantFund_, address voter_, uint256 proposalId_, int256 votesAllocated_) internal {
        vm.expectRevert(IFunding.InvalidVote.selector);
        _fundingVoteNoLog(grantFund_, voter_, proposalId_, votesAllocated_);
    }

    function assertScreeningVoteInvalidVoteRevert(GrantFund grantFund_, address voter_, uint256 proposalId_, uint256 votesAllocated_) internal {
        vm.expectRevert(IFunding.InvalidVote.selector);
        _screeningVoteNoLog(grantFund_, voter_, proposalId_, votesAllocated_);
    }

    function assertInferiorSlateFalse(GrantFund grantFund_, uint256[] memory potentialSlate_, uint24 distributionId_) internal {
        assertFalse(grantFund_.updateSlate(potentialSlate_, distributionId_));
    }

    function assertExecuteExtraordinaryProposalInvalidRevert(GrantFund grantFund_, IAjnaToken token_, TestProposalExtraordinary memory testProposal_) internal {
        changePrank(testProposal_.proposer);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
        ) = _getParamsFromGeneratedTestProposalParams(token_, testProposal_.params);

        bytes32 descriptionHash = grantFund_.getDescriptionHashExtraordinary(testProposal_.description, testProposal_.proposer);

        // execute proposal
        vm.expectRevert(IExtraordinaryFunding.ExecuteExtraordinaryProposalInvalid.selector);
        grantFund_.executeExtraordinary(targets, values, calldatas, descriptionHash);
    }

    function assertExecuteProposalRevert(GrantFund grantFund_, IAjnaToken token_, TestProposal memory testProposal_, bytes4 selector_) internal {
        address recipient = testProposal_.params[0].recipient;
        bytes32 descriptionHash = grantFund_.getDescriptionHashStandard(testProposal_.description);

        // get parameters from test proposal required for execution
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
        ) = _getParamsFromGeneratedTestProposalParams(token_, testProposal_.params);

        // execute proposal
        changePrank(recipient);
        vm.expectRevert(selector_);
        grantFund_.executeStandard(targets, values, calldatas, descriptionHash);
    }

    function assertStandardProposalState(
        GrantFund grantFund_,
        TestProposal memory proposal,
        uint24 expectedDistributionId_,
        uint256 expectedVotesReceived_,
        uint256 expectedTokensRequested_,
        int256 expectedFundingPowerCast_,
        bool expectedExecuted_
    ) internal returns (uint256) {
        (
            uint256 proposalId,
            uint256 distributionId,
            uint256 votesReceived,
            uint256 tokensRequested,
            int256 qvBudgetAllocated,
            bool executed
        ) = grantFund_.getProposalInfo(proposal.proposalId);

        assertEq(proposalId, proposal.proposalId);
        assertEq(distributionId, expectedDistributionId_);
        assertEq(votesReceived, expectedVotesReceived_);
        assertEq(tokensRequested, expectedTokensRequested_);
        assertEq(qvBudgetAllocated, expectedFundingPowerCast_);
        assertEq(executed, expectedExecuted_);

        return proposalId;
    }

}
