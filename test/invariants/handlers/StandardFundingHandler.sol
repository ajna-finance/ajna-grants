// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Test }     from "forge-std/Test.sol";
import { IVotes }   from "@oz/governance/utils/IVotes.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { GrantFund } from "../../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../../src/grants/interfaces/IStandardFunding.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { FundingHandler }      from "./FundingHandler.sol";

import { console } from "@std/console.sol";

contract StandardFundingHandler is FundingHandler {

    // record standard funding proposals over time
    // proposal count
    uint256 public standardFundingProposalCount;
    // list of submitted standard funding proposals
    uint256[] public standardFundingProposals;

    uint256 public screeningVotesCast;

    // time counter
    uint256 private systemTime = 0;

    // record the votes of actors over time
    mapping(address => VotingActor) votingActors;
    struct VotingActor {
        int256[] fundingVotes;
        uint256[] screeningVotes;
        uint256[] fundingProposalIds;
        uint256[] screeningProposalIds;
    }

    constructor(
        address payable grantFund_,
        address token_,
        address tokenDeployer_,
        uint256 numOfActors_,
        uint256 tokensToDistribute_
    ) FundingHandler(grantFund_, token_, tokenDeployer_, numOfActors_, tokensToDistribute_) {}

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

    function screeningVote(uint256 actorIndex_, uint128 numberOfVotes_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.screeningVote']++;

        systemTime++;

        // bind proposalsToVoteOn_ to the number of proposals
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);

        // get actor voting power
        // uint256 votingPower = _grantFund.getVotesWithParams(_actor, block.number, bytes("Screening"));
        uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), _actor);

        // track new proposals voted on
        uint256[] memory proposalsVotedOn = new uint256[](proposalsToVoteOn_);
        // track new proposal votes cast
        uint256[] memory votes = new uint256[](proposalsToVoteOn_);

        // construct vote params
        IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams = new IStandardFunding.ScreeningVoteParams[](proposalsToVoteOn_);
        for (uint256 i = 0; i < proposalsToVoteOn_; i++) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // track actor state change
            votes[i] = constrictToRange(randomSeed(), 0, votingPower);
            proposalsVotedOn[i] = proposalId;

            // generate screening vote params
            screeningVoteParams[i] = IStandardFunding.ScreeningVoteParams({
                proposalId: proposalId,
                votes: votes[i]
            });
        }

        try _grantFund.screeningVote(screeningVoteParams) {
            // update actor screeningVotes count if vote was successful
            VotingActor storage actor = votingActors[_actor];

            for (uint256 i = 0; i < proposalsToVoteOn_; ) {
                actor.screeningVotes.push(votes[i]);
                actor.screeningProposalIds.push(proposalsVotedOn[i]);
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


    // TODO: implement time counter incremeneted monotonically per call depth
    // FIXME: need to be able to randomly advance time
    function fundingVote(uint256 actorIndex_, uint256 numberOfVotes_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.fundingVote']++;
        systemTime++;

        // bind proposalsToVoteOn_ to the number of proposals
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);

        // check where block is in the distribution period
        // uint24 distributionId = _grantFund.getDistributionId();
        // (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        // if (block.number < endBlock - 72000) {

        //     // check if we should activate the funding stage
        //     if (systemTime >= 1500) {
        //         // skip time into the funding stage
        //         uint256 fundingStageStartBlock = endBlock - 72000;
        //         vm.roll(fundingStageStartBlock + 100);
        //         numberOfCalls['SFH.FundingStage']++;
        //     }
        //     else {
        //         return;
        //     }
        // }

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesFunding(_grantFund.getDistributionId(), _actor);

        // new proposals voted on
        uint256[] memory proposalsVotedOn = new uint256[](proposalsToVoteOn_);
        // new proposal votes
        int256[] memory votes = new int256[](proposalsToVoteOn_);

        // construct vote params
        IStandardFunding.FundingVoteParams[] memory fundingVoteParams = new IStandardFunding.FundingVoteParams[](proposalsToVoteOn_);
        for (uint256 i = 0; i < proposalsToVoteOn_; i++) {
            // TODO: replace proposalId with retrieval from top ten list?
            uint256 proposalId = randomProposal();
            // TODO: figure out how to best generate negative votes to cast

            votes[i] = int256(constrictToRange(randomSeed(), 0, votingPower));
            proposalsVotedOn[i] = proposalId;
            fundingVoteParams[i] = IStandardFunding.FundingVoteParams({
                proposalId: proposalId,
                votesUsed: votes[i]
            });
            // revert(Strings.toString(uint256(votes[i])));
        }

        try _grantFund.fundingVote(fundingVoteParams) returns (uint256 votesCast) {
            numberOfCalls['SFH.fundingVote.success']++;
            // update actor funding votes counts
            VotingActor storage actor = votingActors[_actor];
            for (uint256 i = 0; i < proposalsToVoteOn_; ) {
                actor.fundingVotes.push(votes[i]);
                actor.fundingProposalIds.push(proposalsVotedOn[i]);

                ++i;
            }
            // assertEq(votesCast, proposalsToVoteOn_);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()")) ||
                err == keccak256(abi.encodeWithSignature("FundingVoteWrongDirection()"))
            );
        }

    }

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

        numberOfCalls['SFH.updateSlate.success']++;

        uint256 proposalsToCheck = constrictToRange(proposalSeed, 0, standardFundingProposals.length);

        // get top ten proposals
        // uint256[] memory topTen = _grantFund.getTopTenProposals();

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
    }

    function createProposals(uint256 numProposals) external returns (uint256[] memory proposalIds_) {
        proposalIds_ = _createProposals(numProposals);
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
        uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), actor_);

        // get random number of proposals to vote on
        uint256 numProposalsToVoteOn = constrictToRange(randomSeed(), 1, 10);

        // track new proposals voted on
        uint256[] memory proposalsVotedOn = new uint256[](numProposalsToVoteOn);
        // track new proposal votes cast
        uint256[] memory votes = new uint256[](numProposalsToVoteOn);

        uint256 totalVotesUsed = 0;

        // calculate which proposals should be voted upon
        IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams = new IStandardFunding.ScreeningVoteParams[](numProposalsToVoteOn);
        for (uint256 i = 0; i < numProposalsToVoteOn; ++i) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // account for already used voting power
            uint256 additionalVotesUsed = randomAmount(votingPower - totalVotesUsed);
            totalVotesUsed += additionalVotesUsed;

            // track actor state change
            votes[i] = additionalVotesUsed;
            proposalsVotedOn[i] = proposalId;

            // generate screening vote params
            screeningVoteParams[i] = IStandardFunding.ScreeningVoteParams({
                proposalId: proposalId,
                votes: votes[i]
            });
        }

        // cast votes
        changePrank(actor_);
        _grantFund.screeningVote(screeningVoteParams);

        // record cast votes
        VotingActor storage actor = votingActors[actor_];
        for (uint256 i = 0; i < numProposalsToVoteOn; ) {
            actor.screeningVotes.push(votes[i]);
            actor.screeningProposalIds.push(proposalsVotedOn[i]);
            screeningVotesCast++;

            ++i;
        }
    }

    /*****************************/
    /*** SFM Getter Functions ****/
    /*****************************/

    function getStandardFundingProposals() external view returns (uint256[] memory) {
        return standardFundingProposals;
    }

    // TODO: will need to handle this per distribution period
    function getVotingActorsInfo(address actor_, uint256 index_) external view returns (int256, uint256, uint256, uint256) {
        return (
            votingActors[actor_].fundingVotes[index_],
            votingActors[actor_].screeningVotes[index_],
            votingActors[actor_].fundingProposalIds[index_],
            votingActors[actor_].screeningProposalIds[index_]
        );
    }

    function votingActorScreeningVotes(address actor_) external view returns (uint256[] memory) {
        return votingActors[actor_].screeningVotes;
    }

    function votingActorFundingVotes(address actor_) external view returns (int256[] memory) {
        return votingActors[actor_].fundingVotes;
    }

    function votingActorScreeningProposalIds(address actor_) external view returns (uint256[] memory) {
        return votingActors[actor_].screeningProposalIds;
    }

    function votingActorFundingProposalIds(address actor_) external view returns (uint256[] memory) {
        return votingActors[actor_].fundingProposalIds;
    }

    function numVotingActorScreeningVotes(address actor_) external view returns (uint256) {
        return votingActors[actor_].screeningVotes.length;
    }

    function sumVoterScreeningVotes(address actor_) public view returns (uint256 sum_) {
        for (uint256 i = 0; i < votingActors[actor_].screeningVotes.length; ++i) {
            sum_ += votingActors[actor_].screeningVotes[i];
        }
    }

    function sumVoterFundingVotes(address actor_) public view returns (int256 sum_) {
        for (uint256 i = 0; i < votingActors[actor_].fundingVotes.length; ++i) {
            sum_ += votingActors[actor_].fundingVotes[i];
        }
    }

}
