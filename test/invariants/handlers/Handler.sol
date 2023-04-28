// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";
import { Test }    from "forge-std/Test.sol";
import { Strings } from "@oz/utils/Strings.sol";
import { Math }    from "@oz/utils/math/Math.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";

import { TestGrantFund } from "../../utils/harness/TestGrantFund.sol";
import { IStandardFunding } from "../../../src/grants/interfaces/IStandardFunding.sol";

import { ITestBase } from "../base/ITestBase.sol";

contract Handler is Test, GrantFundTestHelper {

    /***********************/
    /*** State Variables ***/
    /***********************/

    // global grant fund variables
    IAjnaToken        public  _ajna;
    TestGrantFund     public  _grantFund;

    // Test invariant contract
    ITestBase internal testContract;

    // test variables
    address internal _actor; // currently active actor, used in useRandomActor modifier
    address[] public actors;
    address _tokenDeployer;

    // logging
    mapping(bytes32 => uint256) public numberOfCalls;

    // randomness counter used in randomSeed()
    uint256 internal counter = 1;

    // constant error string when an unexpected revert is thrown
    string internal constant UNEXPECTED_REVERT = "UNEXPECTED_REVERT_ERROR";

    // used in roll() to determine if we are in a fast or slow scenario
    ScenarioType internal _currentScenarioType = ScenarioType.Slow;

    enum ScenarioType {
        Fast,
        Medium,
        Slow
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(
        address payable grantFund_,
        address token_,
        address tokenDeployer_,
        uint256 numOfActors_,
        uint256 tokensToDistribute_,
        address testContract_
    ) {
        // set global contract variables
        _ajna = IAjnaToken(token_);
        _grantFund = TestGrantFund(grantFund_);

        // set token deployer global variable
        _tokenDeployer = tokenDeployer_;

        // instantiate actors
        actors = _buildActors(numOfActors_, tokensToDistribute_);

        // set Test invariant contract
        testContract = ITestBase(testContract_);
    }

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier useCurrentBlock() {
        vm.roll(testContract.currentBlock());

        _;

        testContract.setCurrentBlock(block.number);
    }

    modifier useRandomActor(uint256 actorIndex) {
        vm.stopPrank();

        address actor = actors[constrictToRange(actorIndex, 0, actors.length - 1)];
        _actor = actor;
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    /*************************/
    /*** Wrapped Functions ***/
    /*************************/

    // roll forward to a random block height
    // roll limit is configurable based on the scenario type
    function roll(uint256 rollAmount_) external useCurrentBlock {
        numberOfCalls['roll']++;

        uint256 rollLimit = 300;

        if (_currentScenarioType == ScenarioType.Fast) {
            console.log("High roller");
            rollLimit = 10_000;
        }
        else if (_currentScenarioType == ScenarioType.Medium) {
            console.log("Medium roller");
            rollLimit = 800;
        }
        else if (_currentScenarioType == ScenarioType.Slow) {
            console.log("Low roller");
            rollLimit = 300;
        }

        // determine a random number of blocks to roll, less than 100
        rollAmount_ = constrictToRange(rollAmount_, 0, rollLimit);

        uint256 blockHeight = testContract.currentBlock() + rollAmount_;

        // roll forward to the selected block
        vm.roll(blockHeight);
    }

    /**************************/
    /*** Utility Functions ****/
    /**************************/

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
            _ajna.transfer(actor, incrementalTokensDistributed);
            tokensDistributed += incrementalTokensDistributed;

            // actor delegates tokens randomly
            changePrank(actor);
            if (randomSeed() % 2 == 0) {
                // actor self delegates
                _ajna.delegate(actor);
            } else {
                // actor delegates to a random actor
                if (i > 0) {
                    address randomDelegate = actors_[constrictToRange(randomSeed(), 0, i)];
                    _ajna.delegate(randomDelegate);
                }
                else {
                    // if no other actors are available (such as on the first iteration) self delegate
                    _ajna.delegate(actor);
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

    function randomSeed() internal returns (uint256) {
        counter++;
        return uint256(keccak256(abi.encodePacked(block.number, block.difficulty, counter)));
    }

    function setCurrentScenarioType(ScenarioType scenarioType) public {
        _currentScenarioType = scenarioType;
    }

    /***********************/
    /*** View Functions ****/
    /***********************/

    function getActorsCount() public view returns(uint256) {
        return actors.length;
    }

    function getCurrentScenarioType() public view returns(ScenarioType) {
        return _currentScenarioType;
    }
}
