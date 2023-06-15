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

    /*****************/
    /*** Modifiers ***/
    /*****************/

    // FIXME: this isn't working properly when used at the top level of a test
    modifier useCurrentBlock() {
        vm.roll(currentBlock);

        _;

        setCurrentBlock(block.number);
    }

    /***************************/
    /**** Utility Functions ****/
    /***************************/

    function setCurrentBlock(uint256 currentBlock_) public {
        currentBlock = currentBlock_;
    }

    function getDiff(uint256 x, uint256 y) internal pure returns (uint256 diff) {
        diff = x > y ? x - y : y - x;
    }

    function requireWithinDiff(uint256 x, uint256 y, uint256 expectedDiff, string memory err) internal pure {
        require(getDiff(x, y) <= expectedDiff, err);
    }

}
