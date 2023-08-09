// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Script }  from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { BurnWrappedAjna } from "../src/token/BurnWrapper.sol";
import { IERC20 }    from "@oz/token/ERC20/IERC20.sol";

contract DeployBurnWrapper is Script {
    function run() public {
        IERC20 ajna = IERC20(vm.envAddress("AJNA_TOKEN"));

        vm.startBroadcast();
        address wrapperAddress = address(new BurnWrappedAjna());
        vm.stopBroadcast();

        console.log("Created BurnWrapper at %s for AJNA token at %s", wrapperAddress, address(ajna));
    }
}
