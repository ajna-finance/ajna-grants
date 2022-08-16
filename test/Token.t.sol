// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken, UUPSProxy } from "../src/Token.sol";

import { TestAjnaTokenV2 } from "./utils/TestAjnaTokenV2.sol";

contract TokenTest is Test {

    using stdStorage for StdStorage;

    AjnaToken internal _token;
    AjnaToken internal tokenProxyV1;
    UUPSProxy proxy;

    function setUp() external {
        _token = new AjnaToken();

        proxy = new UUPSProxy(address(_token), "");

        // wrap in ABI to support easier calls
        tokenProxyV1 = AjnaToken(address(proxy));

        tokenProxyV1.initialize();
    }

    function testFailCannotSendTokensToContract() external {
        assert(false == tokenProxyV1.transfer(address(tokenProxyV1), 1));
    }

    function invariantMetadata() external {
        assertEq(tokenProxyV1.name(),     "AjnaToken");
        assertEq(tokenProxyV1.symbol(),   "AJNA");
        assertEq(tokenProxyV1.decimals(), 18);
    }

    function testTokenTotalSupply() external {
        assertEq(tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** tokenProxyV1.decimals());
    }

    function testMultipleInitialization() external {
        // should revert if token already initialized
        vm.expectRevert("Initializable: contract is already initialized");
        tokenProxyV1.initialize();
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
    function testVote() external {

    }

    // TODO: implement this
    function testCalculateVotingPower() external {

    }

    // TODO: implement this
    function testNestedDelegation() external {
        assertTrue(true);
    }

    function testCanUpgrade() external {
        TestAjnaTokenV2 tokenV2 = new TestAjnaTokenV2();
        tokenProxyV1.upgradeTo(address(tokenV2));

        // re-wrap the proxy
        TestAjnaTokenV2 tokenProxyV2 = TestAjnaTokenV2(address(proxy));

        // check different implementation addresses
        assertTrue(address(_token) != address(tokenV2));

        // check new method can be accessed and correctly reads state
        assertEq(tokenProxyV2.testVar(), 0);
        tokenProxyV2.setTestVar(100);
        assertEq(tokenProxyV2.testVar(), 100);

        // TODO: check previous state no longer accessible...
        // assertEq(tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** tokenProxyV1.decimals());
    }

    // TODO: record storage variables layout and check upgrade can take place without messing up storage layout
    // relevant docs: https://book.getfoundry.sh/reference/forge-std/std-storage?highlight=storage#std-storage
    function testUpgradeStorageLayout() external {

    }

}
