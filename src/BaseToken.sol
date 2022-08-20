// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ERC20 } from "@oz/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@oz/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from  "@oz/token/ERC20/extensions/draft-ERC20Permit.sol";

contract AjnaToken is ERC20, ERC20Burnable, ERC20Permit {
    constructor() ERC20("AjnaToken", "AJNA") ERC20Permit("AjnaToken") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    /*****************/
    /*** Overrides ***/
    /*****************/

    /**
     *  @notice Ensure tokens cannot be transferred to token contract
     */
    function _beforeTokenTransfer(address, address to_, uint256) internal view override {
        require(to_ != address(this), "Cannot transfer tokens to the contract itself");
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Called by an owner of AJNA tokens to enable their tokens to be transferred by a spender address without making a seperate permit call
     *  @param  from_     The address of the current owner of the tokens
     *  @param  to_       The address of the new owner of the tokens
     *  @param  spender_  The address of the third party who will execute the transaction involving an owners tokens
     *  @param  value_    The amount of tokens to transfer
     *  @param  deadline_ The unix timestamp by which the permit must be called
     *  @param  v_        Component of secp256k1 signature
     *  @param  r_        Component of secp256k1 signature
     *  @param  s_        Component of secp256k1 signature
     */
    function transferFromWithPermit(
        address from_, address to_, address spender_, uint256 value_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_
    ) external {
        permit(from_, spender_, value_, deadline_, v_, r_, s_);
        transferFrom(from_, to_, value_);
    }
}
