// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";

import { TestBase } from "./TestBase.sol";
import { StandardFundingHandler } from "../handlers/StandardFundingHandler.sol";

contract StandardFundingTestBase is TestBase {

    uint256 internal constant NUM_ACTORS = 20;

    StandardFundingHandler internal _standardFundingHandler;

    function setUp() public override {
        super.setUp();

        // TODO: modify this setup to enable use of random tokens not in treasury
        // calculate the number of tokens not in the treasury, to be distributed to actors
        uint256 tokensNotInTreasury = _token.balanceOf(_tokenDeployer) - treasury;

        _standardFundingHandler = new StandardFundingHandler(
            payable(address(_grantFund)),
            address(_token),
            _tokenDeployer,
            NUM_ACTORS,
            tokensNotInTreasury
        );

        // get the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = _standardFundingHandler.startNewDistributionPeriod.selector;
        selectors[1] = _standardFundingHandler.proposeStandard.selector;
        selectors[2] = _standardFundingHandler.screeningVote.selector;
        selectors[3] = _standardFundingHandler.fundingVote.selector;
        selectors[4] = _standardFundingHandler.updateSlate.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardFundingHandler),
            selectors: selectors
        }));

        // explicitly target handler
        targetContract(address(_standardFundingHandler));

        // skip time for snapshots and start distribution period
        vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);
        _grantFund.startNewDistributionPeriod();
    }

}
