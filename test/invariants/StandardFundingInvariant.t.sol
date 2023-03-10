// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TestBase } from "./TestBase.sol";
import { StandardFundingHandler } from "./StandardFundingHandler.sol";

contract StandardFundingInvariant is TestBase {

    uint256 internal constant NUM_ACTORS = 50;

    StandardFundingHandler internal _standardFundingHandler;

    function setUp() public override virtual{
        super.setUp();

        // calculate the number of tokens not in the treasury, to be distributed to actors
        uint256 tokensNotInTreasury = _token.balanceOf(_tokenDeployer) - treasury;

        _standardFundingHandler = new StandardFundingHandler(
            payable(address(_grantFund)),
            address(_token),
            _tokenDeployer,
            NUM_ACTORS,
            tokensNotInTreasury
        );

        // TODO: Change once this issue is resolved -> https://github.com/foundry-rs/foundry/issues/2963
        targetSender(address(0x1234));
    }

    function invariant_SS1_SS3() public {
        uint256 actorCount = _standardFundingHandler.getActorsCount();

        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);

        if (topTenProposals.length > 1) {
            for (uint256 i = 0; i < topTenProposals.length - 1; ++i) {
                // invariant SS#: proposals should be sorted in descending order
                (, , uint256 votesReceivedCurr, , , ) = _grantFund.getProposalInfo(topTenProposals[i]);
                (, , uint256 votesReceivedNext, , , ) = _grantFund.getProposalInfo(topTenProposals[i + 1]);
                assertTrue(votesReceivedCurr >= votesReceivedNext);

                // invariant SS4: votes recieved for a proposal can only be positive
                assertTrue(votesReceivedCurr > 0);
                assertTrue(votesReceivedNext > 0);
            }
        }
    }

}
