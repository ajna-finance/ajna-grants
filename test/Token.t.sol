// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken } from "../src/Token.sol";

contract TokenTest is Test {

    using stdStorage for StdStorage;

    AjnaToken internal _token;

    function setUp() external {
        _token = new AjnaToken();

        // TODO: initialize the token
        // _token.initialize();

    }

    function testFailCannotSendTokensToContract() external {
        assert(false == _token.transfer(address(_token), 1));
    }

    function invariantMetadata() external {
        assertEq(_token.name(),     "AjnaToken");
        assertEq(_token.symbol(),   "AJNA");
        assertEq(_token.decimals(), 18);
    }

    function testTokenTotalSupply() external {
        assertEq(_token.totalSupply(), 1_000_000_000 * 10 ** _token.decimals());
    }

    function testTokenInitialization() external {
        // should revert if token already initialized
        vm.expectRevert("Initializable: contract is already initialized");
        _token.initialize();
    }

    function testMinterTokenBalance() external {

    }

    // TODO: implement this -> check can't mint additional tokens
    function testCantMint() external {

    }

    // TODO: implement this
    function testBurn() external {
        assertTrue(true);
    }

    // TODO: implement this -> possibly fuzzy within supply bounds
    function testTransfer() external {

    }

    // TODO: implement this
    function testTransferWithPermit() external {
        assertTrue(true);
    }

    // TODO: implement this
    function testDelegateVotes() external {

    }

    // TODO: implement this
    function testNestedDelegation() external {
        assertTrue(true);
    }

    // TODO: implement this
    function testUpgrade() external {
        assertTrue(true);
    }

    // TODO: record storage variables layout and check upgrade can take place without messing up storage layout
    // relevant docs: https://book.getfoundry.sh/reference/forge-std/std-storage?highlight=storage#std-storage
    function testUpgradeStorageLayout() external {

    }

}
