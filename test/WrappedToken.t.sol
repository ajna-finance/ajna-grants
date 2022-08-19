// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken }        from "../src/BaseToken.sol";
import { WrappedAjnaToken } from "../src/WrapperToken.sol";

contract WrappedTokenTest is Test {

    AjnaToken internal _token;
    WrappedAjnaToken internal _wrappedToken;

    address internal _testTokenHolder = makeAddr("_testTokenHolder");
    uint256 _initialAjnaTokenSupply   = 1_000_000_000 * 1e18;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() external {
        _token = new AjnaToken();
        _wrappedToken = new WrappedAjnaToken(_token);
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
        assertEq(_token.totalSupply(),        1_000_000_000 * 10 ** _token.decimals());
        assertEq(_wrappedToken.totalSupply(), 0);

        // transfer some tokens to the test address
        _token.approve(address(this), tokensToWrap);
        _token.transferFrom(address(this), _testTokenHolder, tokensToWrap);

        // wrap some tokens
        approveAndWrapTokens(_testTokenHolder, tokensToWrap);

        // check post wrap token supply
        assertEq(_token.totalSupply(),        1_000_000_000 * 10 ** _token.decimals());
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

    // TODO: implement
    function testPermitWrapped() external {}

    // TODO: implement
    function testDelegateVotes() external {}

}
