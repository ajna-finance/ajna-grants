// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";
import { Test }     from "forge-std/Test.sol";
import { Math }     from "@oz/utils/math/Math.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings }  from "@oz/utils/Strings.sol";
import { Math }     from "@oz/utils/math/Math.sol";

import { GrantFund }       from "../../../src/grants/GrantFund.sol";
import { IGrantFundState } from "../../../src/grants/interfaces/IGrantFundState.sol";
import { Maths }           from "../../../src/grants/libraries/Maths.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { Handler }             from "./Handler.sol";

contract StandardHandler is Handler {

    /***********************/
    /*** State Variables ***/
    /***********************/

    // proposalId of proposals executed
    uint256[] public proposalsExecuted;

    // number of proposals that recieved a vote in the given stage
    uint256 public screeningVotesCast;
    uint256 public fundingVotesCast;

    struct VotingActor {
        IGrantFundState.FundingVoteParams[] fundingVotes; // list of funding votes made by an actor
        IGrantFundState.ScreeningVoteParams[] screeningVotes; // list of screening votes made by an actor
        uint256 delegationRewardsClaimed; // the amount of delegation rewards claimed by the actor
    }

    struct DistributionState {
        uint256 treasuryBeforeStart;
        uint256 treasuryAtStartBlock; // GrantFund treasury at the time startNewDistributionPeriod was called.
        bytes32 currentTopSlate; // slate hash of the current top proposal slate
        Slate[] topSlates; // assume that the last element in the list is the top slate
        bool treasuryUpdated; // whether the distribution period's surplus tokens have been readded to the treasury
        uint256 totalRewardsClaimed; // total delegation rewards claimed in a distribution period
        bytes32 topTenHashAtLastScreeningVote; // slate hash of top ten proposals at the last time a sreening vote is cast
    }

    struct Slate {
        uint24 distributionId;
        uint256 updateBlock;
        bytes32 slateHash;
        uint256 totalTokensRequested; // total tokens requested by all proposals in the slate
    }

    mapping(uint24 => uint256[]) public standardFundingProposals;             // distributionId => proposalId[]
    mapping(uint24 => DistributionState) public distributionStates;           // distributionId => DistributionState
    mapping(bytes32 => uint256[]) public proposalsInTopSlate;                 // slateHash => proposalId[]
    mapping(address => mapping(uint24 => VotingActor)) internal votingActors; // actor => distributionId => VotingActor
    mapping(uint256 => TestProposal) public testProposals;                    // proposalId => TestProposal
    mapping(uint24 => bool) public distributionIdSurplusAdded;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(
        address payable grantFund_,
        address token_,
        address tokenDeployer_,
        uint256 numOfActors_,
        uint256 treasury_,
        address testContract_
    ) Handler(grantFund_, token_, tokenDeployer_, numOfActors_, treasury_, testContract_) {}

    /*************************/
    /*** Wrapped Functions ***/
    /*************************/

    function startNewDistributionPeriod(uint256 actorIndex_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['SFH.startNewDistributionPeriod']++;

        uint24 newDistributionId = _grantFund.getDistributionId() + 1;
        uint256 treasuryBeforeStart = _grantFund.treasury();
        try _grantFund.startNewDistributionPeriod() returns (uint24 newDistributionId_) {
            assertEq(newDistributionId, newDistributionId_);
            distributionStates[newDistributionId].treasuryAtStartBlock = _grantFund.treasury();
            distributionStates[newDistributionId].treasuryBeforeStart = treasuryBeforeStart;
            vm.roll(block.number + 100);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("DistributionPeriodStillActive()")),
                UNEXPECTED_REVERT
            );
        }
    }

    function propose(uint256 actorIndex_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['SFH.propose']++;

        uint24 distributionId = _grantFund.getDistributionId();
        if (distributionId == 0) return;

        // get a random number between 1 and 5
        uint256 numProposalParams = constrictToRange(randomSeed(), 1, 5);

        // generate list of recipients and tokens requested
        TestProposalParams[] memory testProposalParams = generateTestProposalParams(numProposalParams);

        // generate proposal params
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = generateProposalParams(address(_ajna), testProposalParams);

        try _grantFund.propose(targets, values, calldatas, description) returns (uint256 proposalId) {
            standardFundingProposals[distributionId].push(proposalId);

            // record proposal information into TestProposal struct
            _recordTestProposal(proposalId, distributionId, targets, values, calldatas, description);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("ProposalAlreadyExists()")) ||
                err == keccak256(abi.encodeWithSignature("ScreeningPeriodEnded()")) ||
                err == keccak256(abi.encodeWithSignature("InvalidProposal()")),
                UNEXPECTED_REVERT
            );
        }
    }

    function screeningVote(uint256 actorIndex_, uint256 proposalsToVoteOn_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['SFH.screeningVote']++;

        uint24 distributionId = _grantFund.getDistributionId();
        if (distributionId == 0) return;

        // get a random number less than the number of submitted proposals
        proposalsToVoteOn_ = constrictToRange(proposalsToVoteOn_, 0, standardFundingProposals[distributionId].length);

        vm.roll(block.number + 100);

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), _actor);

        // construct vote params
        IGrantFundState.ScreeningVoteParams[] memory screeningVoteParams = new IGrantFundState.ScreeningVoteParams[](proposalsToVoteOn_);
        for (uint256 i = 0; i < proposalsToVoteOn_; i++) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // generate screening vote params
            screeningVoteParams[i] = IGrantFundState.ScreeningVoteParams({
                proposalId: proposalId,
                votes: constrictToRange(randomSeed(), 0, votingPower) // TODO: account for previously used voting power in a happy path scenario
            });
        }

        try _grantFund.screeningVote(screeningVoteParams) {
            // update actor screeningVotes if vote was successful
            VotingActor storage actor = votingActors[_actor][distributionId];

            for (uint256 i = 0; i < proposalsToVoteOn_; ) {
                actor.screeningVotes.push(screeningVoteParams[i]);
                screeningVotesCast++;

                ++i;
            }
            distributionStates[distributionId].topTenHashAtLastScreeningVote = keccak256(abi.encode(_grantFund.getTopTenProposals(distributionId)));
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()")),
                UNEXPECTED_REVERT
            );
        }
    }

    function fundingVote(uint256 actorIndex_, uint256 proposalsToVoteOn_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['SFH.fundingVote']++;

        // check where block is in the distribution period
        uint24 distributionId = _grantFund.getDistributionId();
        if (distributionId == 0) return;

        if (_grantFund.getStage() != keccak256(bytes("Funding"))) {
            return;
        }

        // if actors voting power is 0, return
        if (_grantFund.getVotesFunding(distributionId, _actor) == 0) return;

        // bind proposalsToVoteOn_ to the number of proposals
        proposalsToVoteOn_ = constrictToRange(proposalsToVoteOn_, 1, standardFundingProposals[distributionId].length);

        // TODO: switch this to true or false? potentially also move flip coin up
        // get the fundingVoteParams for the votes the actor is about to cast
        // take the chaotic path, and cast votes that will likely exceed the actor's voting power
        IGrantFundState.FundingVoteParams[] memory fundingVoteParams = _fundingVoteParams(_actor, distributionId, proposalsToVoteOn_, true);

        try _grantFund.fundingVote(fundingVoteParams) returns (uint256 votesCast) {
            numberOfCalls['SFH.fundingVote.success']++;

            // check votesCast is equal to the sum of votes cast
            assertEq(votesCast, sumFundingVotes(fundingVoteParams));

            // update actor funding votes counts
            // find and replace previous vote record for that proposlId, in that distributonId
            VotingActor storage actor = votingActors[_actor][distributionId];
            for (uint256 i = 0; i < proposalsToVoteOn_; ) {

                // update existing proposal voting record as opposed to a new entry in the list
                int256 voteCastIndex = _findProposalIndexOfVotesCast(fundingVoteParams[i].proposalId, actor.fundingVotes);
                // voter had already cast a funding vote on this proposal
                if (voteCastIndex != -1) {
                    actor.fundingVotes[uint256(voteCastIndex)].votesUsed += fundingVoteParams[i].votesUsed;
                }
                else {
                    actor.fundingVotes.push(fundingVoteParams[i]);
                }

                fundingVotesCast++;

                ++i;
            }

        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()")) ||
                err == keccak256(abi.encodeWithSignature("FundingVoteWrongDirection()")),
                UNEXPECTED_REVERT
            );
        }
    }

    function updateSlate(uint256 actorIndex_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['SFH.updateSlate']++;

        uint24 distributionId = _grantFund.getDistributionId();
        if (distributionId == 0) return;

        // check that the distribution period ended
        if (_grantFund.getStage() != keccak256(bytes("Challenge"))) {
            return;
        }

        // get top ten proposals
        uint256[] memory topTen = _grantFund.getTopTenProposals(distributionId);

        // construct potential slate of proposals
        uint256 potentialSlateLength = 1;
        uint256[] memory potentialSlate = new uint256[](potentialSlateLength);

        bool happyPath = true;
        if (happyPath) {
            (, , , , , bytes32 slateHash) = _grantFund.getDistributionPeriodInfo(distributionId);
            uint256[] memory currentSlate = _grantFund.getFundedProposalSlate(slateHash);
            if (currentSlate.length < 9 && currentSlate.length > 0) {
                numberOfCalls['SFH.updateSlate.prep']++;
                potentialSlateLength = currentSlate.length + 1;
            }
            numberOfCalls['updateSlate.length'] = potentialSlateLength;
            potentialSlate = new uint256[](potentialSlateLength);

            // get subset of top ten in order
            for (uint i = 0; i < potentialSlateLength; ++i) {
                potentialSlate[i] = _findUnusedProposalId(potentialSlate, topTen);
                numberOfCalls['unused.proposal'] = potentialSlate[i];
            }
        }
        else {
            // get random potentialSlate of proposals, may contain duplicates
            for (uint i = 0; i < potentialSlateLength; ++i) {
                potentialSlate[i] = topTen[randomSeed() % 10];
            }
        }

        try _grantFund.updateSlate(potentialSlate, distributionId) returns (bool newTopSlate) {
            numberOfCalls['SFH.updateSlate.called']++;
            if (newTopSlate) {
                numberOfCalls['SFH.updateSlate.success']++;

                numberOfCalls['proposalsInSlates'] += potentialSlateLength;

                bytes32 potentialSlateHash = keccak256(abi.encode(potentialSlate));

                Slate memory slate;
                slate.distributionId = distributionId;
                slate.slateHash = potentialSlateHash;
                slate.updateBlock = block.number;
                slate.totalTokensRequested = getTokensRequestedInFundedSlateInvariant(potentialSlateHash);

                // update distribution state
                DistributionState storage distribution = distributionStates[distributionId];
                distribution.currentTopSlate = potentialSlateHash;
                distribution.topSlates.push(slate);

                // update list of proposals in top slate
                for (uint i = 0; i < potentialSlateLength; ++i) {
                    proposalsInTopSlate[distribution.currentTopSlate].push(potentialSlate[i]);
                }
            }
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidProposalSlate()")),
                UNEXPECTED_REVERT
            );
        }
    }

    function execute(uint256 actorIndex_, uint256) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['SFH.execute']++;

        uint24 distributionId = _grantFund.getDistributionId();
        if (distributionId == 0) return;

        // TODO: implement unhappy path
        uint256 proposalId = _findUnexecutedProposalId(distributionId);
        TestProposal memory proposal = testProposals[proposalId];
        numberOfCalls['unexecuted.proposal'] = proposalId;

        // get parameters from test proposal required for execution
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
        ) = _getParamsFromGeneratedTestProposalParams(_ajna, proposal.params);

        numberOfCalls['SFH.execute.attempt']++;

        try _grantFund.execute(targets, values, calldatas, keccak256(bytes(proposal.description))) returns (uint256 proposalId_) {
            assertEq(proposalId_, proposal.proposalId);
            numberOfCalls['SFH.execute.success']++;
            proposalsExecuted.push(proposalId_);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("ExecuteProposalInvalid()")) ||
                err == keccak256(abi.encodeWithSignature("ProposalNotSuccessful()")),
                UNEXPECTED_REVERT
            );
        }
    }

    function claimDelegateReward(uint256 actorIndex_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['SFH.claimDelegateReward']++;

        uint24 distributionId = _grantFund.getDistributionId();
        if (distributionId == 0) return;

        uint24 distributionIdToClaim = _findUnclaimedReward(_actor, distributionId);

        try _grantFund.claimDelegateReward(distributionIdToClaim) returns (uint256 rewardClaimed_) {
            numberOfCalls['SFH.claimDelegateReward.success']++;

            // should only be able to claim delegation rewards once
            assertEq(votingActors[_actor][distributionIdToClaim].delegationRewardsClaimed, 0);

            // rewards should be non zero
            assertTrue(rewardClaimed_ > 0);

            // record the newly claimed rewards
            votingActors[_actor][distributionIdToClaim].delegationRewardsClaimed = rewardClaimed_;
            distributionStates[distributionIdToClaim].totalRewardsClaimed += rewardClaimed_;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("DelegateRewardInvalid()"))   ||
                err == keccak256(abi.encodeWithSignature("DistributionPeriodStillActive()")) ||
                err == keccak256(abi.encodeWithSignature("RewardAlreadyClaimed()")),
                UNEXPECTED_REVERT
            );
        }
    }

    /**********************************/
    /*** External Utility Functions ***/
    /**********************************/

    // create a given number of proposals
    function createProposals(uint256 numProposals) external returns (uint256[] memory proposalIds_) {
        proposalIds_ = _createProposals(numProposals);
    }

    // make each actor cast funding stage votes on a random number of proposals
    function fundingVoteProposals() external {
        for (uint256 i = 0; i < actors.length; ++i) {
            // get an actor who hasn't already voted
            address actor = actors[i];

            // actor votes on random number of proposals
            _fundingVoteProposal(actor, constrictToRange(randomSeed(), 1, 10));
        }
    }

    // make each actor cast screening stage votes on a random number of proposals
    function screeningVoteProposals() external {
        for (uint256 i = 0; i < actors.length; ++i) {
            // get an actor who hasn't already voted
            address actor = actors[i];

            // actor votes on random number of proposals
            _screeningVoteProposal(actor);
        }
    }

    function setDistributionTreasuryUpdated(uint24 distributionId_) public {
        distributionStates[distributionId_].treasuryUpdated = true;
        distributionIdSurplusAdded[distributionId_] = true;
    }

    // updates invariant test treasury state
    function updateTreasury(uint24 distributionId_, uint256 fundsAvailable_, bytes32 slateHash_) public returns (uint256 surplus_) {
        uint256 totalDelegateRewards = (fundsAvailable_ / 10);
        surplus_ += fundsAvailable_ - (totalDelegateRewards + getTokensRequestedInFundedSlateInvariant(slateHash_));
        setDistributionTreasuryUpdated(distributionId_);
    }

    /**********************************/
    /*** Internal Utility Functions ***/
    /**********************************/

    function generateTestProposalParams(uint256 numParams_) internal returns (TestProposalParams[] memory testProposalParams_) {
        testProposalParams_ = new TestProposalParams[](numParams_);

        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < numParams_; ++i) {
            // get distribution info
            uint24 distributionId = _grantFund.getDistributionId();
            (, , , uint128 fundsAvailable, , ) = _grantFund.getDistributionPeriodInfo(distributionId);

            // account for amount that was previously requested
            uint256 additionalTokensRequested = randomAmount(uint256(fundsAvailable * 9 /10) - totalTokensRequested);
            totalTokensRequested += additionalTokensRequested;

            testProposalParams_[i] = TestProposalParams({
                recipient: randomActor(),
                tokensRequested: additionalTokensRequested
            });
        }
    }

    function randomProposal() internal returns (uint256) {
        uint24 distributionId = _grantFund.getDistributionId();
        if (standardFundingProposals[distributionId].length == 0) return 0;
        return standardFundingProposals[distributionId][constrictToRange(randomSeed(), 0, standardFundingProposals[distributionId].length - 1)];
    }

    function _createProposals(uint256 numProposals_) internal returns (uint256[] memory proposalIds_) {
        proposalIds_ = new uint256[](numProposals_);
        for (uint256 i = 0; i < numProposals_; ++i) {
            proposalIds_[i] = _createProposal();
        }
    }

    function _createProposal() internal useRandomActor(randomSeed()) returns (uint256 proposalId_) {
        uint24 distributionId = _grantFund.getDistributionId();

        // get a random number between 1 and 5
        uint256 numProposalParams = constrictToRange(randomSeed(), 1, 5);

        // generate list of recipients and tokens requested
        TestProposalParams[] memory testProposalParams = generateTestProposalParams(numProposalParams);

        // generate proposal params
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = generateProposalParams(address(_ajna), testProposalParams);

        // create proposal
        proposalId_ = _grantFund.propose(targets, values, calldatas, description);

        // add new proposal to list of all standard proposals
        standardFundingProposals[distributionId].push(proposalId_);

        // record proposal information into TestProposal struct
        _recordTestProposal(proposalId_, distributionId, targets, values, calldatas, description);
    }

    // if taking the happy path, array length may not match numProposalsToVoteOn_
    function _fundingVoteParams(
        address actor_,
        uint24 distributionId_,
        uint256 numProposalsToVoteOn_,
        bool happyPath_
    ) internal returns (IGrantFundState.FundingVoteParams[] memory fundingVoteParams_) {

        (uint256 votingPower, uint256 remainingVotingPower, ) = _grantFund.getVoterInfo(distributionId_, actor_);
        uint256 votingPowerUsed = votingPower - remainingVotingPower;
        if (votingPower == 0) {
            votingPower = _grantFund.getVotesFunding(distributionId_, actor_);
            votingPowerUsed = 0;
        }

        fundingVoteParams_ = new IGrantFundState.FundingVoteParams[](numProposalsToVoteOn_);

        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(distributionId_);

        // generate the array of fundingVoteParams structs
        uint256 i = 0;
        for (i; i < numProposalsToVoteOn_; ) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // get the random number of votes to cast
            // Take the square root of the voting power to determine how many votes are actually available for casting
            int256 votesToCast = int256(constrictToRange(randomSeed(), 1, Math.sqrt(votingPower)));

            // if we should account for previous votes, then we need to make sure that the votes used are less than the available votes
            // flag is useful for generating vote params for a happy path required for test setup, as well as the chaotic path.
            if (happyPath_) {
                votesToCast = int256(constrictToRange(randomSeed(), 0, Math.sqrt(votingPower - votingPowerUsed)));

                // if taking the happy path, set proposalId to a random proposal in the top ten
                if (_findProposalIndexOfVotesCast(proposalId, fundingVoteParams_) == -1) {
                    proposalId = topTenProposals[constrictToRange(randomSeed(), 0, topTenProposals.length - 1)];
                }

                // check for any previous votes on this proposal
                int256 priorVoteIndex = -1;
                IGrantFundState.FundingVoteParams[] memory priorVotes = votingActors[actor_][distributionId_].fundingVotes;
                for (uint256 j = 0; j < priorVotes.length; ++j) {
                    // if we have already voted on this proposal, then we need to update the votes used
                    if (priorVotes[j].proposalId == proposalId) {
                        votingPowerUsed += Maths.wpow(uint256(Maths.abs(priorVotes[j].votesUsed + votesToCast)), 2);
                        priorVoteIndex = int256(j);
                        break;
                    }
                }

                // Need to account for a proposal prior vote direction in test setup
                if (priorVoteIndex != -1) {
                    // check if prior vote was negative
                    if (priorVotes[uint256(priorVoteIndex)].votesUsed < 0) {
                        votesToCast = votesToCast * -1;
                    }
                }
                else {
                    votingPowerUsed += Maths.wpow(uint256(Maths.abs(votesToCast)), 2);
                }

                // check if additional vote would break the happy path
                if (Maths.wpow(Maths.abs(votesToCast), 2) > votingPower - votingPowerUsed) {
                    // resize array before breaking out of the happy path
                    assembly { mstore(fundingVoteParams_, i) }
                    break;
                }

                // generate funding vote params
                fundingVoteParams_[i] = IGrantFundState.FundingVoteParams({
                    proposalId: proposalId,
                    votesUsed: votesToCast
                });

                // start voting on the next proposal
                ++i;
            }
            else {
                // TODO: move flip coin into happy path
                // flip a coin to see if should instead use a negative vote
                if (randomSeed() % 2 == 0) {
                    numberOfCalls['SFH.negativeFundingVote']++;
                    // generate negative vote
                    fundingVoteParams_[i] = IGrantFundState.FundingVoteParams({
                        proposalId: proposalId,
                        votesUsed: -1 * votesToCast
                    });
                    ++i;
                    continue;
                }
            }
        }
    }

    function _screeningVoteParams(
        address actor_,
        uint24 distributionId_,
        uint256 numProposalsToVoteOn_,
        bool happyPath_
    ) internal returns (IGrantFundState.ScreeningVoteParams[] memory screeningVoteParams_) {
        uint256 votingPower = _grantFund.getVotesScreening(distributionId_, actor_);
        uint256 totalVotesUsed = 0;

        // determine which proposals should be voted upon
        screeningVoteParams_ = new IGrantFundState.ScreeningVoteParams[](numProposalsToVoteOn_);
        if (happyPath_) {
            for (uint256 i = 0; i < numProposalsToVoteOn_; ++i) {
                // get a random proposal
                uint256 proposalId = randomProposal();

                // account for already used voting power
                uint256 additionalVotesUsed = 0;
                if (votingPower != 0) {
                    additionalVotesUsed = randomAmount(votingPower - totalVotesUsed);
                }
                totalVotesUsed += additionalVotesUsed;

                // generate screening vote params
                screeningVoteParams_[i] = IGrantFundState.ScreeningVoteParams({
                    proposalId: proposalId,
                    votes: additionalVotesUsed
                });
            }
        }
    }

    function _fundingVoteProposal(address actor_, uint256 numProposalsToVoteOn_) internal {
        uint24 distributionId = _grantFund.getDistributionId();

        // if voter has no voting power, no voting is possible
        if (_grantFund.getVotesFunding(distributionId, actor_) == 0) return;

        // get the fundingVoteParams for the votes the actor is about to cast
        // take the happy path, and cast votes that wont exceed the actor's voting power
        IGrantFundState.FundingVoteParams[] memory fundingVoteParams = _fundingVoteParams(actor_, distributionId, numProposalsToVoteOn_, true);

        // cast votes
        changePrank(actor_);
        _grantFund.fundingVote(fundingVoteParams);

        // record cast votes
        VotingActor storage actor = votingActors[actor_][distributionId];
        for (uint256 i = 0; i < fundingVoteParams.length; ) {
            actor.fundingVotes.push(fundingVoteParams[i]);
            fundingVotesCast++;

            ++i;
        }
    }

    function _screeningVoteProposal(address actor_) internal {
        uint24 distributionId = _grantFund.getDistributionId();
        uint256 votingPower = _grantFund.getVotesScreening(distributionId, actor_);

        // if voter has no voting power, no voting is possible
        if (votingPower == 0) return;

        // get random number of proposals to vote on
        uint256 numProposalsToVoteOn = constrictToRange(randomSeed(), 1, 10);

        IGrantFundState.ScreeningVoteParams[] memory screeningVoteParams = _screeningVoteParams(actor_, distributionId, numProposalsToVoteOn, true);

        // cast votes
        changePrank(actor_);
        _grantFund.screeningVote(screeningVoteParams);

        // record cast votes
        VotingActor storage actor = votingActors[actor_][distributionId];
        for (uint256 i = 0; i < numProposalsToVoteOn; ) {
            actor.screeningVotes.push(screeningVoteParams[i]);
            screeningVotesCast++;

            ++i;
        }
    }

    function _recordTestProposal(uint256 proposalId_, uint24 distributionId_, address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, string memory description_) internal {
        (
            GeneratedTestProposalParams[] memory params,
            uint256 totalTokensRequested
        ) = _getGeneratedTestProposalParamsFromParams(targets_, values_, calldatas_);
        TestProposal storage testProposal = testProposals[proposalId_];
        testProposal.proposalId = proposalId_;
        testProposal.description = description_;
        testProposal.distributionId = distributionId_;
        testProposal.totalTokensRequested = totalTokensRequested;
        for (uint i = 0; i < params.length; ++i) {
            testProposal.params.push(params[i]);
        }
    }

    // find a proposalId in an array of potential proposalIds that isn't already present in another array
    function _findUnusedProposalId(uint256[] memory usedProposals_, uint256[] memory potentialProposals_) internal returns (uint256) {
        uint256 proposalId = potentialProposals_[constrictToRange(randomSeed(), 0, potentialProposals_.length - 1)];

        // check if proposalId is already in the array
        for (uint256 i = 0; i < usedProposals_.length; ++i) {
            if (usedProposals_[i] != proposalId) {
                // if it hasn't been used, then return out
                return proposalId;
            }
        }

        // if random proposal was already used, then try again
        return _findUnusedProposalId(usedProposals_, potentialProposals_);
    }

    function _findUnexecutedProposalId(uint256 endingDistributionId_) internal view returns (uint256 proposalId_) {
        for (uint24 i = 1; i <= endingDistributionId_; ) {
            // get top slate proposals for each distribution period
            (, , , , , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(i);
            uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

            for (uint256 j = 0; j < topSlateProposalIds.length; j++) {
                // determine if a proposal is executable but hasn't already been executed
                IGrantFundState.ProposalState state = _grantFund.state(topSlateProposalIds[j]);
                if (state == IGrantFundState.ProposalState.Succeeded) {
                    proposalId_ = topSlateProposalIds[j];
                }
            }
            ++i;
        }
    }

    function _findUnclaimedReward(address actor_, uint24 endingDistributionId_) internal returns (uint24 distributionIdToClaim_) {
        for (uint24 i = 1; i <= endingDistributionId_; ) {
            uint256 delegationReward = _grantFund.getDelegateReward(i, actor_);
            numberOfCalls["delegationRewardSet"]++;
            if (delegationReward > 0) {
                numberOfCalls["delegationRewardSet"]++;
                distributionIdToClaim_ = i;
                break;
            }
            ++i;
        }
    }

    /**************************/
    /*** Logging Functions ****/
    /**************************/

    function logActorSummary(uint24 distributionId_, bool funding_, bool screening_) external view {
        console.log("\nActor Summary\n");

        console.log("------------------");
        console.log("Number of Actors", getActorsCount());

        // sum proposal votes of each actor
        for (uint256 i = 0; i < getActorsCount(); ++i) {
            address actor = actors[i];

            // get actor info
            (
                IGrantFundState.FundingVoteParams[] memory fundingVoteParams,
                IGrantFundState.ScreeningVoteParams[] memory screeningVoteParams,
                uint256 delegationRewardsClaimed
            ) = getVotingActorsInfo(actor, distributionId_);

            console.log("Actor:                    ", actor);
            console.log("Delegate:                 ", _ajna.delegates(actor));
            console.log("delegationRewardsClaimed: ", delegationRewardsClaimed);
            console.log("\n");

            // log funding info
            if (funding_) {
                console.log("--Funding----------");
                console.log("Funding proposals voted for:     ", fundingVoteParams.length);
                console.log("Sum of squares of fvc:           ", sumSquareOfVotesCast(fundingVoteParams));
                console.log("Funding Votes Cast:              ", uint256(sumFundingVotes(fundingVoteParams)));
                console.log("Negative Funding Votes Cast:     ", countNegativeFundingVotes(fundingVoteParams));
                console.log("------------------");
                console.log("\n");
            }

            if (screening_) {
                console.log("--Screening----------");
                console.log("Screening Voting Power:          ", _grantFund.getVotesScreening(distributionId_, actor));
                console.log("Screening Votes Cast:            ", sumVoterScreeningVotes(actor, distributionId_));
                console.log("Screening proposals voted for:   ", screeningVoteParams.length);
                console.log("------------------");
                console.log("\n");
            }
        }
    }

    function logCallSummary() external view {
        console.log("\nCall Summary\n");
        console.log("--SFM----------");
        console.log("SFH.startNewDistributionPeriod ",  numberOfCalls["SFH.startNewDistributionPeriod"]);
        console.log("SFH.propose                    ",  numberOfCalls["SFH.propose"]);
        console.log("SFH.screeningVote              ",  numberOfCalls["SFH.screeningVote"]);
        console.log("SFH.fundingVote                ",  numberOfCalls["SFH.fundingVote"]);
        console.log("SFH.updateSlate                ",  numberOfCalls["SFH.updateSlate"]);
        console.log("SFH.execute                    ",  numberOfCalls["SFH.execute"]);
        console.log("SFH.claimDelegateReward        ",  numberOfCalls["SFH.claimDelegateReward"]);
        console.log("roll                           ",  numberOfCalls["roll"]);
        console.log("------------------");
        console.log(
            "Total Calls:",
            numberOfCalls["SFH.startNewDistributionPeriod"] +
            numberOfCalls["SFH.propose"] +
            numberOfCalls["SFH.screeningVote"] +
            numberOfCalls["SFH.fundingVote"] +
            numberOfCalls["SFH.updateSlate"] +
            numberOfCalls["SFH.execute"] +
            numberOfCalls["SFH.claimDelegateReward"] +
            numberOfCalls["roll"]
        );
    }

    function logProposalSummary() external view {
        uint24 distributionId = _grantFund.getDistributionId();
        uint256[] memory proposals = standardFundingProposals[distributionId];

        console.log("\nProposal Summary\n");
        console.log("Number of Proposals", proposals.length);
        for (uint256 i = 0; i < proposals.length; ++i) {
            console.log("------------------");
            (uint256 proposalId, , uint128 votesReceived, uint128 tokensRequested, int128 fundingVotesReceived, bool executed) = _grantFund.getProposalInfo(proposals[i]);
            console.log("proposalId:              ",  proposalId);
            console.log("distributionId:          ",  distributionId);
            console.log("executed:                ",  executed);
            console.log("screening votesReceived: ",  votesReceived);
            console.log("tokensRequested:         ",  tokensRequested);
            if (fundingVotesReceived < 0) {
                console.log("Negative fundingVotesReceived: ",  uint256(Maths.abs(fundingVotesReceived)));
            }
            else {
                console.log("Positive fundingVotesReceived: ",  uint256(int256(fundingVotesReceived)));
            }

            console.log("------------------");
        }
        console.log("\n");
    }

    function logTimeSummary() external view {
        uint24 distributionId = _grantFund.getDistributionId();
        (, uint256 startBlock, uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        console.log("\nTime Summary\n");
        console.log("------------------");
        console.log("Distribution Id:        %s", distributionId);
        console.log("start block:            %s", startBlock);
        console.log("end block:              %s", endBlock);
        console.log("block number:           %s", block.number);
        console.log("current block:          %s", testContract.currentBlock());
        console.log("------------------");
    }

    /***********************/
    /*** View Functions ****/
    /***********************/

    function getDistributionFundsUpdated(uint24 distributionId_) external view returns (bool) {
        return distributionStates[distributionId_].treasuryUpdated;
    }

    function getDistributionState(uint24 distributionId_) external view returns (DistributionState memory) {
        return distributionStates[distributionId_];
    }

    function getDistributionStartBlock(uint24 distributionId_) external view returns (uint256 startBlock_) {
        (
            ,
            startBlock_,
            ,
            ,
            ,
        ) = _grantFund.getDistributionPeriodInfo(distributionId_);
    }

    function getStandardFundingProposals(uint24 distributionId_) external view returns (uint256[] memory) {
        return standardFundingProposals[distributionId_];
    }

    function getProposalsExecuted() external view returns (uint256[] memory) {
        return proposalsExecuted;
    }

    function getTestProposal(uint256 proposalId_) external view returns (TestProposal memory) {
        return testProposals[proposalId_];
    }

    function getVotingActorsInfo(address actor_, uint24 distributionId_) public view returns (IGrantFundState.FundingVoteParams[] memory, IGrantFundState.ScreeningVoteParams[] memory, uint256) {
        return (
            votingActors[actor_][distributionId_].fundingVotes,
            votingActors[actor_][distributionId_].screeningVotes,
            votingActors[actor_][distributionId_].delegationRewardsClaimed
        );
    }

    function getTokensRequestedInFundedSlateInvariant(bytes32 slateHash_) public view returns (uint256 tokensRequested_) {
        uint256[] memory fundedProposals = _grantFund.getFundedProposalSlate(slateHash_);
        for (uint256 i = 0; i < fundedProposals.length; ++i) {
            (, , , uint128 tokensRequested, , ) = _grantFund.getProposalInfo(fundedProposals[i]);
            tokensRequested_ += tokensRequested;
        }
    }

    function sumSquareOfVotesCast(
        IGrantFundState.FundingVoteParams[] memory votesCast_
    ) public pure returns (uint256 votesCastSumSquared_) {
        uint256 numVotesCast = votesCast_.length;

        for (uint256 i = 0; i < numVotesCast; ) {
            votesCastSumSquared_ += Maths.wpow(Maths.abs(votesCast_[i].votesUsed), 2);

            unchecked { ++i; }
        }
    }

    function sumVoterScreeningVotes(address actor_, uint24 distributionId_) public view returns (uint256 sum_) {
        VotingActor memory actor = votingActors[actor_][distributionId_];
        for (uint256 i = 0; i < actor.screeningVotes.length; ++i) {
            sum_ += actor.screeningVotes[i].votes;
        }
    }

    function sumFundingVotes(IGrantFundState.FundingVoteParams[] memory fundingVotes_) public pure returns (uint256 sum_) {
        for (uint256 i = 0; i < fundingVotes_.length; ++i) {
            sum_ += Maths.abs(fundingVotes_[i].votesUsed);
        }
    }

    function countNegativeFundingVotes(IGrantFundState.FundingVoteParams[] memory fundingVotes_) public pure returns (uint256 count_) {
        for (uint256 i = 0; i < fundingVotes_.length; ++i) {
            if (fundingVotes_[i].votesUsed < 0) {
                count_++;
            }
        }
    }

}
