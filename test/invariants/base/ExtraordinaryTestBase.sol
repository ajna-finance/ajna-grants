// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";

import { TestBase }             from "./TestBase.sol";
import { ExtraordinaryHandler } from "../handlers/ExtraordinaryHandler.sol";

contract ExtraordinaryTestBase is TestBase {

    uint256 internal constant NUM_ACTORS = 10;
    uint256 public constant TOKENS_TO_DISTRIBUTE = 500_000_000 * 1e18;

    ExtraordinaryHandler internal _extraordinaryHandler;

    function setUp() public virtual override {
        super.setUp();

        // TODO: modify this setup to enable use of random tokens not in treasury
        _extraordinaryHandler = new ExtraordinaryHandler(
            payable(address(_grantFund)),
            address(_ajna),
            _tokenDeployer,
            NUM_ACTORS,
            TOKENS_TO_DISTRIBUTE,
            address(this)
        );

        // explicitly target handler
        targetContract(address(_extraordinaryHandler));
    }

}
