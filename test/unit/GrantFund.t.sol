// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { GrantFund }        from "../../src/grants/GrantFund.sol";
import { IGrantFundErrors } from "../../src/grants/interfaces/IGrantFundErrors.sol";
import { Maths }            from "../../src/grants/libraries/Maths.sol";

import { IAjnaToken }          from "../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../utils/GrantFundTestHelper.sol";
import { TestAjnaToken }       from "../utils/harness/TestAjnaToken.sol";

contract GrantFundTest is GrantFundTestHelper {

    /*************/
    /*** Setup ***/
    /*************/

    IAjnaToken        internal  _token;
    GrantFund         internal  _grantFund;

    // at this block on mainnet, all ajna tokens belongs to _tokenDeployer
    uint256 internal _startBlock = 16354861;

    // Ajna token Holder at the Ajna contract creation on mainnet
    address internal _tokenDeployer  = makeAddr("_tokenDeployer");
    address internal _tokenHolder1   = makeAddr("_tokenHolder1");
    address internal _tokenHolder2   = makeAddr("_tokenHolder2");
    address internal _tokenHolder3   = makeAddr("_tokenHolder3");

    address[] internal _votersArr = [
        _tokenHolder1,
        _tokenHolder2,
        _tokenHolder3
    ];

    function setUp() external {
        // deploy grant fund, skip funding treasury, and transfer tokens to initial set of voters
        uint256 treasury = 0;
        uint256 initialVoterBalance = 50_000_000 * 1e18;
        (_grantFund, _token) = _deployAndFundGrantFund(_tokenDeployer, treasury, _votersArr, initialVoterBalance);
    }

    /*************/
    /*** Tests ***/
    /*************/

    function testFundTreasury() external {
        // should be able to add additional funds to the treasury
        changePrank(_tokenHolder1);
        _token.approve(address(_grantFund), 50_000_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit FundTreasury(50_000_000 * 1e18, 50_000_000 * 1e18);
        _grantFund.fundTreasury(50_000_000 * 1e18);
    }

    function testTreasuryDistributionPeriodFunding() external {
        // fund treasury before and after starting the distribution period
        changePrank(_tokenDeployer);
        _token.approve(address(_grantFund), 100_000_000 * 1e18);
        _grantFund.fundTreasury(50_000_000 * 1e18);

        // start distribution period
        uint24 distributionId = _startDistributionPeriod(_grantFund);

        // calculate expected funds available
        uint256 expectedFundsAvailable = Maths.wmul(50_000_000 * 1e18, 0.03 * 1e18);

        // get distribution period info and check funds available doesn't update for the distribution period
        (, , , uint128 fundsAvailable, , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(fundsAvailable, expectedFundsAvailable);

        // fund treasury after distribution period started
        _grantFund.fundTreasury(50_000_000 * 1e18);

        // get distribution period info and check funds available doesn't update for the distribution period
        (, , , fundsAvailable, , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        assertEq(fundsAvailable, expectedFundsAvailable);
    }

    function testTreasuryInsufficientBalanceStandard() external {
        // voter self delegates
        _token.delegate(_tokenHolder1);

        vm.roll(_startBlock + 100);

        // start distribution period
        _startDistributionPeriod(_grantFund);

        // fund treasury after distribution period started
        changePrank(_tokenDeployer);
        _token.approve(address(_grantFund), 50_000_000 * 1e18);
        _grantFund.fundTreasury(50_000_000 * 1e18);

        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        // Eth to transfer is non zero
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder2,
            1 * 1e18
        );

        // generate proposal message 
        string memory description = "Proposal for Ajna token transfer to tester address";

        // should revert when standard funding proposal created for an amount greater than that in the treasury
        vm.expectRevert(IGrantFundErrors.InvalidProposal.selector);
        _grantFund.propose(targets, values, calldatas, description);
    }

}
