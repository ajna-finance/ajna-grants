// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken, UUPSProxy } from "../src/Token.sol";

import { TestAjnaTokenV2 } from "./utils/TestAjnaTokens.sol";

contract TokenTest is Test {

    // EIP1967 standard storage slot storing implementation address
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

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

        // TODO: check no upgrade or ownable actions are possible
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
        // verify initial state
        assertEq(_tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** _tokenProxyV1.decimals());
        // TODO: check initial implementation slot as part of testing implementation address access vs proxy
        // assertEq(_tokenProxyV1.proxiableUUID())
        // emit log_address(stdStorage.read_address(_tokenProxyV1.proxiableUUID()));
        // emit log_address(address(uint160(uint256(_tokenProxyV1.proxiableUUID()))));

        // transfer some tokens to another address
        address newTokenHolder = address(1111);
        uint256 tokensTransferred = 1000;
        _tokenProxyV1.approve(address(this), tokensTransferred);
        _tokenProxyV1.transferFrom(address(this), newTokenHolder, tokensTransferred);

        TestAjnaTokenV2 tokenV2 = new TestAjnaTokenV2();
        vm.expectEmit(true, true, false, true);
        emit Upgraded(address(tokenV2));
        _tokenProxyV1.upgradeTo(address(tokenV2));

        // re-wrap the proxy
        TestAjnaTokenV2 tokenProxyV2 = TestAjnaTokenV2(address(proxy));

        // check different implementation addresses
        assertTrue(address(_token) != address(tokenV2));
        // check proxy address is unchanged
        assertEq(address(_tokenProxyV1), address(tokenProxyV2));
        assertEq(address(_tokenProxyV1), address(proxy));
        assertEq(address(tokenProxyV2),  address(proxy));

        // check new method can be accessed and correctly reads state
        assertEq(tokenProxyV2.testVar(), 0);
        tokenProxyV2.setTestVar(100);
        assertEq(tokenProxyV2.testVar(), 100);

        // check previous state unchanged
        assertEq(tokenProxyV2.totalSupply(),             1_000_000_000 * 10 ** tokenProxyV2.decimals());
        assertEq(tokenProxyV2.balanceOf(address(this)),  1_000_000_000 * 10 ** tokenProxyV2.decimals() - tokensTransferred);
        assertEq(tokenProxyV2.balanceOf(newTokenHolder), tokensTransferred);
    }

    // TODO: record storage variables layout and check upgrade can take place without messing up storage layout
    // relevant docs: https://book.getfoundry.sh/reference/forge-std/std-storage?highlight=storage#std-storage
    function testUpgradeStorageLayout() external {

        // // TODO: check before and after storage layout
        // stdStorage.target(address(tokenProxyV1))
        //     .sig() // function signature
        //     .with_key() // function arg
        //     .read_uint(); // check type 
    }

    function testRemoveUpgradeability() external {

    }

}
