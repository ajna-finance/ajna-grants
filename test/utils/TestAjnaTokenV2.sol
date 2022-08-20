// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Initializable } from "@oz-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@oz-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@oz-upgradeable/security/PausableUpgradeable.sol";
import { ERC20Upgradeable } from "@oz-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from "@oz-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@oz-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import { ERC20VotesUpgradeable } from "@oz-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import { ERC1967Proxy } from "@oz/proxy/ERC1967/ERC1967Proxy.sol";


contract TestAjnaTokenV2 is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    uint256 public testVar;

    function setTestVar(uint256 value_) external {
        testVar = value_;
    }

    function initialize() initializer public {
        __ERC20_init("AjnaToken", "AJNA");
        __ERC20Burnable_init();
        __ERC20Permit_init("AjnaToken");
        __ERC20Votes_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        __Pausable_init();                

        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
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

contract UUPSProxy is ERC1967Proxy {

    constructor(address implementation_, bytes memory data_)
        ERC1967Proxy(implementation_, data_)
    {}
}
