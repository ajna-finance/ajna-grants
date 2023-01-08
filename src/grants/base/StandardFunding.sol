// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IERC20 }      from "@oz/token/ERC20/IERC20.sol";
import { SafeERC20 }   from "@oz/token/ERC20/utils/SafeERC20.sol";
import { Checkpoints } from "@oz/utils/Checkpoints.sol";

import { Funding } from "./Funding.sol";

import { IStandardFunding } from "../interfaces/IStandardFunding.sol";

import { Maths } from "../libraries/Maths.sol";

abstract contract StandardFunding is Funding, IStandardFunding {

    using Checkpoints for Checkpoints.History;
    using SafeERC20 for IERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     * @notice Maximum percentage of tokens that can be distributed by the treasury in a quarter.
     * @dev Stored as a Wad percentage.
     */
    uint256 internal constant GLOBAL_BUDGET_CONSTRAINT = 0.02 * 1e18;

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
    Checkpoints.History internal distributionIdCheckpoints;

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

    /**
     * @notice Mapping of distributionId to user address to whether user has claimed his delegate reward
     * @dev distributionId => address => bool
    */
    mapping (uint256 => mapping (address => bool)) public hasClaimedReward;

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    /// @inheritdoc IStandardFunding
    function getSlateHash(uint256[] calldata proposalIds_) external pure returns (bytes32) {
        return keccak256(abi.encode(proposalIds_));
    }

    /**
     * @notice Set a new DistributionPeriod Id.
     * @dev    Increments the previous Id nonce by 1, and sets a checkpoint at the calling block.number.
     * @return newId_ The new distribution period Id.
     */
    function _setNewDistributionId() private returns (uint256 newId_) {
        // retrieve current distribution Id
        uint256 currentDistributionId = distributionIdCheckpoints.latest();

        // set the current block number as the checkpoint for the current block
        (, newId_) = distributionIdCheckpoints.push(currentDistributionId + 1);
    }

    /**
     * @notice Updates Treasury with surplus funds from distribution.
     * @param distributionId_ distribution Id of updating distribution 
     */
    function _updateTreasury(uint256 distributionId_) private {
        QuarterlyDistribution memory currentDistribution =  distributions[distributionId_];
        uint256[] memory fundingProposalIds = fundedProposalSlates[distributionId_][currentDistribution.fundedSlateHash];
        uint256 totalTokensRequested;
        for (uint i = 0; i < fundingProposalIds.length; ) {
            Proposal memory proposal = standardFundingProposals[fundingProposalIds[i]];
            totalTokensRequested += proposal.tokensRequested;
            unchecked {
                ++i;
            }
        }
        // update treasury with non distributed tokens
        treasury += (currentDistribution.fundsAvailable - totalTokensRequested);
        isSurplusFundsUpdated[distributionId_] = true;
    }

    /// @inheritdoc IStandardFunding
    function startNewDistributionPeriod() external returns (uint256 newDistributionId_) {
        // check that there isn't currently an active distribution period
        uint256 currentDistributionId = distributionIdCheckpoints.latest();
        if (block.number <= distributions[currentDistributionId].endBlock) revert DistributionPeriodStillActive();

        // update Treasury with unused funds from last two distributions
        {   
            // Check if any last distribution exists and its challenge period is over
            if ( currentDistributionId > 0 && (block.number > distributions[currentDistributionId].endBlock + 50400)) {
                // Add unused funds from last distribution to treasury
                _updateTreasury(currentDistributionId);
            }

            // checks if any second last distribution exist and its unused funds are not added into treasury
            if ( currentDistributionId > 1 && !isSurplusFundsUpdated[currentDistributionId - 1]) {
                // Add unused funds from second last distribution to treasury
                _updateTreasury(currentDistributionId - 1);
            }
        }

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
        uint256 gbc                           = Maths.wmul(treasury, GLOBAL_BUDGET_CONSTRAINT);  
        newDistributionPeriod.fundsAvailable  = gbc;

        // update treasury
        treasury -= gbc;

        emit QuarterlyDistributionStarted(newDistributionId_, startBlock, endBlock);
    }

    /**
     * @notice Calculates the sum of quadratic budgets allocated to a list of proposals.
     * @param  proposalIdSubset_ Array of proposal Ids to sum.
     * @return sum_ The sum of the budget across the given proposals.
     */
    function _sumBudgetAllocated(uint256[] memory proposalIdSubset_) internal view returns (uint256 sum_) {
        for (uint i = 0; i < proposalIdSubset_.length;) {
            sum_ += uint256(standardFundingProposals[proposalIdSubset_[i]].qvBudgetAllocated);

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IStandardFunding
    function checkSlate(uint256[] calldata proposalIds_, uint256 distributionId_) external returns (bool) {
        QuarterlyDistribution storage currentDistribution = distributions[distributionId_];

        // check that the function is being called within the challenge period
        if (block.number <= currentDistribution.endBlock || block.number > currentDistribution.endBlock + 50400) {
            return false;
        }

        uint256 gbc = currentDistribution.fundsAvailable;
        uint256 sum = 0;
        uint256 totalTokensRequested = 0;

        for (uint i = 0; i < proposalIds_.length; ) {
            // check if Proposal is in the topTenProposals list
            if (_findProposalIndex(proposalIds_[i], topTenProposals[distributionId_]) == -1) return false;

            Proposal memory proposal = standardFundingProposals[proposalIds_[i]];

            // account for qvBudgetAllocated possibly being negative
            if (proposal.qvBudgetAllocated < 0) return false;

            // update counters
            sum += uint256(proposal.qvBudgetAllocated);
            totalTokensRequested += proposal.tokensRequested;

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
        bytes32 newSlateHash     = keccak256(abi.encode(proposalIds_));

        // check if slate of proposals is new top slate
        bool newTopSlate = currentSlateHash == 0 ||
            (currentSlateHash!= 0 && sum > _sumBudgetAllocated(fundedProposalSlates[distributionId_][currentSlateHash]));

        if (newTopSlate) {
            uint256[] storage existingSlate = fundedProposalSlates[distributionId_][newSlateHash];
            for (uint i = 0; i < proposalIds_.length; ) {
                // update list of proposals to fund
                existingSlate.push(proposalIds_[i]);

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

    /// @inheritdoc IStandardFunding
    function claimDelegateReward(uint256 distributionId_) external returns(uint256 rewardClaimed_) {
        // Revert if delegatee didn't vote in screening stage 
        if(!hasVotedScreening[distributionId_][msg.sender]) revert DelegateRewardInvalid();

        QuarterlyDistribution memory currentDistribution = distributions[distributionId_];

        // Check if Challenge Period is still active 
        if(block.number < currentDistribution.endBlock + 50400) revert ChallengePeriodNotEnded();

        // check rewards haven't already been claimed
        if(hasClaimedReward[distributionId_][msg.sender]) revert RewardAlreadyClaimed();

        QuadraticVoter memory voter = quadraticVoters[distributionId_][msg.sender];

        // Total number of quadratic votes delegatee has voted
        uint256 quadraticVotesUsed = voter.votingWeight - uint256(voter.budgetRemaining);

        uint256 gbc = currentDistribution.fundsAvailable;

        // delegateeReward = 10 % of GBC distributed as per delegatee Vote share    
        rewardClaimed_ = Maths.wdiv(Maths.wmul(gbc, quadraticVotesUsed), currentDistribution.quadraticVotesCast) / 10;

        emit DelegateRewardClaimed(msg.sender, distributionId_, rewardClaimed_);

        hasClaimedReward[distributionId_][msg.sender] = true;

        // transfer rewards to delegatee
        IERC20(ajnaTokenAddress).safeTransfer(msg.sender, rewardClaimed_);
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /// @inheritdoc IStandardFunding
    function executeStandard(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) external nonReentrant returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, descriptionHash_);
        Proposal memory proposal = standardFundingProposals[proposalId_];

        // check that the distribution period has ended, and one week has passed to enable competing slates to be checked
        if (block.number <= distributions[proposal.distributionId].endBlock + 50400) revert ExecuteProposalInvalid();

        super.execute(targets_, values_, calldatas_, descriptionHash_);
        standardFundingProposals[proposalId_].executed = true;
    }

    /// @inheritdoc IStandardFunding
    function proposeStandard(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) external returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, keccak256(bytes(description_)));

        // check for duplicate proposals
        if (standardFundingProposals[proposalId_].proposalId != 0) revert ProposalAlreadyExists();

        QuarterlyDistribution memory currentDistribution = distributions[distributionIdCheckpoints.latest()];

        // cannot add new proposal after end of screening period
        // screening period ends 72000 blocks before end of distribution period, ~ 80 days.
        if (block.number > currentDistribution.endBlock - 72000) revert ScreeningPeriodEnded();

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

        uint256 currentDistributionId = distributionIdCheckpoints.latest();
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
        if (hasVotedScreening[proposal_.distributionId][account_]) revert AlreadyVoted();

        uint256[] storage currentTopTenProposals = topTenProposals[proposal_.distributionId];

        // update proposal votes counter
        proposal_.votesReceived += votes_;

        // check if proposal was already screened
        int indexInArray = _findProposalIndex(proposal_.proposalId, currentTopTenProposals);
        uint256 screenedProposalsLength = currentTopTenProposals.length;

        // check if the proposal should be added to the top ten list for the first time
        if (screenedProposalsLength < 10 && indexInArray == -1) {
            currentTopTenProposals.push(proposal_.proposalId);

            // sort top ten proposals
            _insertionSortProposalsByVotes(currentTopTenProposals);
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
        hasVotedScreening[proposal_.distributionId][account_] = true;

        // vote for the given proposal
        return super._castVote(proposal_.proposalId, account_, 1, "", "");
    }

    /**
     * @notice Check to see if a proposal is in the current funded slate hash of proposals.
     * @param  proposalId_ The proposalId to check.
     * @return             True if the proposal is in the it's distribution period's slate hash.
     */
    function _standardFundingVoteSucceeded(uint256 proposalId_) internal view returns (bool) {
        Proposal memory proposal = standardFundingProposals[proposalId_];
        uint256 distributionId = proposal.distributionId;
        return _findProposalIndex(proposalId_, fundedProposalSlates[distributionId][distributions[distributionId].fundedSlateHash]) != -1;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /// @inheritdoc IStandardFunding
    function getDistributionIdAtBlock(uint256 blockNumber) external view returns (uint256) {
        return distributionIdCheckpoints.getAtBlock(blockNumber);
    }

    /// @inheritdoc IStandardFunding
    function getDistributionId() external view returns (uint256) {
        return distributionIdCheckpoints.latest();
    }

    /// @inheritdoc IStandardFunding
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

    /// @inheritdoc IStandardFunding
    function getFundedProposalSlate(uint256 distributionId_, bytes32 slateHash_) external view returns (uint256[] memory) {
        return fundedProposalSlates[distributionId_][slateHash_];
    }

    /// @inheritdoc IStandardFunding
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

    /// @inheritdoc IStandardFunding
    function getTopTenProposals(uint256 distributionId_) external view returns (uint256[] memory) {
        return topTenProposals[distributionId_];
    }

    /// @inheritdoc IStandardFunding
    function getVoterInfo(uint256 distributionId_, address account_) external view returns (uint256, int256) {
        QuadraticVoter memory voter = quadraticVoters[distributionId_][account_];
        return (
            voter.votingWeight,
            voter.budgetRemaining
        );
    }

    /// @inheritdoc IStandardFunding
    function maximumQuarterlyDistribution() external view returns (uint256) {
        return Maths.wmul(treasury, GLOBAL_BUDGET_CONSTRAINT);
    }

    /*************************/
    /*** Sorting Functions ***/
    /*************************/

    /**
     * @notice Identify where in an array of proposalIds the proposal exists.
     * @return index_ The index of the proposalId in the array, else -1.
     */
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
