// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IExtraordinaryFunding } from "../interfaces/IExtraordinaryFunding.sol";
import { IStandardFunding }      from "../interfaces/IStandardFunding.sol";

interface IGrantFund is IExtraordinaryFunding, IStandardFunding {


}
