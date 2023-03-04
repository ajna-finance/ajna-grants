// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.7;

import { ERC20 }         from "@oz/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@oz/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit }   from "@oz/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20Votes }    from "@oz/token/ERC20/extensions/ERC20Votes.sol";

contract AjnaToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes {
    constructor(address tokenReceiver_) ERC20("AjnaToken", "AJNA") ERC20Permit("AjnaToken") {
        _mint(tokenReceiver_, 2_000_000_000 * 10 ** decimals());
    }

    /*****************/
    /*** Overrides ***/
    /*****************/

    function _afterTokenTransfer(address from_, address to_, uint256 amount_) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from_, to_, amount_);
    }

    /**
     *  @notice Ensure tokens cannot be transferred to token contract
     */
    function _beforeTokenTransfer(address, address to_, uint256) internal view override {
        require(to_ != address(this), "Cannot transfer tokens to the contract itself");
    }

    function _burn(address account_, uint256 amount_) internal override(ERC20, ERC20Votes) {
        super._burn(account_, amount_);
    }

    function _mint(address to_, uint256 amount_) internal override(ERC20, ERC20Votes) {
        super._mint(to_, amount_);
    }

}
