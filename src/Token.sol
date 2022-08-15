// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Initializable } from "@openzeppelin/openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from "@openzeppelin/openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/openzeppelin-contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import { ERC20VotesUpgradeable } from "@openzeppelin/openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

contract AjnaToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        initialize();
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC20_init("AjnaToken", "AJNA");
        __ERC20Burnable_init();
        __ERC20Permit_init("AjnaToken");
        __ERC20Votes_init();

        // 1 billion token initial supply, with 18 decimals
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from_, address to_, uint256 amount_)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from_, to_, amount_);
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 amount_)
        internal
        override(ERC20Upgradeable) {
        // This can be achived by setting _balances[address(this)] to the max value uint256.
        // But _balances are private variable in the OpenZeppelin ERC20 contract implementation.

        require(to_ != address(this), "Cannot transfer tokens to the contract itself");
        super._beforeTokenTransfer(from_, to_, amount_);
    }

    function _mint(address to_, uint256 amount_)
        internal
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
}