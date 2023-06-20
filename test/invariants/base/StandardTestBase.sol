// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console } from "@std/console.sol";

import { Logger }          from "./Logger.sol";
import { StandardHandler } from "../handlers/StandardHandler.sol";
import { TestBase }        from "./TestBase.sol";

import { DistributionPeriodInvariants } from "./DistributionPeriodInvariants.sol";
import { FinalizeInvariants }           from "./FinalizeInvariants.sol";
import { FundingInvariants }            from "./FundingInvariants.sol";
import { ScreeningInvariants }          from "./ScreeningInvariants.sol";

contract StandardTestBase is DistributionPeriodInvariants, FinalizeInvariants, FundingInvariants, ScreeningInvariants {

    uint256 internal constant NUM_ACTORS = 20; // default number of actors
    uint256 internal constant NUM_PROPOSALS = 200; // default maximum number of proposals that can be created in a distribution period
    uint256 internal constant PER_ADDRESS_TOKEN_REQ_CAP = 10; // Percentage of funds available to request per proposal recipient in invariants
    uint256 public constant TOKENS_TO_DISTRIBUTE = 500_000_000 * 1e18;

    StandardHandler internal _standardHandler;
    Logger internal _logger;

    function setUp() public virtual override {
        super.setUp();

        _standardHandler = new StandardHandler(
            payable(address(_grantFund)),
            address(_ajna),
            _tokenDeployer,
            vm.envOr("NUM_ACTORS", NUM_ACTORS),
            vm.envOr("NUM_PROPOSALS", NUM_PROPOSALS),
            vm.envOr("PER_ADDRESS_TOKEN_REQ_CAP", PER_ADDRESS_TOKEN_REQ_CAP),
            TOKENS_TO_DISTRIBUTE,
            address(this)
        );

        // instantiate logger
        _logger = new Logger(address(_grantFund), address(_standardHandler), address(this));

        // explicitly target handler
        targetContract(address(_standardHandler));
    }

    /***************************/
    /**** Utility Functions ****/
    /***************************/

    function startDistributionPeriod() internal {
        // skip time for snapshots and start distribution period
        vm.roll(currentBlock + 100);
        currentBlock = block.number;
        _grantFund.startNewDistributionPeriod();
    }

}
