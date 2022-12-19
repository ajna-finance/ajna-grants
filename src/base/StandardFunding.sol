// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/token/ERC20/IERC20.sol";
import "@oz/utils/Checkpoints.sol";

import "./Funding.sol";

import "../interfaces/IStandardFunding.sol";

import "../libraries/Maths.sol";

abstract contract StandardFunding is Funding, IStandardFunding {

    using Checkpoints for Checkpoints.History;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     * @notice Maximum percentage of tokens that can be distributed by the treasury in a quarter.
     * @dev Stored as a Wad percentage.
     */
    uint256 internal constant globalBudgetConstraint = 20000000000000000;

    /**
     * @notice Length of the distribution period in blocks.
     * @dev    Equivalent to the number of blocks in 90 days. Blocks come every 12 seconds.
     */
    uint256 internal constant DISTRIBUTION_PERIOD_LENGTH = 648000; // 90 days

    /**
     * @notice ID of the current distribution period.
     * @dev Used to access information on the status of an ongoing distribution.
     * @dev Updated at the start of each quarter.
     */
    Checkpoints.History internal _distributionIdCheckpoints;

    /**
     * @notice Mapping of quarterly distributions from the grant fund.
     * @dev distributionId => QuarterlyDistribution
     */
    mapping(uint256 => QuarterlyDistribution) internal distributions;

    /**
     * @dev Mapping of all proposals that have ever been submitted to the grant fund for screening.
     * @dev proposalId => Proposal
     */
    mapping(uint256 => Proposal) internal standardFundingProposals;

    /**
     * @dev Mapping of distributionId to a sorted array of 10 proposalIds with the most votes in the screening period.
     * @dev distribution.id => proposalId[]
     * @dev A new array is created for each distribution period
     */
    mapping(uint256 => uint256[]) internal topTenProposals;

    /**
     * @notice Mapping of quarterly distributions to a hash of a proposal slate to a list of funded proposals.
     * @dev distributionId => slate hash => proposalId[]
     */
    mapping(uint256 => mapping(bytes32 => uint256[])) internal fundedProposalSlates;

    /**
     * @notice Mapping of quarterly distributions to voters to a Quadratic Voter info struct.
     * @dev distributionId => voter address => QuadraticVoter 
     */
    mapping (uint256 => mapping(address => QuadraticVoter)) internal quadraticVoters;

    /**
     * @notice Mapping of distributionId to whether surplus funds from distribution updated into treasury
     * @dev distributionId => bool
    */
    mapping (uint256 => bool) internal isSurplusFundsUpdated;

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    /**
     * @notice Retrieve the current QuarterlyDistribution distributionId.
     */
    function getDistributionId() external view returns (uint256) {
        return _distributionIdCheckpoints.latest();
    }

    /**
     * @notice Calculate the block at which the screening period of a distribution ends.
     * @dev    Screening period is 80 days, funding period is 10 days. Total distribution is 90 days.
     */
    function getScreeningPeriodEndBlock(QuarterlyDistribution memory currentDistribution_) external pure returns (uint256) {
        // 10 days is equivalent to 72,000 blocks (12 seconds per block, 86400 seconds per day)
        return currentDistribution_.endBlock - 72000;
    }

    /**
     * @notice Generate a unique hash of a list of proposals for usage as a key for comparing proposal slates.
     * @param  proposals_ Array of proposals to hash.
     * @return Bytes32 hash of the list of proposals.
     */
    function getSlateHash(Proposal[] calldata proposals_) external pure returns (bytes32) {
        return keccak256(abi.encode(proposals_));
    }

    /**
     * @notice Set a new DistributionPeriod Id.
     * @dev    Increments the previous Id nonce by 1, and sets a checkpoint at the calling block.number.
     * @return newId_ The new distribution period Id.
     */
    function _setNewDistributionId() private returns (uint256 newId_) {
        // retrieve current distribution Id
        uint256 currentDistributionId = _distributionIdCheckpoints.latest();

        // set the current block number as the checkpoint for the current block
        (, newId_) = _distributionIdCheckpoints.push(currentDistributionId + 1);
    }

    /**
     * @notice Updates Treasury with surplus funds from distributions.
     */
    function _updateTreasury() private {

        uint256 currentDistributionId  = _distributionIdCheckpoints.latest();

        // update treasury with surplus funds that are not distributed if current distribution's challenge period is over
        if ( currentDistributionId > 0 ) {
            QuarterlyDistribution memory currentDistribution =  distributions[currentDistributionId];

            if (block.number > currentDistribution.endBlock + 50400) {
                uint256[] memory fundingProposalIds = fundedProposalSlates[currentDistributionId][currentDistribution.fundedSlateHash];
                uint256 totalTokensRequested;
                for (uint i = 0; i < fundingProposalIds.length; ) {
                    Proposal memory proposal = standardFundingProposals[fundingProposalIds[i]];
                    totalTokensRequested += proposal.tokensRequested;
                    unchecked {
                        ++i;
                    }
                }
                treasury += (currentDistribution.fundsAvailable - totalTokensRequested);
                isSurplusFundsUpdated[currentDistributionId] = true;
            }
        }

        // update treasury with surplus funds that are not distributed in previous Distribution 
        if (currentDistributionId > 1 && !isSurplusFundsUpdated[currentDistributionId - 1]) {
            uint256 previousDistributionId = currentDistributionId - 1;
            QuarterlyDistribution memory previousDistribution = distributions[previousDistributionId];
            uint256[] memory fundingProposalIds = fundedProposalSlates[previousDistributionId][previousDistribution.fundedSlateHash];
            uint256 totalTokensRequested;
            for (uint i = 0; i < fundingProposalIds.length; ) {
                Proposal memory proposal = standardFundingProposals[fundingProposalIds[i]];
                totalTokensRequested += proposal.tokensRequested;
                unchecked {
                    ++i;
                }
            }
            treasury += (previousDistribution.fundsAvailable - totalTokensRequested);
            isSurplusFundsUpdated[previousDistributionId] = true; 
        }
    }

    /**
     * @notice Start a new Distribution Period and reset appropriate state.
     * @dev    Can be kicked off by anyone assuming a distribution period isn't already active.
     * @return newDistributionId_ The new distribution period Id.
     */
    function startNewDistributionPeriod() external returns (uint256 newDistributionId_) {
        // check that there isn't currently an active distribution period
        if (block.number <= distributions[_distributionIdCheckpoints.latest()].endBlock) revert DistributionPeriodStillActive();

        // update Treasury with surplus funds from previous distributions 
        _updateTreasury();

        // set the distribution period to start at the current block
        uint256 startBlock = block.number;
        uint256 endBlock = startBlock + DISTRIBUTION_PERIOD_LENGTH;

        // set new value for currentDistributionId
        newDistributionId_ = _setNewDistributionId();

        // create QuarterlyDistribution struct
        QuarterlyDistribution storage newDistributionPeriod = distributions[newDistributionId_];
        newDistributionPeriod.id              = newDistributionId_;
        newDistributionPeriod.startBlock      = startBlock;
        newDistributionPeriod.endBlock        = endBlock;
        uint256 gbc                           = Maths.wmul(treasury, globalBudgetConstraint);  
        newDistributionPeriod.fundsAvailable  = gbc;

        // update treasury
        treasury -= gbc;

        emit QuarterlyDistributionStarted(newDistributionId_, startBlock, endBlock);
    }

    function _sumBudgetAllocated(uint256[] memory proposalIdSubset_) internal view returns (uint256 sum) {
        for (uint i = 0; i < proposalIdSubset_.length;) {
            sum += uint256(standardFundingProposals[proposalIdSubset_[i]].qvBudgetAllocated);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Check if a slate of proposals meets requirements, and maximizes votes. If so, update QuarterlyDistribution.
     * @param  fundedProposals_ Array of proposals to check.
     * @param  distributionId_ Id of the current quarterly distribution.
     * @return Boolean indicating whether the new proposal slate was set as the new top slate for distribution.
     */
    function checkSlate(Proposal[] calldata fundedProposals_, uint256 distributionId_) external returns (bool) {
        QuarterlyDistribution storage currentDistribution = distributions[distributionId_];

        // check that the function is being called within the challenge period
        if (block.number <= currentDistribution.endBlock || block.number > currentDistribution.endBlock + 50400) {
            return false;
        }

        uint256 gbc = currentDistribution.fundsAvailable;
        uint256 sum = 0;
        uint256 totalTokensRequested = 0;

        for (uint i = 0; i < fundedProposals_.length; ) {
            // check if Proposal is in the topTenProposals list
            if (_findProposalIndex(fundedProposals_[i].proposalId, topTenProposals[distributionId_]) == -1) return false;

            // account for qvBudgetAllocated possibly being negative
            if (fundedProposals_[i].qvBudgetAllocated < 0) return false;

            // update counters
            sum += uint256(fundedProposals_[i].qvBudgetAllocated);
            totalTokensRequested += fundedProposals_[i].tokensRequested;

            // check if slate of proposals exceeded budget constraint ( 90% of GBC )
            if (totalTokensRequested > (gbc * 9 / 10)) {
                return false;
            }

            unchecked {
                ++i;
            }
        }

        // get pointers for comparing proposal slates
        bytes32 currentSlateHash = currentDistribution.fundedSlateHash;
        bytes32 newSlateHash = keccak256(abi.encode(fundedProposals_));

        bool newTopSlate = currentSlateHash == 0 ||
            (currentSlateHash!= 0 && sum > _sumBudgetAllocated(fundedProposalSlates[distributionId_][currentSlateHash]));

        if (newTopSlate) {
            uint256[] storage existingSlate = fundedProposalSlates[distributionId_][newSlateHash];
            for (uint i = 0; i < fundedProposals_.length; ) {
                // update list of proposals to fund
                existingSlate.push(fundedProposals_[i].proposalId);

                unchecked {
                    ++i;
                }
            }

            // update hash to point to the new leading slate of proposals
            currentDistribution.fundedSlateHash = newSlateHash;
            emit FundedSlateUpdated(distributionId_, newSlateHash);
        }

        return newTopSlate;
    }

    /**
     * @notice Get the current maximum possible distribution of Ajna tokens that will be released from the treasury this quarter.
     */
    function maximumQuarterlyDistribution() public view returns (uint256) {
        return Maths.wmul(IERC20(ajnaTokenAddress).balanceOf(address(this)), globalBudgetConstraint);
    }

    /**
     * @notice distributes delegate reward based on delegatee Vote share
     * @dev  Can be called by anyone who has voted in both screening and funding period 
     * @param distributionId_ Id of distribution from which delegatee wants to claim his reward
     * @return rewardClaimed_ Amount of reward claimed by delegatee
     */

    function claimDelegateReward(uint256 distributionId_) external returns(uint256 rewardClaimed_) {
        // Revert if delegatee didn't vote in screening stage 
        if(!hasVotedInScreening[distributionId_][msg.sender]) revert DelegateRewardInvalid();

        QuarterlyDistribution memory currentDistribution = distributions[distributionId_];

        if(block.number < currentDistribution.endBlock + 50400) revert ChallengePeriodStillActive();

        QuadraticVoter storage voter = quadraticVoters[distributionId_][msg.sender];

        // Total no of quadratic votes delegatee has voted
        uint256 quadraticVotesUsed = voter.votingWeight - uint256(voter.budgetRemaining);

        uint256 gbc = currentDistribution.fundsAvailable;

        // delegateeReward = 10 % of GBC distributed as per delegatee Vote share    
        rewardClaimed_ = gbc * quadraticVotesUsed / currentDistribution.quadraticVotesCast / 10;

        // prevent multiple claims from delegatee
        voter.budgetRemaining = int256(voter.votingWeight);

        IERC20(ajnaTokenAddress).transfer(msg.sender, rewardClaimed_);
        
        emit DelegateRewardClaimed(msg.sender, distributionId_, rewardClaimed_);
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Execute a proposal that has been approved by the community.
     * @dev    Calls out to Governor.execute()
     * @dev    Check for proposal being succesfully funded or previously executed is handled by Governor.execute().
     * @return proposalId_ of the executed proposal.
     */
    function executeStandard(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) public payable nonReentrant returns (uint256 proposalId_) {
        // check that the distribution period has ended, and one week has passed to enable competing slates to be checked
        if (block.number <= distributions[_distributionIdCheckpoints.latest()].endBlock + 50400) revert ExecuteProposalInvalid();

        proposalId_ = super.execute(targets_, values_, calldatas_, descriptionHash_);
        standardFundingProposals[proposalId_].executed = true;
    }

    /**
     * @notice Submit a new proposal to the Grant Coordination Fund Standard Funding mechanism.
     * @dev    All proposals can be submitted by anyone. There can only be one value in each array. Interface inherits from OZ.propose().
     * @param  targets_ List of contracts the proposal calldata will interact with. Should be the Ajna token contract for all proposals.
     * @param  values_ List of values to be sent with the proposal calldata. Should be 0 for all proposals.
     * @param  calldatas_ List of calldata to be executed. Should be the transfer() method.
     * @return proposalId_ The id of the newly created proposal.
     */
    function proposeStandard(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) public returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, keccak256(bytes(description_)));

        // check for duplicate proposals
        if (standardFundingProposals[proposalId_].proposalId != 0) revert ProposalAlreadyExists();

        QuarterlyDistribution memory currentDistribution = distributions[_distributionIdCheckpoints.latest()];

        // cannot add new proposal after end of screening period
        if (block.number > currentDistribution.endBlock - 72000 ) revert ScreeningPeriodEnded();

        // check params have matching lengths
        if (targets_.length != values_.length || targets_.length != calldatas_.length || targets_.length == 0) revert InvalidProposal();

        // store new proposal information
        Proposal storage newProposal = standardFundingProposals[proposalId_];
        newProposal.proposalId       = proposalId_;
        newProposal.distributionId   = currentDistribution.id;

        // check proposal parameters are valid and update tokensRequested
        newProposal.tokensRequested  = _validateCallDatas(targets_, values_, calldatas_);

        emit ProposalCreated(
            proposalId_,
            msg.sender,
            targets_,
            values_,
            new string[](targets_.length),
            calldatas_,
            block.number,
            distributions[newProposal.distributionId].endBlock,
            description_);
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @notice Vote on a proposal in the funding stage of the Distribution Period.
     * @dev    Votes can be allocated to multiple proposals, quadratically, for or against.
     * @param  proposal_ The current proposal being voted upon.
     * @param  account_  The voting account.
     * @param  voter_    The voter data struct tracking available votes.
     * @param  budgetAllocation_ The amount of votes being allocated to the proposal.
     * @return budgetAllocated_ The amount of votes allocated to the proposal.
     */
    function _fundingVote(Proposal storage proposal_, address account_, QuadraticVoter storage voter_, int256 budgetAllocation_) internal returns (uint256 budgetAllocated_) {

        uint256 currentDistributionId = _distributionIdCheckpoints.latest();
        QuarterlyDistribution storage currentDistribution = distributions[currentDistributionId];

        uint8  support = 1;
        uint256 proposalId = proposal_.proposalId;

        // case where voter is voting against the proposal
        if (budgetAllocation_ < 0) {
            support = 0;

            // update voter budget remaining
            voter_.budgetRemaining += budgetAllocation_;
        }
        // voter is voting in support of the proposal
        else {
            // update voter budget remaining
            voter_.budgetRemaining -= budgetAllocation_;
        }
        // update total vote cast
        currentDistribution.quadraticVotesCast += uint256(Maths.abs(budgetAllocation_));

        // update proposal vote tracking
        proposal_.qvBudgetAllocated += budgetAllocation_;

        // update top ten proposals
        uint256[] memory topTen = topTenProposals[proposal_.distributionId];
        uint256 proposalIndex = uint256(_findProposalIndex(proposalId, topTen));
        standardFundingProposals[topTen[proposalIndex]].qvBudgetAllocated = proposal_.qvBudgetAllocated;

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        budgetAllocated_ = uint256(Maths.abs(budgetAllocation_));
        emit VoteCast(account_, proposalId, support, budgetAllocated_, "");
    }

    /**
     * @notice Vote on a proposal in the screening stage of the Distribution Period.
     * @param account_                The voting account.
     * @param proposal_               The current proposal being voted upon.
     * @param votes_                  The amount of votes being cast.
     * @return                        The amount of votes cast.
     */
    function _screeningVote(address account_, Proposal storage proposal_, uint256 votes_) internal returns (uint256) {
        if (hasVotedInScreening[proposal_.distributionId][account_]) revert AlreadyVoted();

        uint256[] storage currentTopTenProposals = topTenProposals[proposal_.distributionId];

        // update proposal votes counter
        proposal_.votesReceived += votes_;

        // check if proposal was already screened
        int indexInArray = _findProposalIndex(proposal_.proposalId, currentTopTenProposals);
        uint256 screenedProposalsLength = currentTopTenProposals.length;

        // check if the proposal should be added to the top ten list for the first time
        if (screenedProposalsLength < 10 && indexInArray == -1) {
            currentTopTenProposals.push(proposal_.proposalId);
        }
        else {
            // proposal is already in the array
            if (indexInArray != -1) {
                currentTopTenProposals[uint256(indexInArray)] = proposal_.proposalId;

                // sort top ten proposals
                _insertionSortProposalsByVotes(currentTopTenProposals);
            }
            // proposal isn't already in the array
            else if(standardFundingProposals[currentTopTenProposals[screenedProposalsLength - 1]].votesReceived < proposal_.votesReceived) {
                // replace least supported proposal with the new proposal
                currentTopTenProposals.pop();
                currentTopTenProposals.push(proposal_.proposalId);

                // sort top ten proposals
                _insertionSortProposalsByVotes(currentTopTenProposals);
            }
        }

        // record voters vote
        hasVotedInScreening[proposal_.distributionId][account_] = true;

        // vote for the given proposal
        return super._castVote(proposal_.proposalId, account_, 1, "", "");
    }

    /**
     * @notice Check to see if a proposal is in the current funded slate hash of proposals.
     */
    function _standardFundingVoteSucceeded(uint256 proposalId_) internal view returns (bool) {
        uint256 distributionId = _distributionIdCheckpoints.latest();
        return _findProposalIndex(proposalId_, fundedProposalSlates[distributionId][distributions[distributionId].fundedSlateHash]) != -1;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     * @notice Retrieve the QuarterlyDistribution distributionId at a given block.
     */
    function getDistributionIdAtBlock(uint256 blockNumber) external view returns (uint256) {
        return _distributionIdCheckpoints.getAtBlock(blockNumber);
    }

    function getDistributionPeriodInfo(uint256 distributionId_) external view returns (uint256, uint256, uint256, uint256, uint256, bytes32) {
        QuarterlyDistribution memory distribution = distributions[distributionId_];
        return (
            distribution.id,
            distribution.quadraticVotesCast,
            distribution.startBlock,
            distribution.endBlock,
            distribution.fundsAvailable,
            distribution.fundedSlateHash
        );
    }

    /**
     * @notice Get the funded proposal slate for a given distributionId, and slate hash
     */
    function getFundedProposalSlate(uint256 distributionId_, bytes32 slateHash_) external view returns (uint256[] memory) {
        return fundedProposalSlates[distributionId_][slateHash_];
    }

    /**
     * @notice Get the current state of a given proposal.
     */
    function getProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, uint256, int256, bool) {
        Proposal memory proposal = standardFundingProposals[proposalId_];
        return (
            proposal.proposalId,
            proposal.distributionId,
            proposal.votesReceived,
            proposal.tokensRequested,
            proposal.qvBudgetAllocated,
            proposal.executed
        );
    }

    /**
     * @notice Get the current state of a given voter in the funding stage.
     */
    function getVoterInfo(uint256 distributionId_, address account_) external view returns (uint256, int256) {
        QuadraticVoter memory voter = quadraticVoters[distributionId_][account_];
        return (
            voter.votingWeight,
            voter.budgetRemaining
        );
    }

    function getTopTenProposals(uint256 distributionId_) external view returns (uint256[] memory) {
        return topTenProposals[distributionId_];
    }

    /*************************/
    /*** Sorting Functions ***/
    /*************************/

    // return the index of the proposalId in the array, else -1
    function _findProposalIndex(uint256 proposalId, uint256[] memory array) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array

        for (int256 i = 0; i < int256(array.length);) {
            //slither-disable-next-line incorrect-equality
            if (array[uint256(i)] == proposalId) {
                index_ = i;
                break;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sort the 10 proposals which will make it through screening and move on to the funding round.
     * @dev    Implements the descending insertion sort algorithm.
     */
    function _insertionSortProposalsByVotes(uint256[] storage arr) internal {
        for (int i = 1; i < int(arr.length); i++) {
            Proposal memory key = standardFundingProposals[arr[uint(i)]];
            int j = i;

            while (j > 0 && key.votesReceived > standardFundingProposals[arr[uint(j - 1)]].votesReceived) {
                // swap values if left item < right item
                uint256 temp = arr[uint(j - 1)];
                arr[uint(j - 1)] = arr[uint(j)];
                arr[uint(j)] = temp;

                j--;
            }
        }
    }

}
