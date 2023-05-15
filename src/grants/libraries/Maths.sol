// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeCast }  from "@oz/utils/math/SafeCast.sol";

library Maths {

    uint256 internal constant WAD = 10**18;

    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? SafeCast.toUint256(x) : SafeCast.toUint256(-x);
    }

    /**
     * @notice Returns the square root of a WAD, as a WAD.
     * @dev Utilizes the babylonian method: https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
     * @param y The WAD to take the square root of.
     * @return z The square root of the WAD, as a WAD.
     */
    function wsqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // convert z to a WAD
        z = z * 10**9;
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + WAD / 2) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD + y / 2) / y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    /** @notice Raises a WAD to the power of an integer and returns a WAD */
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
