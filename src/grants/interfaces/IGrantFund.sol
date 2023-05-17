// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IGrantFundActions } from "./IGrantFundActions.sol";
import { IGrantFundErrors }  from "./IGrantFundErrors.sol";
import { IGrantFundEvents }  from "./IGrantFundEvents.sol";

/**
 * @title Grant Fund Interface.
 * @dev   Combines all interfaces into one.
 * @dev   IGrantFundState is inherited through IGrantFundActions.
 */
interface IGrantFund is
    IGrantFundActions,
    IGrantFundErrors,
    IGrantFundEvents
{

}
