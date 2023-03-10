// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TestBase } from "./TestBase.sol";
import { StandardFundingHandler } from "./StandardFundingHandler.sol";

contract StandardFundingInvariant is TestBase {

    uint256 internal constant NUM_ACTORS = 50;

    StandardFundingHandler internal _standardFundingHandler;

    function setUp() public override virtual{
        super.setUp();

        // calculate the number of tokens not in the treasury, to be distributed to actors
        uint256 tokensNotInTreasury = _token.balanceOf(_tokenDeployer) - treasury;

        _standardFundingHandler = new StandardFundingHandler(
            payable(address(_grantFund)),
            address(_token),
            _tokenDeployer,
            NUM_ACTORS,
            tokensNotInTreasury
        );

        // start the first distribution period
        _grantFund.startNewDistributionPeriod();
        emit log_string("here");
    }

    function invariant_SS1() public {
        emit log_string("here 2");

        uint256 actorCount = _standardFundingHandler.getActorsCount();

        // actors submit proposals
        for (uint256 i = 0; i < actorCount; ++i) {
            if (_standardFundingHandler.shouldSubmitProposal()) {
                _standardFundingHandler.submitProposal(_standardFundingHandler.actors(i));
            }
        }

        // invariant: grant fund should have the same balance as the treasury
        assertEq(_token.balanceOf(address(_grantFund)), treasury);
    }

}
