// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../src/GrantFund.sol";
import "../src/interfaces/IExtraordinaryFunding.sol";

import "./GrantFundTestHelper.sol";

import "../src/libraries/Maths.sol";


contract ExtraordinaryFundingGrantFundTest is GrantFundTestHelper {

    AjnaToken          internal  _token;
    IVotes             internal  _votingToken;
    GrantFund         internal  _grantFund;

    address internal _tokenDeployer  = makeAddr("tokenDeployer");
    address internal _tokenHolder1   = makeAddr("_tokenHolder1");
    address internal _tokenHolder2   = makeAddr("_tokenHolder2");
    address internal _tokenHolder3   = makeAddr("_tokenHolder3");
    address internal _tokenHolder4   = makeAddr("_tokenHolder4");
    address internal _tokenHolder5   = makeAddr("_tokenHolder5");
    address internal _tokenHolder6   = makeAddr("_tokenHolder6");
    address internal _tokenHolder7   = makeAddr("_tokenHolder7");
    address internal _tokenHolder8   = makeAddr("_tokenHolder8");
    address internal _tokenHolder9   = makeAddr("_tokenHolder9");
    address internal _tokenHolder10   = makeAddr("_tokenHolder10");
    address internal _tokenHolder11   = makeAddr("_tokenHolder11");
    address internal _tokenHolder12   = makeAddr("_tokenHolder12");
    address internal _tokenHolder13   = makeAddr("_tokenHolder13");
    address internal _tokenHolder14   = makeAddr("_tokenHolder14");
    address internal _tokenHolder15   = makeAddr("_tokenHolder15");

    address[] internal _selfDelegatedVotersArr = [
        _tokenHolder1,
        _tokenHolder2,
        _tokenHolder3,
        _tokenHolder4,
        _tokenHolder5,
        _tokenHolder6,
        _tokenHolder7,
        _tokenHolder8,
        _tokenHolder9,
        _tokenHolder10,
        _tokenHolder11,
        _tokenHolder12,
        _tokenHolder13,
        _tokenHolder14,
        _tokenHolder15
    ];

    uint256 _initialAjnaTokenSupply   = 2_000_000_000 * 1e18;

    function setUp() external {
        vm.startPrank(_tokenDeployer);
        _token = new AjnaToken(_tokenDeployer);

        // deploy voting token wrapper
        _votingToken = IVotes(address(_token));

        // deploy growth fund contract
        _grantFund = new GrantFund(_votingToken);

        // TODO: replace with for loop -> test address initializer method that created array and transfers tokens given n?
        // initial minter distributes tokens to test addresses
        changePrank(_tokenDeployer);
        _token.transfer(_tokenHolder1, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder2, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder3, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder4, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder5, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder6, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder7, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder8, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder9, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder10, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder11, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder12, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder13, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder14, 50_000_000 * 1e18);
        _token.transfer(_tokenHolder15, 50_000_000 * 1e18);

        // initial minter distributes treasury to grantFund
        _token.transfer(address(_grantFund), 500_000_000 * 1e18);
    }

    function testGetVotingPowerExtraordinary() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(50);

        uint256 votingPower = _grantFund.getVotesWithParams(_tokenHolder1, block.number, "Extraordinary");
        assertEq(votingPower, 0);
    }

    function testGetMinimumThresholdPercentage() external {
        // default threshold percentage is 50
        uint256 minimumThresholdPercentage = _grantFund.getMinimumThresholdPercentage();
        assertEq(minimumThresholdPercentage, 50);

        // TODO: check percentage updates after proposal is passed
    }

    /** 
     * @notice Calculate the number of tokens equivalent to various percentages assuming a treasury balance of 500,000,000.
     */
    function testGetPercentageOfTreasury() external {
        uint256 percentageRequested = 0.100000000000000000 * 1e18;
        uint256 percentageOfTreasury = _grantFund.getPercentageOfTreasury(percentageRequested);
        assertEq(percentageOfTreasury, 50_000_000 * 1e18);

        percentageRequested = 0.055000000000000000 * 1e18;
        percentageOfTreasury = _grantFund.getPercentageOfTreasury(percentageRequested);
        assertEq(percentageOfTreasury, 27_500_000 * 1e18);
    }

    function testProposeExtraordinary() external {
        // 14 tokenholders self delegate their tokens to enable voting on the proposals
        _selfDelegateVoters(_token, _selfDelegatedVotersArr);

        vm.roll(100);

        // set proposal params
        uint256 percentageRequested = 0.100000000000000000 * 1e18;
        uint256 endBlock = block.number + 100_000;

        // generate proposal targets
        address[] memory targets = new address[](1);
        targets[0] = address(_token);

        // generate proposal values
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // generate proposal calldata
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            _tokenHolder1,
            1 * 1e18
        );

        // generate proposal message
        string memory description = "Extraordinary Proposal for Ajna token transfer to tester address";

        _grantFund.proposeExtraordinary(percentageRequested, endBlock, targets, values, calldatas, description);
    }

    function testProposeExtraordinaryInvalid() external {
        // _grantFund.proposeExtraordinary();
    }



}
