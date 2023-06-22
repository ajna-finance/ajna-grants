// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console }  from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IGrantFund } from "../../../src/grants/interfaces/IGrantFund.sol";

import { StandardTestBase } from "../base/StandardTestBase.sol";
import { StandardHandler }  from "../handlers/StandardHandler.sol";

contract FundingInvariant is StandardTestBase {

    // override setup to start tests in the funding stage with already screened proposals
    function setUp() public override {
        super.setUp();

        startDistributionPeriod();

        // create 15 proposals
        _standardHandler.createProposals(15);

        // cast screening votes on proposals
        _standardHandler.screeningVoteProposals();

        // skip time into the funding stage
        uint24 distributionId = _grantFund.getDistributionId();
        (, uint256 startBlock, , , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        uint256 fundingStageStartBlock = _grantFund.getScreeningStageEndBlock(startBlock) + 1;
        vm.roll(fundingStageStartBlock + 100);
        currentBlock = fundingStageStartBlock + 100;

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = _standardHandler.fundingVote.selector;
        selectors[1] = _standardHandler.updateSlate.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardHandler),
            selectors: selectors
        }));

        uint256[] memory initialTopTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());
        initialTopTenHash = keccak256(abi.encode(initialTopTenProposals));
        assertTrue(initialTopTenProposals.length > 0);
    }

    function invariant_funding_stage() external useCurrentBlock {
        _invariant_FS1_FS2_FS3(_grantFund, _standardHandler);
        _invariant_FS4_FS5_FS6_FS7_FS8(_grantFund, _standardHandler);
    }

    function invariant_call_summary() external useCurrentBlock {
        uint24 distributionId = _grantFund.getDistributionId();

        _logger.logCallSummary();
        _logger.logProposalSummary();
        _logger.logActorSummary(distributionId, true, false);
        _logger.logFundingSummary(distributionId);
    }

}
