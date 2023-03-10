// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IVotes } from "@oz/governance/utils/IVotes.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { IAjnaToken }          from "../utils/IAjnaToken.sol";
import { InvariantTest}        from "./InvariantTest.sol";
import { GrantFundTestHelper } from "../utils/GrantFundTestHelper.sol";

import { GrantFund } from "../../src/grants/GrantFund.sol";

contract StandardFundingHandler is InvariantTest, GrantFundTestHelper {

    // state variables
    IAjnaToken        internal  _token;
    IVotes            internal  _votingToken;
    GrantFund         internal  _grantFund;

    // test params
    address internal _actor; // currently active actor, used in useRandomActor modifier
    address[] public actors;
    address _tokenDeployer;

    uint256[] public standardFundingProposals;

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

    function submitProposal(
        address actor_
    ) external returns (TestProposal memory newProposal_) {

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

        // create and submit proposal
        newProposal_ = _createProposalStandard(
            _grantFund,
            actor_,
            targets,
            values,
            calldatas,
            description
        );

        // add proposal to list of proposals
        standardFundingProposals.push(newProposal_.proposalId);
    }

    function getStandardFundingProposalsCount() external view returns(uint256) {
        return standardFundingProposals.length;
    }

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

}
