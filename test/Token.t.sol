// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken } from "../src/Token.sol";

contract TokenTest is Test {

    AjnaToken internal _token;

    function setUp() external {
        _token = new AjnaToken();
    }

    function testFailCannotSendTokensToContract() external {
        assert(false == _token.transfer(address(_token), 1));
    }

    function invariantMetadata() external {
        assertEq(_token.name(),     "AjnaToken");
        assertEq(_token.symbol(),   "AJNA");
        assertEq(_token.decimals(), 18);

        // TODO: check initial token supply
    }

    // TODO: implement this
    function testTokenSupply() external {
        assertTrue(true);
    }


    // TODO: implement this -> check can't mint additional tokens
    function testCantMint() external {

    }

    // TODO: implement this
    function testBurn() external {
        assertTrue(true);
    }

    // TODO: implement this
    function testPermit() external {
        assertTrue(true);
    }

    // TODO: implement this
    function testDelegateVotes() external {

    }

    // TODO: implement this
    function testNestedDelegation() external {
        assertTrue(true);
    }

    function testUpgrade() external {
        assertTrue(true);
    }

}
