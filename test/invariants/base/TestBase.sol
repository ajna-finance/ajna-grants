// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { Test }   from "@std/Test.sol";

import { GrantFund } from "../../../src/grants/GrantFund.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { TestAjnaToken }       from "../../utils/harness/TestAjnaToken.sol";

contract TestBase is Test, GrantFundTestHelper {
    // global variables
    IAjnaToken        internal  _ajna;
    GrantFund         internal  _grantFund;

    // token deployment variables
    address internal _tokenDeployer = makeAddr("tokenDeployer");
    uint256 public   _startBlock    = 16354861; // at this block on mainnet, all ajna tokens belongs to _tokenDeployer

    // initial treasury value
    uint256 treasury = 500_000_000 * 1e18;

    uint256 public currentBlock;

    function setUp() public virtual {
        // deploy grant fund, and fund treasury
        address[] memory iniitalVotersArr = new address[](0);
        uint256 initialVoterBalance = 0;
        (_grantFund, _ajna) = _deployAndFundGrantFund(_tokenDeployer, treasury, iniitalVotersArr, initialVoterBalance);

        // exclude unrelated contracts
        excludeContract(address(_ajna));

        currentBlock = block.number;
    }

    function setCurrentBlock(uint256 currentBlock_) external {
        currentBlock = currentBlock_;
    }

}
