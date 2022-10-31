// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/governance/Governor.sol";

abstract contract Funding is Governor {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice Voter has already voted on a proposal in the screening stage in a quarter.
     */
    error AlreadyVoted();

    /***********************/
    /*** State Variables ***/
    /***********************/

    // address of the ajna token used in grant coordination
    address public ajnaTokenAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /**
     * @notice Mapping checking if a voter has voted on a given proposal.
     * @dev proposalId => address => bool.
     */
    mapping(uint256 => mapping(address => bool)) hasScreened;

}
