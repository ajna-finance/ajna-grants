// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeCast }  from "@oz/utils/math/SafeCast.sol";

library Maths {

    uint256 internal constant WAD = 10**18;

    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? SafeCast.toUint256(x) : SafeCast.toUint256(-x);
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
