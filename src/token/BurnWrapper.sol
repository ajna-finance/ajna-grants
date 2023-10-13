// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.7;


import { ERC20 }          from "@oz/token/ERC20/ERC20.sol";
import { IERC20 }         from "@oz/token/ERC20/IERC20.sol";
import { ERC20Burnable }  from "@oz/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit }    from "@oz/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20Wrapper }   from "@oz/token/ERC20/extensions/ERC20Wrapper.sol";
import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Ajna Token `ERC20` token interface.
 * @dev Ajna Token `ERC20` token interface, including the following functions:
 * - `burnFrom()`
 * @dev Used by the `BurnWrappedAjna` contract to burn Ajna tokens on wrapping.
*/
interface IERC20Token {
    /**
     * @notice Burns `amount` tokens from `account`, deducting from the caller's allowance and balance.
     * @param account Account to burn tokens from.
     * @param amount Amount of tokens to burn.
     */
    function burnFrom(address account, uint256 amount) external;
}


/**
 *  @title  BurnWrappedAjna Contract
 *  @notice Entrypoint of BurnWrappedAjna actions for Ajna token holders looking to migrate their tokens to a sidechain:
 *          - `TokenHolders`: Approve the BurnWrappedAjna contract to burn a specified amount of Ajna tokens, and call `depositFor()` to mint them a corresponding amount of bwAJNA tokens.
 *  @dev    This contract is intended for usage in cases where users are attempting to migrate their Ajna to a sidechain that lacks a permissionless bridge.
 *          Usage of this contract protects holders from the risk of a compromised sidechain bridge.
 *  @dev    Contract inherits from OpenZeppelin ERC20Burnable and ERC20Wrapper extensions.
 *  @dev    Only mainnet Ajna token can be wrapped. Tokens that have been wrapped cannot be unwrapped, as they are burned on wrapping.
 *  @dev    Holders must call `depositFor()` to wrap their tokens. Transferring Ajna tokens to the wrapper contract directly results in loss of tokens.
 */
contract BurnWrappedAjna is ERC20, ERC20Burnable, ERC20Permit, ERC20Wrapper {

    /**
     * @notice Ethereum mainnet address of the Ajna Token.
     */
    address internal constant AJNA_TOKEN_ADDRESS = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /**
     * @notice Tokens that have been wrapped cannot be unwrapped.
     */
    error UnwrapNotAllowed();

    /**
     * @notice Only mainnet Ajna token can be wrapped.
     */
    error InvalidWrappedToken();

    constructor(IERC20 wrappedToken)
        ERC20("Burn Wrapped AJNA", "bwAJNA")
        ERC20Permit("Burn Wrapped AJNA") // enables wrapped token to also use permit functionality
        ERC20Wrapper(wrappedToken)
    {
        if (address(wrappedToken) != AJNA_TOKEN_ADDRESS) {
            revert InvalidWrappedToken();
        }
    }

    /*****************/
    /*** OVERRIDES ***/
    /*****************/

    /**
     * @dev See {ERC20-decimals} and {ERC20Wrapper-decimals}.
     */
    function decimals() public pure override(ERC20, ERC20Wrapper) returns (uint8) {
        // since the Ajna Token has 18 decimals, we can just return 18 here.
        return 18;
    }

    /**
     * @notice Override wrap method to burn Ajna tokens on wrapping instead of transferring to the wrapper contract.
     */
    function depositFor(address account, uint256 amount) public override returns (bool) {
        // burn the existing ajna tokens
        IERC20Token(AJNA_TOKEN_ADDRESS).burnFrom(account, amount);

        // mint the new wrapped tokens
        _mint(account, amount);
        return true;
    }

    /**
     * @notice Override unwrap method to ensure burn wrapped tokens can't be unwrapped.
     */
    function withdrawTo(address, uint256) public pure override returns (bool) {
        revert UnwrapNotAllowed();
    }

}
