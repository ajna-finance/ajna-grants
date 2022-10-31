// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.16;

/**
 * @title Ajna Grant Coordination Fund
 */
interface IGrantFund {

    /**
        User attempted to vote in a non-specified pathyway.
     */
    error InvalidStage();

    error ProposalNotFound();

}
