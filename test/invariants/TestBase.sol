// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IVotes } from "@oz/governance/utils/IVotes.sol";
import { Test }   from "@std/Test.sol";

import { IAjnaToken }   from "../utils/IAjnaToken.sol";
import { InvariantTest} from "./InvariantTest.sol";

import { GrantFund }        from "../../src/grants/GrantFund.sol";

contract TestBase is InvariantTest, Test {
    IAjnaToken        internal  _token;
    IVotes            internal  _votingToken;
    GrantFund         internal  _grantFund;

    // token deployment variables
    address internal _tokenDeployer = 0x666cf594fB18622e1ddB91468309a7E194ccb799;
    uint256 internal _startBlock    = 16354861; // at this block on mainnet, all ajna tokens belongs to _tokenDeployer

    // initial treasury value
    uint256 treasury = 500_000_000 * 1e18;

    function setUp() public virtual {

        vm.createSelectFork(vm.envString("ETH_RPC_URL"), _startBlock);

        // Ajna Token contract address on mainnet
        _token = IAjnaToken(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079);

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _grantFund = new GrantFund(_votingToken, treasury);

        vm.startPrank(_tokenDeployer);

        // initial minter distributes treasury to grantFund
        _token.transfer(address(_grantFund), treasury);
    }
}
