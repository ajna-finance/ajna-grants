// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken, UUPSProxy } from "../src/Token.sol";

import { TestAjnaTokenV2 } from "./utils/TestAjnaTokenV2.sol";

contract TokenTest is Test {

    using stdStorage for StdStorage;

    AjnaToken internal _token;
    AjnaToken internal _tokenProxyV1;
    UUPSProxy proxy;

    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() external {
        _token = new AjnaToken();

        proxy = new UUPSProxy(address(_token), "");

        // wrap in ABI to support easier calls
        _tokenProxyV1 = AjnaToken(address(proxy));

        _tokenProxyV1.initialize();
    }

    function testCannotSendTokensToContract() external {
        vm.expectRevert("Cannot transfer tokens to the contract itself");
        _tokenProxyV1.transfer(address(_tokenProxyV1), 1);
    }

    function testTransferTokensToZeroAddress() external {
        vm.expectRevert("ERC20: transfer to the zero address");
        _tokenProxyV1.transfer(address(0), 1);
    }

    function invariantMetadata() external {
        assertEq(_tokenProxyV1.name(),     "AjnaToken");
        assertEq(_tokenProxyV1.symbol(),   "AJNA");
        assertEq(_tokenProxyV1.decimals(), 18);
    }

    function testChangeOwner() external {
        address newOwner = address(2222);

        assertEq(_tokenProxyV1.owner(), address(this));

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(this), newOwner);
        _tokenProxyV1.transferOwnership(newOwner);

        assertEq(_tokenProxyV1.owner(), newOwner);
    }

    function testRenounceOwnership() external {
        assertEq(_tokenProxyV1.owner(), address(this));

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(this), address(0));
        _tokenProxyV1.renounceOwnership();

        assertEq(_tokenProxyV1.owner(), address(0));

        TestAjnaTokenV2 tokenV2 = new TestAjnaTokenV2();
        // check upgrade is not possible
        vm.expectRevert("Ownable: caller is not the owner");
        _tokenProxyV1.upgradeTo(address(tokenV2));

        // check no ownable actions are possible
        vm.expectRevert("Ownable: caller is not the owner");
        _tokenProxyV1.transferOwnership(address(2222));
    }

    function testTokenTotalSupply() external {
        assertEq(_tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** _tokenProxyV1.decimals());
    }

    function testMultipleInitialization() external {
        // should revert if token already initialized
        vm.expectRevert("Initializable: contract is already initialized");
        _tokenProxyV1.initialize();
    }

    function testMinterTokenBalance() external {
        assertEq(_tokenProxyV1.balanceOf(address(this)), 1_000_000_000 * 10 **18);
    }

    // TODO: implement this -> check can't mint additional tokens
    function testCantMint() external {

    }

    function testBurn() external {
        assertEq(_tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** _tokenProxyV1.decimals());
        _tokenProxyV1.burn(50_000_000 * 1e18);
        assertEq(_tokenProxyV1.totalSupply(), 950_000_000 * 10 ** _tokenProxyV1.decimals());
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
        assertEq(_tokenProxyV1.getVotes(address(this)), 0);
        assertEq(_tokenProxyV1.getVotes(address(3333)), 0);

        _tokenProxyV1.delegate(address(3333));
        assertEq(_tokenProxyV1.balanceOf(address(this)), 1_000_000_000 * 10 **18);
        assertEq(_tokenProxyV1.balanceOf(address(3333)), 0);

        assertEq(_tokenProxyV1.getVotes(address(this)), 0);
        assertEq(_tokenProxyV1.getVotes(address(3333)), 1_000_000_000 * 10 **18);
        assertEq(_tokenProxyV1.delegates(address(this)), address(3333));
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
        assertEq(_tokenProxyV1.totalSupply(),            1_000_000_000 * 10 **18);
        assertEq(_tokenProxyV1.balanceOf(address(this)), 1_000_000_000 * 10 **18);

        TestAjnaTokenV2 tokenV2 = new TestAjnaTokenV2();
        vm.expectEmit(true, true, false, true);
        emit Upgraded(address(tokenV2));
        _tokenProxyV1.upgradeTo(address(tokenV2));

        assertEq(_tokenProxyV1.totalSupply(),            0);
        assertEq(_tokenProxyV1.balanceOf(address(this)), 0);

        // TODO: determine if need to call initialize on the new proxy variable again?

        // re-wrap the proxy
        TestAjnaTokenV2 tokenProxyV2 = TestAjnaTokenV2(address(proxy));

        // check different implementation addresses
        assertTrue(address(_token) != address(tokenV2));

        // check new method can be accessed and correctly reads state
        assertEq(tokenProxyV2.testVar(), 0);
        tokenProxyV2.setTestVar(100);
        assertEq(tokenProxyV2.testVar(), 100);

        // FIXME: shouldn't these be 1bil as it used to be in v1?
        assertEq(tokenProxyV2.totalSupply(),            0);
        assertEq(tokenProxyV2.balanceOf(address(this)), 0);
    }

    // TODO: record storage variables layout and check upgrade can take place without messing up storage layout
    // relevant docs: https://book.getfoundry.sh/reference/forge-std/std-storage?highlight=storage#std-storage
    function testUpgradeStorageLayout() external {

    }

}
