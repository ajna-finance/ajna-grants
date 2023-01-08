// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

library Maths {

    uint256 public constant WAD = 10**18;

    function abs(int x) internal pure returns (int) {
        return x >= 0 ? x : -x;
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + 10**18 / 2) / 10**18;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 10**18 + y / 2) / y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    function wad(uint256 x) internal pure returns (uint256) {
        return x * 10**18;
    }

    /** @notice Raises a WAD to the power of an integer and returns a WAD */
    function wpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : 10**18;

        for (n /= 2; n != 0; n /= 2) {
            x = wmul(x, x);

            if (n % 2 != 0) {
                z = wmul(z, x);
            }
        }
    }
}
