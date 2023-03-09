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
    address[] public actors;
    address _tokenDeployer;

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
        // _actor = actor;
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    function _buildActors(uint256 numOfActors_, uint256 tokensToDistribute_) internal returns (address[] memory actors_) {
        actors_ = new address[](numOfActors_);
        for (uint256 i = 0; i < numOfActors_; ++i) {
            // create actor
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actors_[i] = actor;

            // transfer ajna tokens to the actor
            changePrank(_tokenDeployer);
            _token.transfer(actor, randomTokenAmount(tokensToDistribute_));

            if (shouldSelfDelegate()) {
                // actor self delegates
                changePrank(actor);
                _token.delegate(actor);
            } else {
                // actor delegates to a random actor
                changePrank(actor);
                _token.delegate(randomActor());
            }
        }
    }

    function constrictToRange(
        uint256 x,
        uint256 min,
        uint256 max
    ) pure public returns (uint256 result) {
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
        // calculate random proposal Index between 0 and noOfProposals_
        uint256 number = uint256(keccak256(abi.encodePacked(block.number, block.difficulty))) % 10;
        vm.roll(block.number + 1);

        return number >= 5 ? true : false;
    }

    function getActorsCount() external view returns(uint256) {
        return actors.length;
    }

}
