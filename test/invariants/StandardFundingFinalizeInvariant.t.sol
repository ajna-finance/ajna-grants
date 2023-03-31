// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { StandardFundingTestBase } from "./base/StandardFundingTestBase.sol";
import { StandardFundingHandler } from "./handlers/StandardFundingHandler.sol";

contract StandardFundingFinalizeInvariant is StandardFundingTestBase {

    // override setup to start tests in the funding stage with proposals that have already been screened and funded
    function setUp() public override {
        super.setUp();

        // create 15 proposals
        _standardFundingHandler.createProposals(15);

        // vote on proposals
        _standardFundingHandler.screeningVoteProposals();

        // skip time into the funding stage
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        uint256 fundingStageStartBlock = endBlock - 72000;
        vm.roll(fundingStageStartBlock + 100);

        // TODO: voter's cast funding votes randomly
        _standardFundingHandler.fundingVoteProposals();

        // skip time into the challenge stage
        vm.roll(endBlock + 100);

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _standardFundingHandler.fundingVote.selector;
        selectors[1] = _standardFundingHandler.updateSlate.selector;
        selectors[2] = _standardFundingHandler.executeStandard.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardFundingHandler),
            selectors: selectors
        }));
    }

    function invariant_CS1_CS2_CS3_CS4_CS5() external {
        uint24 distributionId = _grantFund.getDistributionId();

        // StandardFundingHandler.DistributionState memory distributionState = _standardFundingHandler.distributionStates(distributionId);

        (, , , uint128 fundsAvailable, , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId);

        uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

        uint256[] memory topTenScreenedProposalIds = _grantFund.getTopTenProposals(distributionId);

        // invariant CS2: top slate should have 10 or less proposals
        assertTrue(topSlateProposalIds.length <= 10);

        // check proposal state of the constituents of the top slate
        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < topSlateProposalIds.length; ++i) {
            uint256 proposalId = topSlateProposalIds[i];
            (, , , uint128 tokensRequested, int128 fundingVotesReceived, ) = _grantFund.getProposalInfo(proposalId);
            totalTokensRequested += tokensRequested;

            // invariant CS3: Proposal slate should never contain a proposal with negative funding votes received
            assertTrue(fundingVotesReceived >= 0);

            // invariant CS4: Proposal slate should never contain a proposal that wasn't in the top ten in the funding stage.
            assertTrue(_findProposalIndex(proposalId, topTenScreenedProposalIds) != -1);
        }

        // invariant CS1: total tokens requested should be <= 90% of fundsAvailable
        assertTrue(totalTokensRequested <= uint256(fundsAvailable) * 9 / 10);

        // invariant CS5: proposal slate should never contain duplicate proposals
        assertFalse(_standardFundingHandler.hasDuplicates(topSlateProposalIds));
    }

}
