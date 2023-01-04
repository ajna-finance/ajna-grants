// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Governor }        from "@oz/governance/Governor.sol";
import { ReentrancyGuard } from "@oz/security/ReentrancyGuard.sol";

abstract contract Funding is Governor, ReentrancyGuard {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice Voter has already voted on a proposal in the screening stage in a quarter.
     */
    error AlreadyVoted();

    /**
     * @notice Non Ajna token contract address specified in target list.
     */
    error InvalidTarget();

    /**
     * @notice Non-zero amount specified in values array.
     * @dev This parameter is only used for sending ETH which the GrantFund doesn't utilize.
     */
    error InvalidValues();

    /**
     * @notice Calldata for a method other than `transfer(address,uint256) was provided in a proposal.
     * @dev seth sig "transfer(address,uint256)" == 0xa9059cbb.
     */
    error InvalidSignature();

    /**
     * @notice User attempted to submit a proposal with too many target, values or calldatas, or to the wrong method.
     */
    error InvalidProposal();

    /**
     * @notice User attempted to interacted with a method not implemented in the GrantFund.
     */
    error MethodNotImplemented();

    /**
     * @notice User attempted to submit a duplicate proposal.
     */
    error ProposalAlreadyExists();

    /**
     * @notice Provided proposalId isn't present in either funding mechanisms storage mappings.
     */
    error ProposalNotFound();

    /***********************/
    /*** State Variables ***/
    /***********************/

    // address of the ajna token used in grant coordination
    address public ajnaTokenAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /**
     * @notice Enum listing available proposal types.
     */
    enum FundingMechanism {
        Standard,
        Extraordinary
    }

    /**
     * @notice Mapping checking if a voter has voted on a given proposal.
     * @dev proposalId => address => bool.
     */
    mapping(uint256 => mapping(address => bool)) internal hasVotedExtraordinary;

    /**
     * @notice Mapping checking if a voter has voted in screening in a given distribution quarter.
     * @dev distributionId => address => bool.
     */
    mapping(uint256 => mapping(address => bool)) internal hasVotedScreening;

    /**
     * @notice Total funds available for Funding Mechanism
    */
    uint256 public treasury;

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     * @notice Verifies proposal's targets, values, and calldatas match specifications.
     * @param targets_         The addresses of the contracts to call.
     * @param values_          The amounts of ETH to send to each target.
     * @param calldatas_       The calldata to send to each target.
     * @return tokensRequested_ The amount of tokens requested in the calldata.
     */
    function _validateCallDatas(address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_) internal view returns (uint256 tokensRequested_) {

        for (uint256 i = 0; i < targets_.length;) {

            // check  targets and values are valid
            if (targets_[i] != ajnaTokenAddress) revert InvalidTarget();
            if (values_[i] != 0) revert InvalidValues();

            // check calldata function selector is transfer()
            bytes memory selDataWithSig = calldatas_[i];

            bytes4 selector;
            //slither-disable-next-line assembly
            assembly {
                selector := mload(add(selDataWithSig, 0x20))
            }
            if (selector != bytes4(0xa9059cbb)) revert InvalidSignature();

            // https://github.com/ethereum/solidity/issues/9439
            // retrieve tokensRequested from incoming calldata, accounting for selector and recipient address
            uint256 tokensRequested;
            bytes memory tokenDataWithSig = calldatas_[i];
            //slither-disable-next-line assembly
            assembly {
                tokensRequested := mload(add(tokenDataWithSig, 68))
            }

            // update tokens requested for additional calldata
            tokensRequested_ += tokensRequested;

            unchecked {
                ++i;
            }
        }
    }
}
