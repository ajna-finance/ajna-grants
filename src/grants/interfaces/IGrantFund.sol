// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IGrantFundActions } from ".IGrantFundActions.sol";
import { IGrantFundErrors }  from "./IGrantFundErrors.sol";
import { IGrantFundEvents }  from "./IGrantFundEvents.sol";
import { IGrantFundState }   from "./IGrantFundState.sol";

interface IGrantFund is
    IGrantFundActions,
    IGrantFundErrors,
    IGrantFundEvents,
    IGrantFundState
{

}
