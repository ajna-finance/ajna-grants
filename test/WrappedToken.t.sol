// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken }        from "../src/BaseToken.sol";
import { WrappedAjnaToken } from "../src/WrapperToken.sol";

import { SigUtils } from "./utils/SigUtils.sol";

contract WrappedTokenTest is Test {

    AjnaToken        internal _token;
    WrappedAjnaToken internal _wrappedToken;
    SigUtils         internal _sigUtils;

    address internal _testTokenHolder = makeAddr("_testTokenHolder");
    uint256 _initialAjnaTokenSupply   = 1_000_000_000 * 1e18;

    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    function setUp() external {
        _token = new AjnaToken();
        _wrappedToken = new WrappedAjnaToken(_token);

        _sigUtils = new SigUtils(_wrappedToken.DOMAIN_SEPARATOR());
    }

    function approveAndWrapTokens(address account_, uint256 amount_) internal {
        vm.prank(account_);
        _token.approve(address(_wrappedToken), amount_);

        vm.prank(account_);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(account_), address(_wrappedToken), amount_);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(account_), amount_);
        (bool wrapSuccess) = _wrappedToken.depositFor(account_, amount_);

        assertTrue(wrapSuccess);
    }

    function testBaseInvariantMetadata() external {
        assertEq(_token.name(),     "AjnaToken");
        assertEq(_token.symbol(),   "AJNA");
        assertEq(_token.decimals(), 18);
    }

    function testWrappedInvariantMetadata() external {
        assertEq(_wrappedToken.name(),     "Wrapped AJNA");
        assertEq(_wrappedToken.symbol(),   "wAJNA");
        assertEq(_wrappedToken.decimals(), 18);
    }

    function testWrap() external {
        uint256 tokensToWrap = 50 * 1e18;

        // check initial token balances
        assertEq(_token.balanceOf(_testTokenHolder), 0);
        assertEq(_wrappedToken.balanceOf(_testTokenHolder), 0);
        assertEq(_token.balanceOf(address(this)), _initialAjnaTokenSupply);
        assertEq(_wrappedToken.balanceOf(address(this)), 0);

        // transfer some tokens to the test address
        _token.approve(address(this), tokensToWrap);
        _token.transferFrom(address(this), _testTokenHolder, tokensToWrap);

        // check token balances after transfer
        assertEq(_token.balanceOf(_testTokenHolder), tokensToWrap);
        assertEq(_wrappedToken.balanceOf(_testTokenHolder), 0);
        assertEq(_token.balanceOf(address(this)), _initialAjnaTokenSupply - tokensToWrap);
        assertEq(_wrappedToken.balanceOf(address(this)), 0);

        // wrap tokens
        approveAndWrapTokens(_testTokenHolder, tokensToWrap);

        // check token balances after wrapping
        assertEq(_token.balanceOf(_testTokenHolder), 0);
        assertEq(_wrappedToken.balanceOf(_testTokenHolder), tokensToWrap);
        assertEq(_token.balanceOf(address(this)), _initialAjnaTokenSupply - tokensToWrap);
        assertEq(_wrappedToken.balanceOf(address(this)), 0);
    }

    // TODO: remove and add these checks to testWrap?
    function testWrapTotalSupply() external {
        uint256 tokensToWrap = 50 * 1e18;

        // check initial token supply
        assertEq(_token.totalSupply(),        _initialAjnaTokenSupply);
        assertEq(_wrappedToken.totalSupply(), 0);

        // transfer some tokens to the test address
        _token.approve(address(this), tokensToWrap);
        _token.transferFrom(address(this), _testTokenHolder, tokensToWrap);

        // wrap some tokens
        approveAndWrapTokens(_testTokenHolder, tokensToWrap);

        // check post wrap token supply
        assertEq(_token.totalSupply(),        _initialAjnaTokenSupply);
        assertEq(_wrappedToken.totalSupply(), tokensToWrap);
    }

    function testUnWrap() external {
        uint256 tokensToWrap = 110 * 1e18;

        // check initial token balances
        assertEq(_token.balanceOf(_testTokenHolder), 0);
        assertEq(_wrappedToken.balanceOf(_testTokenHolder), 0);
        assertEq(_token.balanceOf(address(this)), _initialAjnaTokenSupply);
        assertEq(_wrappedToken.balanceOf(address(this)), 0);

        // transfer some tokens to the test address
        _token.approve(address(this), tokensToWrap);
        _token.transferFrom(address(this), _testTokenHolder, tokensToWrap);

        // wrap all of holder's tokens
        approveAndWrapTokens(_testTokenHolder, tokensToWrap);

        // check token balances after wrapping
        assertEq(_token.balanceOf(_testTokenHolder), 0);
        assertEq(_wrappedToken.balanceOf(_testTokenHolder), tokensToWrap);
        assertEq(_token.balanceOf(address(this)), _initialAjnaTokenSupply - tokensToWrap);
        assertEq(_wrappedToken.balanceOf(address(this)), 0);

        // FIXME: cleanup token approvals
        // unwrap holder's tokens
        vm.prank(_testTokenHolder);
        _wrappedToken.approve(address(_wrappedToken), tokensToWrap);
        vm.prank(_testTokenHolder);
        _token.approve(address(_wrappedToken), tokensToWrap);

        vm.prank(_testTokenHolder);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_testTokenHolder), address(0), tokensToWrap);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_wrappedToken), address(_testTokenHolder), tokensToWrap);
        (bool unWrapSuccess) = _wrappedToken.withdrawTo(_testTokenHolder, tokensToWrap);
        assertTrue(unWrapSuccess);

        // check token balances after unwrapping
        assertEq(_token.balanceOf(_testTokenHolder), tokensToWrap);
        assertEq(_wrappedToken.balanceOf(_testTokenHolder), 0);
        assertEq(_token.balanceOf(address(this)), _initialAjnaTokenSupply - tokensToWrap);
        assertEq(_wrappedToken.balanceOf(address(this)), 0);
    }

    function testPermitWrapped(uint256 amount_) external {
        vm.assume(amount_ > 0);
        vm.assume(amount_ <= _initialAjnaTokenSupply);

        // define owner and spender addresses
        (address owner, uint256 ownerPrivateKey) = makeAddrAndKey("owner");
        address spender                          = makeAddr("spender");
        address newOwner                         = makeAddr("newOwner");

        // set owner balance
        deal(address(_wrappedToken), owner, amount_);

        // check owner and spender balances
        assertEq(_wrappedToken.balanceOf(owner),    amount_);
        assertEq(_wrappedToken.balanceOf(spender),  0);
        assertEq(_wrappedToken.balanceOf(newOwner), 0);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount_,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = _sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // test transfer with ERC20 permit
        _wrappedToken.permit(owner, spender, amount_, permit.deadline, v, r, s);
        vm.prank(spender);
        _wrappedToken.transferFrom(owner, newOwner, amount_);

        // check owner and spender balances after transfer
        assertEq(_wrappedToken.balanceOf(owner),    0);
        assertEq(_wrappedToken.balanceOf(spender),  0);
        assertEq(_wrappedToken.balanceOf(newOwner), amount_);

        assertEq(_wrappedToken.allowance(owner, spender), 0);

        // set owner balance
        deal(address(_wrappedToken), owner, amount_);

        permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount_,
            nonce: 1,
            deadline: 1 days
        });

        digest = _sigUtils.getTypedDataHash(permit);
        (v, r, s) = vm.sign(ownerPrivateKey, digest);

        vm.prank(spender);
        _wrappedToken.transferFromWithPermit(owner, newOwner, spender, amount_, permit.deadline, v, r, s);
        // check owner and spender balances after 2nd transfer with permit
        assertEq(_wrappedToken.balanceOf(owner),    0);
        assertEq(_wrappedToken.balanceOf(spender),  0);
        assertEq(_wrappedToken.balanceOf(newOwner), amount_ * 2);

        assertEq(_wrappedToken.allowance(owner, spender), 0);
    }

    function testDelegateVotes() external {
        address delegator = address(2222);
        address delegate1 = address(3333);
        address delegate2 = address(4444);

        // set delegator balance to 1_000 AJNA tokens
        deal(address(_wrappedToken), delegator, 1_000 * 1e18);

        // check voting power
        assertEq(_wrappedToken.getVotes(delegator), 0);
        assertEq(_wrappedToken.getVotes(delegate1), 0);
        assertEq(_wrappedToken.getVotes(delegate2), 0);

        vm.roll(11111);
        vm.prank(delegator);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator, address(0), delegate1);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegate1, 0, 1_000 * 1e18);
        _wrappedToken.delegate(delegate1);

        // check accounts balances
        assertEq(_wrappedToken.balanceOf(delegator), 1_000 * 1e18);
        assertEq(_wrappedToken.balanceOf(delegate1), 0);
        assertEq(_wrappedToken.balanceOf(delegate2), 0);
        // check voting power
        assertEq(_wrappedToken.getVotes(delegator), 0);
        assertEq(_wrappedToken.getVotes(delegate1), 1_000 * 1e18);
        assertEq(_wrappedToken.getVotes(delegate2), 0);

        assertEq(_wrappedToken.delegates(delegator), delegate1);

        vm.roll(11112);

        vm.prank(delegator);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator, delegate1, delegate2);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegate1, 1_000 * 1e18, 0);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegate2, 0, 1_000 * 1e18);
        _wrappedToken.delegate(delegate2);
        vm.roll(11113);

        // check accounts balances
        assertEq(_wrappedToken.balanceOf(delegator), 1_000 * 1e18);
        assertEq(_wrappedToken.balanceOf(delegate1), 0);
        assertEq(_wrappedToken.balanceOf(delegate2), 0);
        // check voting power
        assertEq(_wrappedToken.getVotes(delegator), 0);
        assertEq(_wrappedToken.getVotes(delegate1), 0);
        assertEq(_wrappedToken.getVotes(delegate2), 1_000 * 1e18);

        assertEq(_wrappedToken.delegates(delegator), delegate2);
        // check voting power at block 11111 and 11112
        assertEq(_wrappedToken.getPastVotes(delegate1, 11111), 1_000 * 1e18);
        assertEq(_wrappedToken.getPastVotes(delegate2, 11111), 0);
        assertEq(_wrappedToken.getPastVotes(delegate1, 11112), 0);
        assertEq(_wrappedToken.getPastVotes(delegate2, 11112), 1_000 * 1e18);
    }

}
