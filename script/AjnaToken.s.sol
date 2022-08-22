// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Script } from "forge-std/Script.sol";
import { AjnaToken } from "../src/BaseToken.sol";

contract DeployAjnaToken is Script {

    function run() public {
        vm.startBroadcast();

        new AjnaToken(vm.envAddress("MINT_TO_ADDRESS"));

        vm.stopBroadcast();
    }
}
