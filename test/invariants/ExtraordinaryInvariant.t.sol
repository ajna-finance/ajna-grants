// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console }  from "@std/console.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";

import { IExtraordinaryFunding } from "../../src/grants/interfaces/IExtraordinaryFunding.sol";
import { Maths }                 from "../../src/grants/libraries/Maths.sol";

import { ExtraordinaryTestBase } from "./base/ExtraordinaryTestBase.sol";
import { ExtraordinaryHandler }  from "./handlers/ExtraordinaryHandler.sol";

contract ExtraordinaryInvariant is ExtraordinaryTestBase {

    function setUp() public override {
        super.setUp();

        // TODO: need to setCurrentBlock?
        currentBlock = block.number;

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = _extraordinaryHandler.proposeExtraordinary.selector;
        selectors[1] = _extraordinaryHandler.voteExtraordinary.selector;
        selectors[2] = _extraordinaryHandler.executeExtraordinary.selector;
        selectors[3] = _extraordinaryHandler.roll.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_extraordinaryHandler),
            selectors: selectors
        }));
    }

    function invariant_call_summary() external view {
        _extraordinaryHandler.logCallSummary();
        _extraordinaryHandler.logActorSummary(true);
    }

}
