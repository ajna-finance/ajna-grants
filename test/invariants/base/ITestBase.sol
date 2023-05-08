// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface ITestBase {

    function currentBlock() external view returns (uint256 currentBlock);

    function setCurrentBlock(uint256 currentBlock) external;

}
