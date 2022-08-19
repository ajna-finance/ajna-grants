// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ERC20 } from "@oz/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@oz/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from  "@oz/token/ERC20/extensions/draft-ERC20Permit.sol";

contract AjnaToken is ERC20, ERC20Burnable, ERC20Permit {
    constructor() ERC20("AjnaToken", "AJNA") ERC20Permit("AjnaToken") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }
}
