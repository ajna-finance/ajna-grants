// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Test }     from "forge-std/Test.sol";
import { IVotes }   from "@oz/governance/utils/IVotes.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { GrantFund }        from "../../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../../src/grants/interfaces/IStandardFunding.sol";
import { Maths }            from "../../../src/grants/libraries/Maths.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { Handler }      from "./Handler.sol";

import { console } from "@std/console.sol";

contract StandardHandler is Handler {

    // record standard funding proposals over time
    // proposal count
    uint256 public standardFundingProposalCount;
    // list of submitted standard funding proposals
    uint256[] public standardFundingProposals;

    uint256[] public proposalsExecuted;

    // number of proposals that recieved a vote in the given stage
    uint256 public screeningVotesCast;
    uint256 public fundingVotesCast;

    // time counter
    uint256 private systemTime = 0;

    struct VotingActor {
        IStandardFunding.FundingVoteParams[] fundingVotes;
        IStandardFunding.ScreeningVoteParams[] screeningVotes;
        uint256 delegationRewardsClaimed;
    }

    struct DistributionState {
        uint24 distributionId;
        bytes32 currentTopSlate;
    }

    mapping(uint24 => DistributionState) public distributionStates;
    mapping(bytes32 => uint256[]) public proposalsInTopSlate;
    mapping(address => mapping(uint24 => VotingActor)) internal votingActors; // actor => distributionId => VotingActor
    mapping(uint256 => TestProposal) public testProposals;

    constructor(
        address payable grantFund_,
        address token_,
        address tokenDeployer_,
        uint256 numOfActors_,
        uint256 tokensToDistribute_
    ) Handler(grantFund_, token_, tokenDeployer_, numOfActors_, tokensToDistribute_) {}

    /*********************/
    /*** SFM Functions ***/
    /*********************/

    function startNewDistributionPeriod(uint256 actorIndex_) external useRandomActor(actorIndex_) returns (uint24 newDistributionId_) {
        numberOfCalls['SFH.startNewDistributionPeriod']++;
        systemTime++;

        // vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);

        try _grantFund.startNewDistributionPeriod() returns (uint24 newDistributionId) {
            newDistributionId_ = newDistributionId;
            // FIXME: remove this
            vm.roll(block.number + 100);
            vm.rollFork(block.number + 100);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("DistributionPeriodStillActive()"))
            );
        }
    }

    function proposeStandard(uint256 actorIndex_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.proposeStandard']++;
        systemTime++;

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
        ) = generateProposalParams(testProposalParams);

        console.log("description", description);
        try _grantFund.proposeStandard(targets, values, calldatas, description) returns (uint256 proposalId) {
            standardFundingProposals.push(proposalId);
            standardFundingProposalCount++;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("ProposalAlreadyExists()")) ||
                err == keccak256(abi.encodeWithSignature("ScreeningPeriodEnded()")) ||
                err == keccak256(abi.encodeWithSignature("InvalidProposal()"))
            );
        }

    }

    function screeningVote(uint256 actorIndex_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.screeningVote']++;
        systemTime++;

        uint24 distributionId = _grantFund.getDistributionId();

        // bind proposalsToVoteOn_ to the number of proposals
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), _actor);

        // construct vote params
        IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams = new IStandardFunding.ScreeningVoteParams[](proposalsToVoteOn_);
        for (uint256 i = 0; i < proposalsToVoteOn_; i++) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // generate screening vote params
            screeningVoteParams[i] = IStandardFunding.ScreeningVoteParams({
                proposalId: proposalId,
                votes: constrictToRange(randomSeed(), 0, votingPower) // FIXME: account for previously used voting power
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
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()"))
            );
        }
    }

    function fundingVote(uint256 actorIndex_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.fundingVote']++;
        systemTime++;

        // bind proposalsToVoteOn_ to the number of proposals
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);

        // TODO: implement time counter incremeneted monotonically per call depth
        // check where block is in the distribution period
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        if (block.number < endBlock - 72000) {

        //     // check if we should activate the funding stage
        //     if (systemTime >= 1500) {
        //         // skip time into the funding stage
        //         uint256 fundingStageStartBlock = endBlock - 72000;
        //         vm.roll(fundingStageStartBlock + 100);
        //         numberOfCalls['SFH.FundingStage']++;
        //     }
        //     else {
                return;
        //     }
        }

        // TODO: make happy / chaotic path decision random / dynamic?
        // get the fundingVoteParams for the votes the actor is about to cast
        // take the chaotic path, and cast votes that will likely exceed the actor's voting power
        IStandardFunding.FundingVoteParams[] memory fundingVoteParams = _fundingVoteParams(_actor, proposalsToVoteOn_, false);

        try _grantFund.fundingVote(fundingVoteParams) returns (uint256 votesCast) {
            numberOfCalls['SFH.fundingVote.success']++;

            // assertGt(votesCast, 0);

            // TODO: account for possibly being negative
            // check votesCast is equal to the sum of votes cast
            assertEq(votesCast, SafeCast.toUint256(sumFundingVotes(fundingVoteParams)));

            // update actor funding votes counts
            // TODO: find and replace previous vote record for that proposlId, in that distributonId
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
            // TODO: replace with _recordError()
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()")) ||
                err == keccak256(abi.encodeWithSignature("FundingVoteWrongDirection()"))
            );
        }
    }

    // FIXME: can a proposal slate have no proposals?
    function updateSlate(uint256 actorIndex_, uint256 proposalSeed) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.updateSlate']++;
        systemTime++;

        // check that the distribution period ended
        if (keccak256(getStage()) != keccak256(bytes("Challenge"))) {
            return;
        }

        if (systemTime > 2800) {
            return;
        }

        uint256 potentialSlateLength = constrictToRange(proposalSeed, 0, 10);
        uint24 distributionId = _grantFund.getDistributionId();

        // get top ten proposals
        uint256[] memory topTen = _grantFund.getTopTenProposals(distributionId);
        // construct potential slate of proposals
        uint256[] memory potentialSlate = new uint256[](potentialSlateLength);

        bool happyPath = true;

        if (happyPath) {
            // get subset of top ten in order
            for (uint i = 0; i < potentialSlateLength; ++i) {
                potentialSlate[i] = topTen[i];
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

                // update distribution state
                DistributionState storage distribution = distributionStates[distributionId];
                distribution.distributionId = distributionId;
                distribution.currentTopSlate = keccak256(abi.encode(potentialSlate));

                // update list of proposals in top slate
                for (uint i = 0; i < potentialSlateLength; ++i) {
                    proposalsInTopSlate[distribution.currentTopSlate].push(potentialSlate[i]);
                }
            }
        }
        catch (bytes memory _err){
            // TODO: replace with _recordError()
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidProposalSlate()"))
            );
        }
    }

    function executeStandard(uint256 actorIndex_, uint256 proposalToExecute_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.executeStandard']++;
        systemTime++;

        uint24 distributionId = _grantFund.getDistributionId();

        (, , uint256 endBlock, , , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId);

        if (systemTime >= 500) {
            // skip time to the end of the challenge stage
            vm.roll(endBlock + 50401);
            // numberOfCalls['SFH.FundingStage']++;
        }

        if (block.number <= endBlock + 50400) return;

        // get a proposal from the current top ten slate
        uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

        if (topSlateProposalIds.length == 0) return;

        uint256 proposalIndex = constrictToRange(proposalToExecute_, 1, topSlateProposalIds.length) -1;

        console.log("proposal index", proposalIndex);
        TestProposal memory proposal = testProposals[topSlateProposalIds[proposalIndex]];

        try _grantFund.executeStandard(proposal.targets, proposal.values, proposal.calldatas, keccak256(bytes(proposal.description))) returns (uint256 proposalId_) {
            assertEq(proposalId_, proposal.proposalId);
            numberOfCalls['SFH.executeStandard.success']++;
            proposalsExecuted.push(proposalId_);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("ExecuteProposalInvalid()")) ||
                err == keccak256(abi.encodeWithSignature("ProposalNotSuccessful()"))
            );
        }
    }

    function claimDelegateReward(uint256 actorIndex_, uint256 proposalToExecute_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.claimDelegateReward']++;
        systemTime++;

        uint24 distributionId = _grantFund.getDistributionId();

        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);

        if (systemTime >= 900) {
            // skip time to the end of the challenge stage
            vm.roll(endBlock + 50401);
            // numberOfCalls['SFH.FundingStage']++;
        }

        try _grantFund.claimDelegateReward(distributionId) returns (uint256 rewardClaimed_) {
            numberOfCalls['SFH.claimDelegateReward.success']++;

            // should only be able to claim delegation rewards once
            assertEq(votingActors[_actor][distributionId].delegationRewardsClaimed, 0);

            votingActors[_actor][distributionId].delegationRewardsClaimed = rewardClaimed_;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("DelegateRewardInvalid()"))   ||
                err == keccak256(abi.encodeWithSignature("ChallengePeriodNotEnded()")) ||
                err == keccak256(abi.encodeWithSignature("RewardAlreadyClaimed()"))
            );
        }
    }


    /*****************************/
    /*** SFM Utility Functions ***/
    /*****************************/

    function generateProposalParams(TestProposalParams[] memory testProposalParams_) internal view
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
            targets_[i] = address(_token);
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

            // FIXME: random actor and amount in generateTestProposalParams are returning same value due to not being able to advance time
            descriptionPartTwo = string.concat(descriptionPartTwo, Strings.toString(standardFundingProposals.length));
        }
        description_ = string(abi.encodePacked(descriptionPartOne, descriptionPartTwo));
    }

    function generateTestProposalParams(uint256 numParams_) internal returns (TestProposalParams[] memory testProposalParams_) {
        testProposalParams_ = new TestProposalParams[](numParams_);

        // FIXME: these values aren't random
        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < numParams_; ++i) {
            // get distribution info
            uint24 distributionId = _grantFund.getDistributionId();
            (, , , uint128 fundsAvailable, , ) = _grantFund.getDistributionPeriodInfo(distributionId);

            // account for amount that was previously requested
            uint256 additionalTokensRequested = randomAmount((fundsAvailable * 9 /10) - totalTokensRequested);
            totalTokensRequested += additionalTokensRequested;

            testProposalParams_[i] = TestProposalParams({
                recipient: randomActor(),
                tokensRequested: additionalTokensRequested
            });
        }
    }

    function randomProposal() internal returns (uint256) {
        return standardFundingProposals[constrictToRange(randomSeed(), 0, standardFundingProposals.length - 1)];
    }

    function getStage() internal view returns (bytes memory stage_) {
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        if (block.number < endBlock - 72000) {
            stage_ = bytes("Screening");
        }
        else if (block.number > endBlock - 72000 && block.number < endBlock) {
            stage_ = bytes("Funding");
        }
        else if (block.number > endBlock) {
            stage_ = bytes("Challenge");
        }
    }

    function _createProposals(uint256 numProposals_) internal returns (uint256[] memory proposalIds_) {
        proposalIds_ = new uint256[](numProposals_);
        for (uint256 i = 0; i < numProposals_; ++i) {
            proposalIds_[i] = _createProposal();
        }
    }

    function _createProposal() internal returns (uint256 proposalId_) {
        // get a random number between 1 and 5
        uint256 numProposalParams = constrictToRange(randomSeed(), 1, 5);
        // uint256 numProposalParams = 3;

        // TODO: increase randomness of number of params
        // generate list of recipients and tokens requested
        TestProposalParams[] memory testProposalParams = generateTestProposalParams(numProposalParams);

        // generate proposal params
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = generateProposalParams(testProposalParams);

        // create proposal
        proposalId_ = _grantFund.proposeStandard(targets, values, calldatas, description);

        // record new proposal
        standardFundingProposals.push(proposalId_);
        standardFundingProposalCount++;

        // FIXME: set recipient and tokensRequested
        // record proposal information
        testProposals[proposalId_] = TestProposal(
            proposalId_,
            targets,
            values,
            calldatas,
            description,
            address(0),
            0
        );
    }

    function createProposals(uint256 numProposals) external returns (uint256[] memory proposalIds_) {
        proposalIds_ = _createProposals(numProposals);
    }

    function _findProposalIndexOfVotesCast(
        uint256 proposalId_,
        IStandardFunding.FundingVoteParams[] memory voteParams_
    ) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array

        // since we are converting from uint256 to int256, we can safely assume that the value will not overflow
        int256 numVotesCast = int256(voteParams_.length);
        for (int256 i = 0; i < numVotesCast; ) {
            //slither-disable-next-line incorrect-equality
            if (voteParams_[uint256(i)].proposalId == proposalId_) {
                index_ = i;
                break;
            }

            unchecked { ++i; }
        }
    }

    // TODO: need to add support for different types of param generation -> turn this into a factory
    function _fundingVoteParams(address actor_, uint256 numProposalsToVoteOn_, bool happyPath_) internal returns (IStandardFunding.FundingVoteParams[] memory fundingVoteParams_) {
        uint24 distributionId = _grantFund.getDistributionId();
        uint256 votingPower = _grantFund.getVotesFunding(distributionId, actor_);

        // Take the square root of the voting power to determine how many votes are actually available for casting
        uint256 availableVotes = _grantFund.getFundingPowerVotes(votingPower);

        fundingVoteParams_ = new IStandardFunding.FundingVoteParams[](numProposalsToVoteOn_);

        uint256 votingPowerUsed;

        // generate the array of fundingVoteParams structs
        for (uint256 i = 0; i < numProposalsToVoteOn_; ) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // get the random number of votes to cast
            int256 votesToCast = int256(constrictToRange(randomSeed(), 0, availableVotes));

            // if we should account for previous votes, then we need to make sure that the votes used are less than the available votes
            // flag is useful for generating vote params for a happy path required for test setup, as well as the chaotic path.
            if (happyPath_) {
                votesToCast = int256(constrictToRange(randomSeed(), 0, _grantFund.getFundingPowerVotes(votingPower - votingPowerUsed)));

                uint256[] memory topTenProposals = _grantFund.getTopTenProposals(distributionId);

                // if taking the happy path, set proposalId to a random proposal in the top ten
                if (_findProposalIndexOfVotesCast(proposalId, fundingVoteParams_) == -1) {
                    proposalId = topTenProposals[constrictToRange(randomSeed(), 0, topTenProposals.length - 1)];
                }

                bool votedPrior = false;

                // FIXME: check prior votes as well as pending votes.
                    // this may not be possible as we don't yet know what the pending votes will be...
                // check for any previous votes on this proposal
                IStandardFunding.FundingVoteParams[] memory priorVotes = votingActors[actor_][distributionId].fundingVotes;
                for (uint256 j = 0; j < priorVotes.length; ++j) {
                    // if we have already voted on this proposal, then we need to update the votes used
                    if (priorVotes[j].proposalId == proposalId) {
                        // votesToCast = int256(constrictToRange(randomSeed(), 0, _grantFund.getFundingPowerVotes(votingPower - votingPowerUsed)));
                        votingPowerUsed += Maths.wpow(uint256(Maths.abs(priorVotes[j].votesUsed + votesToCast)), 2);
                        votedPrior = true;
                        break;
                    }
                }

                if (!votedPrior) {
                    votingPowerUsed += Maths.wpow(uint256(Maths.abs(votesToCast)), 2);
                }

            }

            // TODO: happy path expects non negative? -> reverts with InvalidVote if used
                // Need to account for a proposal prior vote direction in test setup
            // flip a coin to see if should instead use a negative vote
            if (randomSeed() % 2 == 0) {
                numberOfCalls['SFH.negativeFundingVote']++;
                // generate negative vote
                fundingVoteParams_[i] = IStandardFunding.FundingVoteParams({
                    proposalId: proposalId,
                    votesUsed: -1 * votesToCast
                });
                ++i;
                continue;
            }

            // generate funding vote params
            fundingVoteParams_[i] = IStandardFunding.FundingVoteParams({
                proposalId: proposalId,
                votesUsed: votesToCast
            });

            ++i;
        }
    }

    function fundingVoteProposals() external {
        for (uint256 i = 0; i < actors.length; ++i) {
            // get an actor who hasn't already voted
            address actor = actors[i];

            // actor votes on random number of proposals
            _fundingVoteProposal(actor, constrictToRange(randomSeed(), 1, 10));
        }
    }

    function _fundingVoteProposal(address actor_, uint256 numProposalsToVoteOn_) internal {
        // get the fundingVoteParams for the votes the actor is about to cast
        // take the happy path, and cast votes that wont exceed the actor's voting power
        IStandardFunding.FundingVoteParams[] memory fundingVoteParams = _fundingVoteParams(actor_, numProposalsToVoteOn_, true);

        // cast votes
        changePrank(actor_);
        _grantFund.fundingVote(fundingVoteParams);

        uint24 distributionId = _grantFund.getDistributionId();

        // record cast votes
        VotingActor storage actor = votingActors[actor_][distributionId];
        for (uint256 i = 0; i < numProposalsToVoteOn_; ) {
            actor.fundingVotes.push(fundingVoteParams[i]);
            fundingVotesCast++;

            ++i;
        }
    }

    function screeningVoteProposals() external {
        for (uint256 i = 0; i < actors.length; ++i) {
            // get an actor who hasn't already voted
            address actor = actors[i];

            // actor votes on random number of proposals
            _screeningVoteProposal(actor);
        }
    }

    function _screeningVoteProposal(address actor_) internal {
        uint24 distributionId = _grantFund.getDistributionId();

        uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), actor_);

        // get random number of proposals to vote on
        uint256 numProposalsToVoteOn = constrictToRange(randomSeed(), 1, 10);

        uint256 totalVotesUsed = 0;

        // calculate which proposals should be voted upon
        IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams = new IStandardFunding.ScreeningVoteParams[](numProposalsToVoteOn);
        for (uint256 i = 0; i < numProposalsToVoteOn; ++i) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // account for already used voting power
            uint256 additionalVotesUsed = randomAmount(votingPower - totalVotesUsed);
            totalVotesUsed += additionalVotesUsed;

            // generate screening vote params
            screeningVoteParams[i] = IStandardFunding.ScreeningVoteParams({
                proposalId: proposalId,
                votes: additionalVotesUsed
            });
        }

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

    // TODO: add support for handling input strings and number of calls
    function _recordError(bytes memory err_) internal {
        bytes32 err = keccak256(err_);
        if (err == keccak256(abi.encodeWithSignature("InvalidVote()"))) {
            numberOfCalls['SFH.fv.e.InvalidVote']++;
        }
        else if (err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()"))) {
            numberOfCalls['SFH.fv.e.InsufficientVotingPower']++;
        }
        else if (err == keccak256(abi.encodeWithSignature("FundingVoteWrongDirection()"))) {
            numberOfCalls['SFH.fv.e.FVWD']++;
        }
        else {
            numberOfCalls['SFH.fv.e.unknown']++;
            revert("unknown error");
        }
    }

    function hasDuplicates(
        uint256[] calldata proposalIds_
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

    function sumSquareOfVotesCast(
        IStandardFunding.FundingVoteParams[] memory votesCast_
    ) public pure returns (uint256 votesCastSumSquared_) {
        uint256 numVotesCast = votesCast_.length;

        for (uint256 i = 0; i < numVotesCast; ) {
            votesCastSumSquared_ += Maths.wpow(SafeCast.toUint256(Maths.abs(votesCast_[i].votesUsed)), 2);

            unchecked { ++i; }
        }
    }

    function _votingActorsInfo(address actor_, uint24 distributionId_) internal view returns (IStandardFunding.FundingVoteParams[] memory, IStandardFunding.ScreeningVoteParams[] memory, uint256) {
        return (
            votingActors[actor_][distributionId_].fundingVotes,
            votingActors[actor_][distributionId_].screeningVotes,
            votingActors[actor_][distributionId_].delegationRewardsClaimed
        );
    }

    function logActorSummary(uint24 distributionId_, bool funding_, bool screening_) external view {
        console.log("\nActor Summary\n");

        console.log("------------------");
        console.log("Number of Actors", getActorsCount());

        // sum proposal votes of each actor
        for (uint256 i = 0; i < getActorsCount(); ++i) {
            address actor = actors[i];

            // get actor info
            (
                IStandardFunding.FundingVoteParams[] memory fundingVoteParams,
                IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams,
                uint256 delegationRewardsClaimed
            ) = getVotingActorsInfo(actor, distributionId_);

            console.log("Actor:                    ", actor);
            console.log("Delegate:                 ", _token.delegates(actor));
            console.log("delegationRewardsClaimed: ", delegationRewardsClaimed);
            console.log("\n");

            // log funding info
            if (funding_) {
                console.log("--Funding----------");
                console.log("Funding proposals voted for:     ", fundingVoteParams.length);
                console.log("Sum of squares of fvc:           ", sumSquareOfVotesCast(fundingVoteParams));
                console.log("Funding Votes Cast:              ", uint256(sumFundingVotes(fundingVoteParams)));
                console.log("Negative Funding Votes Cast:     ", countNegativeFundingVotes(actor, fundingVoteParams));
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
        console.log("SFH.proposeStandard            ",  numberOfCalls["SFH.proposeStandard"]);
        console.log("SFH.screeningVote              ",  numberOfCalls["SFH.screeningVote"]);
        console.log("SFH.fundingVote                ",  numberOfCalls["SFH.fundingVote"]);
        console.log("SFH.updateSlate                ",  numberOfCalls["SFH.updateSlate"]);
        console.log("SFH.executeStandard            ",  numberOfCalls["SFH.executeStandard"]);
        console.log("------------------");
        console.log(
            "Total Calls:",
            numberOfCalls["SFH.startNewDistributionPeriod"] +
            numberOfCalls["SFH.proposeStandard"] +
            numberOfCalls["SFH.screeningVote"] +
            numberOfCalls["SFH.fundingVote"] +
            numberOfCalls["SFH.updateSlate"] +
            numberOfCalls["SFH.executeStandard"]
        );
    }

    function logProposalSummary() external view {
        console.log("\nProposal Summary\n");
        console.log("Number of Proposals", standardFundingProposalCount);
        for (uint256 i = 0; i < standardFundingProposalCount; ++i) {
            console.log("------------------");
            (uint256 proposalId, uint24 distributionId, uint128 votesReceived, uint128 tokensRequested, int128 fundingVotesReceived, bool executed) = _grantFund.getProposalInfo(standardFundingProposals[i]);
            console.log("proposalId:           ",  proposalId);
            console.log("distributionId:       ",  distributionId);
            console.log("executed:             ",  executed);
            console.log("votesReceived:        ",  votesReceived);
            console.log("tokensRequested:      ",  tokensRequested);
            // console.log("fundingVotesReceived: ",  fundingVotesReceived);
            console.log("------------------");
        }
        console.log("\n");
    }

    /*****************************/
    /*** SFM Getter Functions ****/
    /*****************************/

    function getStandardFundingProposals() external view returns (uint256[] memory) {
        return standardFundingProposals;
    }

    function getProposalsExecuted() external view returns (uint256[] memory) {
        return proposalsExecuted;
    }

    function getVotingActorsInfo(address actor_, uint24 distributionId_) public view returns (IStandardFunding.FundingVoteParams[] memory, IStandardFunding.ScreeningVoteParams[] memory, uint256) {
        return _votingActorsInfo(actor_, distributionId_);
    }

    function sumVoterScreeningVotes(address actor_, uint24 distributionId_) public view returns (uint256 sum_) {
        VotingActor memory actor = votingActors[actor_][distributionId_];
        for (uint256 i = 0; i < actor.screeningVotes.length; ++i) {
            sum_ += actor.screeningVotes[i].votes;
        }
    }

    function sumFundingVotes(IStandardFunding.FundingVoteParams[] memory fundingVotes_) public pure returns (int256 sum_) {
        for (uint256 i = 0; i < fundingVotes_.length; ++i) {
            sum_ += Maths.abs(fundingVotes_[i].votesUsed);
        }
    }

    function countNegativeFundingVotes(address actor_, IStandardFunding.FundingVoteParams[] memory fundingVotes_) public pure returns (uint256 count_) {
        for (uint256 i = 0; i < fundingVotes_.length; ++i) {
            if (fundingVotes_[i].votesUsed < 0) {
                count_++;
            }
        }
    }

}
