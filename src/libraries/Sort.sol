// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { GrowthFund } from "../GrowthFund.sol";

library Sort {

    // TODO: move this into sort library
    // return the index of the proposalId in the array, else -1
    function findInArray(uint256 proposalId, GrowthFund.Proposal[] storage array) internal view returns (int256 index) {
        index = -1; // default value indicating proposalId not in the array

        for (int i = 0; i < int(array.length);) {
            if (array[uint256(i)].proposalId == proposalId) {
                index = i;
            }

            unchecked {
                ++i;
            }
        }
    }

    // TODO: move this into sort library
    /**
     * @notice Determine the 10 proposals which will make it through screening and move on to the funding round.
     * @dev    Implements the descending quicksort algorithm from this discussion: https://gist.github.com/subhodi/b3b86cc13ad2636420963e692a4d896f#file-quicksort-sol-L12
     */
    function quickSortProposalsByVotes(GrowthFund.Proposal[] storage arr, int left, int right) internal {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)].votesReceived;
        while (i <= j) {
            while (arr[uint(i)].votesReceived > pivot) i++;
            while (pivot > arr[uint(j)].votesReceived) j--;
            if (i <= j) {
                GrowthFund.Proposal memory temp = arr[uint(i)];
                arr[uint(i)] = arr[uint(j)];
                arr[uint(j)] = temp;
                i++;
                j--;
            }
        }
        if (left < j)
            quickSortProposalsByVotes(arr, left, j);
        if (i < right)
            quickSortProposalsByVotes(arr, i, right);
    }

}