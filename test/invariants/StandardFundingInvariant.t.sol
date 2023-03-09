// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TestBase } from "./TestBase.sol";
import { StandardFundingHandler } from "./StandardFundingHandler.sol";

contract StandardFundingInvariant is TestBase {

    uint256 internal constant NUM_ACTORS = 100;

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
    }

    function invariant_S1() public {
        // invariant: grant fund should have the same balance as the treasury
        assertEq(_token.balanceOf(address(_grantFund)), treasury);
    }

}
