// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Test }     from "forge-std/Test.sol";
import { IVotes }   from "@oz/governance/utils/IVotes.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";

import { GrantFund } from "../../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../../src/grants/interfaces/IStandardFunding.sol";

contract Handler is Test, GrantFundTestHelper {

    // state variables
    IAjnaToken        internal  _token;
    IVotes            internal  _votingToken;
    GrantFund         internal  _grantFund;

    // test params
    address internal _actor; // currently active actor, used in useRandomActor modifier
    address[] public actors;
    address _tokenDeployer;

    // logging
    mapping(bytes32 => uint256) public numberOfCalls;

    // randomness counter
    uint256 internal counter = 1;

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

            // FIXME: this isn't currently delegating to other actors properly
            // actor delegates tokens randomly
            if (randomSeed() % 2 == 0) {
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

    function randomSeed() internal returns (uint256) {
        counter++;
        return uint256(keccak256(abi.encodePacked(block.number, block.difficulty, counter)));
    }

    function getActorsCount() external view returns(uint256) {
        return actors.length;
    }

}
