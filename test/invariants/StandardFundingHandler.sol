// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IVotes } from "@oz/governance/utils/IVotes.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { IAjnaToken }          from "../utils/IAjnaToken.sol";
import { InvariantTest}        from "./InvariantTest.sol";
import { GrantFundTestHelper } from "../utils/GrantFundTestHelper.sol";

import { GrantFund } from "../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

contract StandardFundingHandler is InvariantTest, GrantFundTestHelper {

    // state variables
    IAjnaToken        internal  _token;
    IVotes            internal  _votingToken;
    GrantFund         internal  _grantFund;

    // test params
    address internal _actor; // currently active actor, used in useRandomActor modifier
    address[] public actors;
    uint256[] public standardFundingProposals;
    address _tokenDeployer;

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
            uint256 incrementalTokensDistributed = randomTokenAmount(tokensToDistribute_ - tokensDistributed);
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
    ) public pure returns (uint256 result) {
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

    function randomTokenAmount(uint256 maxAmount) public view returns (uint256) {
        return constrictToRange(uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))), 1, maxAmount);
    }

    function randomActor() public view returns (address) {
        return actors[constrictToRange(uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))), 0, actors.length - 1)];
    }

    function shouldSelfDelegate() internal returns (bool) {
        // calculate random number between 0 and 9
        uint256 number = uint256(keccak256(abi.encodePacked(block.number, block.difficulty))) % 10;
        vm.roll(block.number + 1);

        return number >= 5 ? true : false;
    }

    function shouldSubmitProposal() public returns (bool) {
        // calculate random number between 0 and 9
        uint256 number = uint256(keccak256(abi.encodePacked(block.number, block.difficulty))) % 10;
        vm.roll(block.number + 1);

        return number >= 5 ? true : false;
    }

    function getActorsCount() external view returns(uint256) {
        return actors.length;
    }

    /*********************/
    /*** SFM Functions ***/
    /*********************/

    function startNewDistributionPeriod() external returns (uint24 newDistributionId_) {
        numberOfCalls['SFH.startNewDistributionPeriod']++;

        try _grantFund.startNewDistributionPeriod() returns (uint24 newDistributionId) {
            newDistributionId_ = newDistributionId;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("DistributionPeriodStillActive()"))
            );
        }
    }

    function proposeStandard() external {
        numberOfCalls['SFH.proposeStandard']++;

        // get a random number between 1 and 5
        uint256 numProposalParams = constrictToRange(uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))), 1, 5);

        // generate list of recipients and tokens requested
        TestProposalParams[] memory testProposalParams = generateTestProposalParams(numProposalParams);

        // generate proposal params
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = generateProposalParams(testProposalParams);

        try _grantFund.proposeStandard(targets, values, calldatas, description) returns (uint256 proposalId) {
            standardFundingProposals.push(proposalId);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("ProposalAlreadyExists()")) ||
                err == keccak256(abi.encodeWithSignature("ScreeningPeriodEnded()"))
            );
        }

    }

    function screeningVoteMulti(uint256 actorIndex_, uint256 numberOfVotes_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.screeningVoteMulti']++;

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesWithParams(_actor, block.number, bytes("Screening"));

        // proposals voted on
        uint256[] memory proposalsVotedOn = new uint256[](numberOfVotes_);
        // proposal votes
        uint256[] memory votes = new uint256[](numberOfVotes_);

        // construct vote params
        IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams = new IStandardFunding.ScreeningVoteParams[](standardFundingProposals.length);
        for (uint256 i = 0; i < numberOfVotes_; i++) {
            uint256 proposalId = randomProposal();
            votes[i] = constrictToRange(uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))), 0, votingPower);
            screeningVoteParams[i] = IStandardFunding.ScreeningVoteParams({
                proposalId: proposalId,
                votes: votes[i]
            });
        }

        try _grantFund.screeningVoteMulti(screeningVoteParams) {
            // update actor vote count
            uint256 startIndex = votingActors[_actor].screeningVotes.length;
            startIndex == 0 ? 0 : startIndex - 1;
            uint256 j;
            for (uint256 i = startIndex; i < numberOfVotes_; ++i) {
                votingActors[_actor].screeningVotes[i] = votes[j];
                votingActors[_actor].screeningProposalIds[proposalsVotedOn[i]] = proposalsVotedOn[j];

                ++i;
                ++j;
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

    // FIXME: need to be able to randomly advance time
    function fundingVotesMulti(uint256 actorIndex_, uint256 numberOfVotes_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.fundingVotesMulti']++;

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesWithParams(_actor, block.number, bytes("Funding"));

        // construct vote params
        IStandardFunding.FundingVoteParams[] memory fundingVoteParams = new IStandardFunding.FundingVoteParams[](standardFundingProposals.length);
        for (uint256 i = 0; i < numberOfVotes_; i++) {
            // TODO: replace proposalId with retrieval from top ten list?
            uint256 proposalId = randomProposal();
            // TODO: figure out how to best generate negative votes to cast
            int256 votes = int256(constrictToRange(uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))), 0, votingPower));
            fundingVoteParams[i] = IStandardFunding.FundingVoteParams({
                proposalId: proposalId,
                votesUsed: votes
            });
        }

        try _grantFund.fundingVotesMulti(fundingVoteParams) {

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
        }
        description_ = string(abi.encodePacked(descriptionPartOne, descriptionPartTwo));
    }

    function generateTestProposalParams(uint256 numParams_) internal view returns (TestProposalParams[] memory testProposalParams_) {
        testProposalParams_ = new TestProposalParams[](numParams_);

        for (uint256 i = 0; i < numParams_; ++i) {
            testProposalParams_[i] = TestProposalParams({
                recipient: randomActor(),
                tokensRequested: randomTokenAmount(_grantFund.maximumQuarterlyDistribution())
            });
        }
    }

    function randomProposal() public view returns (uint256) {
        return standardFundingProposals[constrictToRange(uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))), 0, standardFundingProposals.length - 1)];
    }

    function getStandardFundingProposalsLength() external view returns (uint256) {
        return standardFundingProposals.length;
    }

    function getStandardFundingProposals() external view returns (uint256[] memory) {
        return standardFundingProposals;
    }

    function findProposalIndex(
        uint256 proposalId_,
        uint256[] memory array_
    ) public pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array
        int256 arrayLength = int256(array_.length);

        for (int256 i = 0; i < arrayLength;) {
            //slither-disable-next-line incorrect-equality
            if (array_[uint256(i)] == proposalId_) {
                index_ = i;
                break;
            }

            unchecked { ++i; }
        }
    }

    // record the votes of actors over time
    mapping(address => VotingActor) votingActors;

    struct VotingActor {
        int256[] fundingVotes;
        uint256[] screeningVotes;
        uint256[] fundingProposalIds;
        uint256[] screeningProposalIds;
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

    function numVotingActorScreeningVotes(address actor_) external view returns (uint256) {
        return votingActors[actor_].screeningVotes.length;
    }

    function sumVoterScreeningVotes(address actor_) public view returns (uint256 sum_) {
        for (uint256 i = 0; i < votingActors[actor_].screeningVotes.length; ++i) {
            sum_ += votingActors[actor_].screeningVotes[i];
        }
    }

}
