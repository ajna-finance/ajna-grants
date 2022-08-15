// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import { AjnaToken } from "../src/Token.sol";

import "forge-std/Test.sol";

contract AjnaTokenTest is Test {

    AjnaToken internal _token;
    address   internal _deployer;

    function setUp() external {
        _deployer = address(1111);

        vm.prank(_deployer);
        _token    = new AjnaToken();
    }

    function invariantMetadata() external {
        assertEq(_token.name(),     "AjnaToken");
        assertEq(_token.symbol(),   "AJNA");
        assertEq(_token.decimals(), 18);
    }

    function testMultipleInitialize() external {
        vm.expectRevert("Initializable: contract is already initialized");
        _token.initialize();
    }

    function testDeployerBalance() external {
        assertEq(_token.balanceOf(_deployer), 1_000_000_000 * 1e18);
    }

    function testTransferTokensToZeroAddress() external {
        vm.expectRevert("ERC20: transfer to the zero address");
        _token.transfer(address(0), 1);
    }

    function testTransferTokensToTokenAddress() external {
        vm.expectRevert("Cannot transfer tokens to the contract itself");
        _token.transfer(address(_token), 1);
    }

    function testTransferTokensFromDeployer() external {
        address receiver = address(2222);
        assertEq(_token.balanceOf(_deployer), 1_000_000_000 * 1e18);
        assertEq(_token.balanceOf(receiver),  0);

        vm.prank(receiver);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        _token.transfer(_deployer, 50_000_000 * 1e18);

        vm.prank(_deployer);
        _token.transfer(receiver, 50_000_000 * 1e18);

        assertEq(_token.balanceOf(_deployer), 950_000_000 * 1e18);
        assertEq(_token.balanceOf(receiver),   50_000_000 * 1e18);
    }

}

