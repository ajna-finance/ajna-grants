// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Initializable } from "@oz-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@oz-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "@oz-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from "@oz-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@oz-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import { ERC20VotesUpgradeable } from "@oz-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import { ERC1967Proxy } from "@oz/proxy/ERC1967/ERC1967Proxy.sol";


contract AjnaToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC20_init("AjnaToken", "AJNA");
        __ERC20Burnable_init();
        __ERC20Permit_init("AjnaToken");
        __ERC20Votes_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    // The following functions are overrides required by Solidity.

    /**************************/
    /*** REQUIRED OVERRIDES ***/
    /**************************/

    function _afterTokenTransfer(address from_, address to_, uint256 amount_)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from_, to_, amount_);
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 amount_)
        internal
        override(ERC20Upgradeable)
    {
        require(to_ != address(this), "Cannot transfer tokens to the contract itself");
        super._beforeTokenTransfer(from_, to_, amount_);
    }

    function _mint(address to_, uint256 amount_)
        internal
        onlyInitializing
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to_, amount_);
    }

    function _burn(address account_, uint256 amount_)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account_, amount_);
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

contract UUPSProxy is ERC1967Proxy {

    constructor(address implementation_, bytes memory data_)
        ERC1967Proxy(implementation_, data_)
    {}
}
