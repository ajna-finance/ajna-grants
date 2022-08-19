// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ERC20 }          from "@oz/token/ERC20/ERC20.sol";
import { IERC20 }         from "@oz/token/ERC20/IERC20.sol";
import { ERC20Permit }    from "@oz/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20Wrapper }   from "@oz/token/ERC20/extensions/ERC20Wrapper.sol";
import { ERC20Votes }     from "@oz/token/ERC20/extensions/ERC20Votes.sol";
import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// NOTES: https://forum.openzeppelin.com/t/erc20-wrapper-tutorial/23536

contract WrappedAjnaToken is ERC20, ERC20Wrapper, ERC20Votes {

    constructor(IERC20 wrappedToken)
        ERC20("Wrapped AJNA", "wAJNA")
        ERC20Permit("Wrapped AJNA") // enables wrapped token to also use permit functionality
        ERC20Wrapper(wrappedToken)
    {}

    /**************************/
    /*** REQUIRED OVERRIDES ***/
    /**************************/

    /**
     * @dev See {ERC20-decimals} and {ERC20Wrapper-decimals}.
     */
    function decimals() public view override(ERC20, ERC20Wrapper) returns (uint8) {
        try IERC20Metadata(address(this.underlying())).decimals() returns (uint8 value) {
            return value;
        } catch {
            return super.decimals();
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }
 
    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }
 
    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }

}
