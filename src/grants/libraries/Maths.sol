// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeCast }  from "@oz/utils/math/SafeCast.sol";

/**
    @title  Maths library
    @notice Internal library containing helpful math utility functions.
 */
library Maths {

    /*****************/
    /*** Constants ***/
    /*****************/

    uint256 internal constant WAD = 10**18;

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     * @notice Returns the absolute value of a number.
     * @param x Number to return the absolute value of.
     * @return z Absolute value of the number.
     */
    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? SafeCast.toUint256(x) : SafeCast.toUint256(-x);
    }

    /**
     * @notice Returns the result of multiplying two numbers.
     * @param x First number, WAD.
     * @param y Second number, WAD.
     * @return z Result of multiplication, as a WAD.
     */
    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + WAD / 2) / WAD;
    }

    /**
     * @notice Returns the result of dividing two numbers.
     * @param x First number, WAD.
     * @param y Second number, WAD.
     * @return z Result of division, as a WAD.
     */
    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD + y / 2) / y;
    }

    /**
     * @notice Returns the minimum of two numbers.
     * @param x First number.
     * @param y Second number.
     * @return z Minimum number.
     */
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    /**
     * @notice Raises a WAD to the power of an integer and returns a WAD
     * @param x WAD to raise to a power.
     * @param n Integer power to raise WAD to.
     * @return z Squared number as a WAD.
     */
    function wpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : WAD;

        for (n /= 2; n != 0; n /= 2) {
            x = wmul(x, x);

            if (n % 2 != 0) {
                z = wmul(z, x);
            }
        }
    }

}
