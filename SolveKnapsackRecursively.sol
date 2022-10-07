    // // TODO: determine how to resolve ties
    // /**
    //  * @notice Solve the knapsack problems with a dynamic programming approach.
    //  * @dev inspired by: 
    //  https://www.educative.io/blog/0-1-knapsack-problem-dynamic-solution
    //  https://www.freecodecamp.org/news/how-i-used-algorithms-to-solve-the-knapsack-problem-for-my-real-life-carry-on-knapsack-5f996b0e6895/
    //  * @dev Assumed all token votes are greater than 0, as <0 votes are automatically excluded.
    //  * @return List of proposalIds that maximize this value
    //  */
    // function _solveDistribution(uint256 tokensRequested, uint256 proposalVotes, uint256 budgetConstraint, uint256 currentIndex) public returns (uint256[]) {
    //     if ()

    // }

    // returns the total value of a possible subset
    function _totalValueSubset(Proposal[] memory proposalSubset, uint256 budgetConstraint) public returns (uint256 sum) {
        sum = 0;
        for (uint i = 0; i < proposalSubset.length;) {
            sum += uint256(proposalSubset[i].fundingReceived);

            // check subset sum is less than budget constraint
            if (sum > budgetConstraint) {
                sum = 0;
                break;
            }

            unchecked {
                ++i;
            }
        }
    }

    // TODO: check hash uniqueness
    // https://ethereum.stackexchange.com/questions/47894/how-to-hash-an-array-of-address
    // https://ethereum.stackexchange.com/questions/90758/encoding-address-into-bytes
    // create a unique hash from a subset of proposals
    function _subsetHash(Proposal[] memory proposalSubset_) internal returns (bytes32 subsetHash) {
        // for (uint i = 0; i < proposalSubset_.length;) {

        //     subsetHash = abi.encodePacked(subsetHash, proposalSubset_[i]);

        //     unchecked {
        //         ++i;
        //     }
        // }
        // return keccak256(subsetHash);
        subsetHash = keccak256(abi.encode(proposalSubset_));
    }

    // mapping of subsetHash => subset
    mapping (bytes32 => Proposal[]) cachedSubsets;

    function _copyArray(Proposal[] memory arrayToCopy_, uint256 startIndex_, uint256 endIndex_) internal returns (Proposal[] memory newArray) {
        newArray = new Proposal[](arrayToCopy_.length);

        for (uint i = startIndex_; i < arrayToCopy_.length;) {
            if (i == endIndex_) break;

            newArray[i] = arrayToCopy_[i];
            
            unchecked {
                ++i;
            }
        }
    }

    function _concatArrays(Proposal[] memory arrayOne, Proposal[] memory arrayTwo) internal returns (Proposal[] memory newArray) {
        // newArray = new Proposal[](arrayOne.length + arrayTwo.length);

        uint i = 0;
        for (; i < arrayOne.length;) {
            newArray[i] = arrayOne[i];
            unchecked {
                ++i;
            }
        }

        for (uint j = 0; j < arrayTwo.length;) {
            newArray[i++] = arrayTwo[j];
            unchecked {
                ++j;
            }
        }
    
    }

    function _storeSubset(Proposal[] memory arrayToStore, bytes32 subsetHash_) internal {

        uint256 subsetLength = arrayToStore.length;

        for (uint i = 0; i < subsetLength;) {
            // storedProposals[i] = arrayToStore[i];
            cachedSubsets[subsetHash_].push(arrayToStore[i]);

            unchecked {
                ++i;
            }
        }
    }

    // https://stackoverflow.com/questions/71819186/what-is-the-best-practice-of-copying-from-array-to-array-in-solidity
    // https://rosettacode.org/wiki/Knapsack_problem/0-1#Python
    // solves the knapsack problem with a recursive dynamic programming algorithm
    function _solveDistribution(Proposal[] memory votedProposals, uint256 budgetConstraint) public returns (Proposal[] memory) {

        // TODO: update this to avoid infinite loop
        // base case
        if (votedProposals.length == 0) return votedProposals;

        // hash proposal array to allow checking against previous subsets
        bytes32 subsetHash = _subsetHash(votedProposals);

        // TODO: handle case of empty array
        // subset not currently cached
        if (cachedSubsets[subsetHash].length == 0) {

            Proposal[] memory head = _copyArray(votedProposals, 0, 1);
            Proposal[] memory tail = _copyArray(votedProposals, 1, votedProposals.length);
            
            // recursively check array subsets
            Proposal[] memory firstOpt = _concatArrays(head, _solveDistribution(tail, budgetConstraint - uint256(head[0].fundingReceived)));
            Proposal[] memory secondOpt = _solveDistribution(tail, budgetConstraint);

            if (_totalValueSubset(firstOpt, budgetConstraint) > _totalValueSubset(secondOpt, budgetConstraint)) {
                _storeSubset(firstOpt, subsetHash);
                return firstOpt;
            }
            else {
                _storeSubset(secondOpt, subsetHash);
                return secondOpt;
            }
        }
        else {
            return cachedSubsets[subsetHash];
        }
    }

    // TODO: update this to check slate is < GBC (MaximumQuarterlyDistribution)
