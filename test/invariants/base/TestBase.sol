// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Test }   from "@std/Test.sol";

import { TestGrantFund } from "../../utils/harness/TestGrantFund.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { TestAjnaToken }       from "../../utils/harness/TestAjnaToken.sol";

contract TestBase is Test, GrantFundTestHelper {
    IAjnaToken        internal  _ajna;
    TestGrantFund     internal  _grantFund;

    // token deployment variables
    address internal _tokenDeployer = makeAddr("tokenDeployer");
    uint256 public   _startBlock    = 16354861;

    // initial treasury value
    uint256 treasury = 500_000_000 * 1e18;

    uint256 public currentBlock;

    function setUp() public virtual {
        // provide cheatcode access to the standard funding handler
        // vm.allowCheatcodes(0x4447E7a83995B5cCDCc9A6cd8Bc470305C940DA3);

        // deploy ajna token
        TestAjnaToken token = new TestAjnaToken();

        // Ajna Token contract address on mainnet
        _ajna = IAjnaToken(address(token));

        _ajna.mint(_tokenDeployer, 1_000_000_000 * 1e18);

        // deploy test grant fund contract
        _grantFund = new TestGrantFund(address(_ajna));

        vm.startPrank(_tokenDeployer);

        // initial minter distributes treasury to grantFund
        _ajna.approve(address(_grantFund), treasury);
        _grantFund.fundTreasury(treasury);

        // exclude unrelated contracts
        excludeContract(address(_ajna));

        currentBlock = block.number;
    }

    function setCurrentBlock(uint256 currentBlock_) external {
        currentBlock = currentBlock_;
    }

}
