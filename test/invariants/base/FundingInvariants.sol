// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { console } from "@std/console.sol";

import { GrantFund }        from "../../../src/grants/GrantFund.sol";
import { IGrantFund }       from "../../../src/grants/interfaces/IGrantFund.sol";

import { TestBase }        from "./TestBase.sol";
import { StandardHandler } from "../handlers/StandardHandler.sol";

abstract contract FundingInvariants is TestBase {}

