// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IFunding } from "../interfaces/IFunding.sol";
import { IExtraordinaryFunding } from "../interfaces/IExtraordinaryFunding.sol";
import { IStandardFunding }      from "../interfaces/IStandardFunding.sol";

interface IGrantFund is
    IFunding,
    IExtraordinaryFunding,
    IStandardFunding
{

}
