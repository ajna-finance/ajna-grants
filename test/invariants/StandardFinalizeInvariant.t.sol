// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { StandardTestBase } from "./base/StandardTestBase.sol";
import { StandardHandler } from "./handlers/StandardHandler.sol";

contract StandardFinalizeInvariant is StandardTestBase {

    // override setup to start tests in the challenge stage with proposals that have already been screened and funded
    function setUp() public override {
        super.setUp();

        // create 15 proposals
        _standardHandler.createProposals(15);

        // cast screening votes on proposals
        _standardHandler.screeningVoteProposals();

        // skip time into the funding stage
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        uint256 fundingStageStartBlock = endBlock - 72000;
        vm.roll(fundingStageStartBlock + 100);

        // cast funding votes on proposals
        try _standardHandler.fundingVoteProposals() {

        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()")) ||
                err == keccak256(abi.encodeWithSignature("FundingVoteWrongDirection()"))
            );
        }

        // skip time into the challenge stage
        vm.roll(endBlock + 100);

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _standardHandler.fundingVote.selector;
        selectors[1] = _standardHandler.updateSlate.selector;
        selectors[2] = _standardHandler.executeStandard.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardHandler),
            selectors: selectors
        }));
    }

    function invariant_CS1_CS2_CS3_CS4_CS5() external {
        uint24 distributionId = _grantFund.getDistributionId();

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
        assertFalse(_standardHandler.hasDuplicates(topSlateProposalIds));
    }

    function invariant_ES1_ES3() external {
        uint24 distributionId = _grantFund.getDistributionId();

        (, , , uint128 fundsAvailable, , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId);

        uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < topSlateProposalIds.length; ++i) {
            uint256 proposalId = topSlateProposalIds[i];
            (, , , uint128 tokensRequested, , ) = _grantFund.getProposalInfo(proposalId);
            totalTokensRequested += tokensRequested;
        }

        uint256[] memory standardFundingProposals = _standardHandler.getStandardFundingProposals();

        // invariant ES1: A proposal can only be executed if it's listed in the final funded proposal slate at the end of the challenge round.
        for (uint256 i = 0; i < _standardHandler.standardFundingProposalCount(); ++i) {
            uint256 proposalId = standardFundingProposals[i];
            (, , , , , bool executed) = _grantFund.getProposalInfo(proposalId);
            int256 proposalIndex = _findProposalIndex(proposalId, topSlateProposalIds);
            if (proposalIndex == -1) {
                assertFalse(executed);
            }
        }

        // invariant ES3: A proposal can only be executed once.
        assertFalse(_standardHandler.hasDuplicates(_standardHandler.getProposalsExecuted()));
    }

    function invariant_call_summary() external view {
        uint24 distributionId = _grantFund.getDistributionId();

        _standardHandler.logCallSummary();
        _standardHandler.logProposalSummary();
        _logFinalizeSummary(distributionId);
    }

    function _logFinalizeSummary(uint24 distributionId_) internal view {
        (, , , uint128 fundsAvailable, , bytes32 topSlateHash) = _grantFund.getDistributionPeriodInfo(distributionId_);
        uint256[] memory topSlateProposalIds = _grantFund.getFundedProposalSlate(topSlateHash);

        uint256[] memory topTenScreenedProposalIds = _grantFund.getTopTenProposals(distributionId_);

        console.log("\nFinalize Summary\n");
        console.log("------------------");
        console.log("Proposal Execute Count:     ", _standardHandler.numberOfCalls('SFH.executeStandard.success'));
        console.log("Slate Update Called:        ", _standardHandler.numberOfCalls('SFH.updateSlate.called'));
        console.log("Slate Update Count:         ", _standardHandler.numberOfCalls('SFH.updateSlate.success'));
        console.log("Top Slate Proposal Count:   ", topSlateProposalIds.length);
        console.log("Top Ten Proposal Count:     ", topTenScreenedProposalIds.length);
        console.log("------------------");
    }

}
