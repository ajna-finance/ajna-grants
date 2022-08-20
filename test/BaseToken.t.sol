// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken } from "../src/BaseToken.sol";

import { SigUtils } from "./utils/SigUtils.sol";

contract AjnaTokenTest is Test {

    AjnaToken internal _token;
    SigUtils  internal _sigUtils;

    address internal _tokenDeployer   = makeAddr("tokenDeployer");
    address internal _testTokenHolder = makeAddr("_testTokenHolder");
    uint256 _initialAjnaTokenSupply   = 1_000_000_000 * 1e18;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() external {
        vm.startPrank(_tokenDeployer);
        _token = new AjnaToken();

        _sigUtils = new SigUtils(_token.DOMAIN_SEPARATOR());
    }

    function testCannotSendTokensToContract() external {
        vm.expectRevert("Cannot transfer tokens to the contract itself");
        _token.transfer(address(_token), 1);
    }

    function testTransferTokensToZeroAddress() external {
        vm.expectRevert("ERC20: transfer to the zero address");
        _token.transfer(address(0), 1);
    }

    function testBaseInvariantMetadata() external {
        assertEq(_token.name(),     "AjnaToken");
        assertEq(_token.symbol(),   "AJNA");
        assertEq(_token.decimals(), 18);
    }

    function testTokenTotalSupply() external {
        assertEq(_token.totalSupply(), _initialAjnaTokenSupply);
    }

    function testMinterTokenBalance() external {
        assertEq(_token.balanceOf(_tokenDeployer), _initialAjnaTokenSupply);
    }

    function testBurn() external {
        assertEq(_token.totalSupply(), _initialAjnaTokenSupply);
        _token.burn(50_000_000 * 1e18);
        assertEq(_token.totalSupply(), 950_000_000 * 1e18);
    }

    function testTransferWithApprove(uint256 amount_) external {
        vm.assume(amount_ > 0);
        vm.assume(amount_ <= _initialAjnaTokenSupply);
        _token.approve(_tokenDeployer, amount_);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_tokenDeployer, address(5555), amount_);
        _token.transferFrom(_tokenDeployer, address(5555), amount_);

        assertEq(_token.balanceOf(_tokenDeployer), _initialAjnaTokenSupply - amount_);
        assertEq(_token.balanceOf(address(5555)),  amount_);
    }

    function testTransferWithPermit(uint256 amount_) external {
        vm.assume(amount_ > 0);
        vm.assume(amount_ <= _initialAjnaTokenSupply);

        // define owner and spender addresses
        (address owner, uint256 ownerPrivateKey) = makeAddrAndKey("owner");
        address spender                          = makeAddr("spender");
        address newOwner                         = makeAddr("newOwner");

        // set owner balance
        deal(address(_token), owner, amount_);

        // check owner and spender balances
        assertEq(_token.balanceOf(owner),    amount_);
        assertEq(_token.balanceOf(spender),  0);
        assertEq(_token.balanceOf(newOwner), 0);

        // TEST transfer with ERC20 permit
        changePrank(owner);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount_,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = _sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        _token.permit(owner, spender, amount_, permit.deadline, v, r, s);

        changePrank(spender);
        _token.transferFrom(owner, newOwner, amount_);

        // check owner and spender balances after transfer
        assertEq(_token.balanceOf(owner),    0);
        assertEq(_token.balanceOf(spender),  0);
        assertEq(_token.balanceOf(newOwner), amount_);
        assertEq(_token.allowance(owner, spender), 0);

        // TEST transfer from with permit
        // set owner balance
        deal(address(_token), owner, amount_);

        permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount_,
            nonce: 1,
            deadline: 1 days
        });

        digest = _sigUtils.getTypedDataHash(permit);
        (v, r, s) = vm.sign(ownerPrivateKey, digest);

        _token.transferFromWithPermit(owner, newOwner, spender, amount_, permit.deadline, v, r, s);
        // check owner and spender balances after 2nd transfer with permit
        assertEq(_token.balanceOf(owner),    0);
        assertEq(_token.balanceOf(spender),  0);
        assertEq(_token.balanceOf(newOwner), amount_ * 2);
        assertEq(_token.allowance(owner, spender), 0);
    }
}
