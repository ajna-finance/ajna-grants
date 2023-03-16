// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Test }     from "forge-std/Test.sol";
import { IVotes }   from "@oz/governance/utils/IVotes.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { IAjnaToken }          from "../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../utils/GrantFundTestHelper.sol";

import { GrantFund } from "../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { console } from "@std/console.sol";

contract StandardFundingHandler is Test, GrantFundTestHelper {

    // state variables
    IAjnaToken        internal  _token;
    IVotes            internal  _votingToken;
    GrantFund         internal  _grantFund;

    // test params
    address internal _actor; // currently active actor, used in useRandomActor modifier
    address[] public actors;
    address _tokenDeployer;

    // record standard funding proposals over time
    // proposal count
    uint256 public standardFundingProposalCount;
    // list of submitted standard funding proposals
    uint256[] public standardFundingProposals;

    uint256 public screeningVotesCast;

    // randomness counter
    uint256 private counter = 1;

    // record the votes of actors over time
    mapping(address => VotingActor) votingActors;
    struct VotingActor {
        int256[] fundingVotes;
        uint256[] screeningVotes;
        uint256[] fundingProposalIds;
        uint256[] screeningProposalIds;
    }

    // ghost variables

    // Logging
    mapping(bytes32 => uint256) public numberOfCalls;

    constructor(address payable grantFund_, address token_, address tokenDeployer_, uint256 numOfActors_, uint256 tokensToDistribute_) {
        // Ajna Token contract address on mainnet
        _token = IAjnaToken(token_);

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _grantFund = GrantFund(grantFund_);

        // token deployer
        _tokenDeployer = tokenDeployer_;

        // instantiate actors
        actors = _buildActors(numOfActors_, tokensToDistribute_);
    }

    modifier useRandomActor(uint256 actorIndex) {

        vm.stopPrank();

        address actor = actors[constrictToRange(actorIndex, 0, actors.length - 1)];
        _actor = actor;
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    function _buildActors(uint256 numOfActors_, uint256 tokensToDistribute_) internal returns (address[] memory actors_) {
        actors_ = new address[](numOfActors_);
        uint256 tokensDistributed = 0;

        for (uint256 i = 0; i < numOfActors_; ++i) {
            // create actor
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actors_[i] = actor;

            // transfer ajna tokens to the actor
            if (tokensToDistribute_ - tokensDistributed == 0) {
                break;
            }
            uint256 incrementalTokensDistributed = randomAmount(tokensToDistribute_ - tokensDistributed);
            changePrank(_tokenDeployer);
            _token.transfer(actor, incrementalTokensDistributed);
            tokensDistributed += incrementalTokensDistributed;

            // actor delegates tokens randomly
            if (shouldSelfDelegate()) {
                // actor self delegates
                changePrank(actor);
                _token.delegate(actor);
            } else {
                // actor delegates to a random actor
                changePrank(actor);
                if (actors.length > 0) {
                    _token.delegate(randomActor());
                }
                else {
                    // if no other actors are available (such as on the first iteration) self delegate
                    _token.delegate(actor);
                }
            }
        }
    }

    function constrictToRange(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256 result) {
        require(max >= min, "MAX_LESS_THAN_MIN");

        uint256 size = max - min;

        if (size == 0) return min;            // Using max would be equivalent as well.
        if (max != type(uint256).max) size++; // Make the max inclusive.

        // Ensure max is inclusive in cases where x != 0 and max is at uint max.
        if (max == type(uint256).max && x != 0) x--; // Accounted for later.

        if (x < min) x += size * (((min - x) / size) + 1);

        result = min + ((x - min) % size);

        // Account for decrementing x to make max inclusive.
        if (max == type(uint256).max && x != 0) result++;
    }

    function randomAmount(uint256 maxAmount_) internal returns (uint256) {
        return constrictToRange(randomSeed(), 1, maxAmount_);
    }

    function randomActor() internal returns (address) {
        return actors[constrictToRange(randomSeed(), 0, actors.length - 1)];
    }

    function shouldSelfDelegate() internal returns (bool) {
        // calculate random number between 0 and 9
        uint256 number = uint256(keccak256(abi.encodePacked(block.number, block.difficulty))) % 10;
        vm.roll(block.number + 1);

        return number >= 5 ? true : false;
    }

    function randomSeed() internal returns (uint256) {
        counter++;
        return uint256(keccak256(abi.encodePacked(block.number, block.difficulty, counter, standardFundingProposalCount)));
    }

    function getActorsCount() external view returns(uint256) {
        return actors.length;
    }

    /*********************/
    /*** SFM Functions ***/
    /*********************/

    function startNewDistributionPeriod(uint256 actorIndex_) external useRandomActor(actorIndex_) returns (uint24 newDistributionId_) {
        numberOfCalls['SFH.startNewDistributionPeriod']++;

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
                err == keccak256(abi.encodeWithSignature("ScreeningPeriodEnded()"))
            );
        }

    }

    function screeningVoteMulti(uint256 actorIndex_, uint128 numberOfVotes_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.screeningVoteMulti']++;
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesWithParams(_actor, block.number, bytes("Screening"));

        // new proposals voted on
        uint256[] memory proposalsVotedOn = new uint256[](proposalsToVoteOn_);
        // new proposal votes
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

        try _grantFund.screeningVoteMulti(screeningVoteParams) {
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
    function fundingVotesMulti(uint256 actorIndex_, uint256 numberOfVotes_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.fundingVotesMulti']++;
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);

        // check where block is in the distribution period
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        if (block.number < endBlock - 72000) {

            // check if we should activate the funding stage
            // 1/10 chance of activating funding stage
            bool shouldActivateFundingStage = randomAmount(10) == 2 ? true : false;
            if (shouldActivateFundingStage) {
                // skip time into the funding stage
                uint256 fundingStageStartBlock = endBlock - 72000;
                vm.roll(fundingStageStartBlock + 100);
                numberOfCalls['SFH.FundingStage']++;
            }
            else {
                return;
            }
        }

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesWithParams(_actor, block.number - 50, bytes("Funding"));

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

        try _grantFund.fundingVotesMulti(fundingVoteParams) returns (uint256 votesCast) {
            numberOfCalls['SFH.fundingVotesMulti.success']++;
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

    function checkSlate(uint256 actorIndex_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.checkSlate']++;

        // check that the distribution period ended
        if (keccak256(getStage()) != keccak256(bytes("Challenge"))) {
            return;
        }

        numberOfCalls['SFH.checkSlate.success']++;

        // get top ten proposals
        // uint256[] memory topTen = _grantFund.getTopTenProposals();



    }

    function getVotes(address actor_) external view returns (uint256) {
        return _grantFund.getVotes(actor_, block.number);
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
        for (uint256 i = 0; i < numParams_; ++i) {
            testProposalParams_[i] = TestProposalParams({
                recipient: randomActor(),
                tokensRequested: randomAmount(_grantFund.maximumQuarterlyDistribution())
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
