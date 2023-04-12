// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Test }   from "@std/Test.sol";

import { GrantFund }        from "../../../src/grants/GrantFund.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { TestAjnaToken }       from "../../utils/TestAjnaToken.sol";

contract TestBase is Test, GrantFundTestHelper {
    IAjnaToken        internal  _ajna;
    GrantFund         internal  _grantFund;

    // token deployment variables
    // address internal _tokenDeployer = 0x666cf594fB18622e1ddB91468309a7E194ccb799;
    address internal _tokenDeployer = makeAddr("tokenDeployer");
    uint256 public   _startBlock    = 16354861; // at this block on mainnet, all ajna tokens belongs to _tokenDeployer

    // initial treasury value
    uint256 treasury = 500_000_000 * 1e18;

    uint256 public currentBlock;

    function setUp() public virtual {
        // vm.createSelectFork(vm.envString("ETH_RPC_URL"), _startBlock);

        // provide cheatcode access to the standard funding handler
        vm.allowCheatcodes(0x4447E7a83995B5cCDCc9A6cd8Bc470305C940DA3);

        // TestAjnaToken token = new TestAjnaToken(_tokenDeployer);
        // vm.etch(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079, address(token).code);

        // bytes memory args = abi.encode(_tokenDeployer);
        // bytes memory bytecode = abi.encodePacked(vm.getCode("TestAjnaToken.sol:TestAjnaToken"), args);
        // // // bytes memory bytecode = abi.encodePacked(type(TestAjnaToken).creationCode, args);

        // // // address deployAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
        // // // assembly {
        // // //     deployAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        // // // }

        // // // address deployAddress;
        // // // assembly {
        // // //     deployAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        // // // }
        // // // vm.etch(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079, deployAddress.code);

        // address deployAddress;
        // assembly {
        //     deployAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        // }
        // vm.etch(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079, deployAddress.code);

        // // // vm.etch(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079, type(TestAjnaToken).creationCode);

        // // assertEq(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079.code, deployAddress.code);


        // // Ajna Token contract address on mainnet
        // _ajna = IAjnaToken(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079);

        // _ajna.mint(_tokenDeployer);

        // // deploy growth fund contract
        // _grantFund = new GrantFund();

        // vm.startPrank(_tokenDeployer);

        // emit log_uint(_ajna.balanceOf(_tokenDeployer));
        // emit log_uint(_ajna.totalSupply());
        // // emit log_uint(token.totalSupply());
        // emit log_address(address(_ajna));
        // // emit log_address(address(token));

        // // initial minter distributes treasury to grantFund
        // _ajna.approve(address(_grantFund), treasury);
        // _grantFund.fundTreasury(treasury);

        // exclude unrelated contracts
        // excludeContract(address(_ajna));

        // vm.makePersistent(address(_ajna));

        currentBlock = block.number;
    }

    function setCurrentBlock(uint256 currentBlock_) external {
        currentBlock = currentBlock_;
    }

}
