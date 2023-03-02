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
     * @notice Length of the challengephase of the distribution period in blocks.
     * @dev    Roughly equivalent to the number of blocks in 7 days.
     * @dev    The period in which funded proposal slates can be checked in checkSlate.
     */
    uint256 internal constant CHALLENGE_PERIOD_LENGTH = 50400;

    /**
     * @notice Length of the distribution period in blocks.
     * @dev    Roughly equivalent to the number of blocks in 90 days.
     */
    uint256 internal constant DISTRIBUTION_PERIOD_LENGTH = 648000;

    /**
     * @notice Length of the funding phase of the distribution period in blocks.
     * @dev    Roughly equivalent to the number of blocks in 10 days.
     */
    uint256 internal constant FUNDING_PERIOD_LENGTH = 72000;

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
     * @notice Mapping of a hash of a proposal slate to a list of funded proposals.
     * @dev slate hash => proposalId[]
     */
    mapping(bytes32 => uint256[]) internal fundedProposalSlates;

    /**
     * @notice Mapping of quarterly distributions to voters to a Quadratic Voter info struct.
     * @dev distributionId => voter address => QuadraticVoter 
     */
    mapping(uint256 => mapping(address => QuadraticVoter)) internal quadraticVoters;

    /**
     * @notice Mapping of distributionId to whether surplus funds from distribution updated into treasury
     * @dev distributionId => bool
    */
    mapping(uint256 => bool) internal isSurplusFundsUpdated;

    /**
     * @notice Mapping of distributionId to user address to whether user has claimed his delegate reward
     * @dev distributionId => address => bool
    */
    mapping(uint256 => mapping(address => bool)) public hasClaimedReward;

    /**
     * @notice Mapping of distributionId to user address to total votes cast on screening stage proposals.
     * @dev distributionId => address => uint256
    */
    mapping(uint256 => mapping(address => uint256)) public screeningVotesCast;

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    /**
     * @notice Get the block number at which this distribution period's challenge stage ends.
     * @param  endBlock_ The end block of quarterly distribution to get the challenge stage end block for.
     * @return The block number at which this distribution period's challenge stage ends.
    */
    function _getChallengeStageEndBlock(
        uint256 endBlock_
    ) internal pure returns (uint256) {
        return endBlock_ + CHALLENGE_PERIOD_LENGTH;
    }

    /**
     * @notice Get the block number at which this distribution period's screening stage ends.
     * @param  endBlock_ The end block of quarterly distribution to get the screening stage end block for.
     * @return The block number at which this distribution period's screening stage ends.
    */
    function _getScreeningStageEndBlock(
        uint256 endBlock_
    ) internal pure returns (uint256) {
        return endBlock_ - FUNDING_PERIOD_LENGTH;
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
    function _updateTreasury(
        uint256 distributionId_
    ) private {
        QuarterlyDistribution memory currentDistribution =  distributions[distributionId_];

        uint256[] memory fundingProposalIds = fundedProposalSlates[currentDistribution.fundedSlateHash];

        uint256 totalTokensRequested;
        uint256 numFundedProposals = fundingProposalIds.length;

        for (uint i = 0; i < numFundedProposals; ) {
            Proposal memory proposal = standardFundingProposals[fundingProposalIds[i]];

            totalTokensRequested += proposal.tokensRequested;

            unchecked { ++i; }
        }

        // readd non distributed tokens to the treasury
        treasury += (currentDistribution.fundsAvailable - totalTokensRequested);

        isSurplusFundsUpdated[distributionId_] = true;
    }

    /// @inheritdoc IStandardFunding
    function startNewDistributionPeriod() external returns (uint256 newDistributionId_) {
        // check that there isn't currently an active distribution period
        uint256 currentDistributionId = distributionIdCheckpoints.latest();

        QuarterlyDistribution memory currentDistribution = distributions[currentDistributionId];

        if (block.number <= currentDistribution.endBlock) revert DistributionPeriodStillActive();

        // update Treasury with unused funds from last two distributions
        {   
            // Check if any last distribution exists and its challenge stage is over
            if ( currentDistributionId > 0 && (block.number > _getChallengeStageEndBlock(currentDistribution.endBlock))) {
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
        newDistributionPeriod.id              = uint128(newDistributionId_);
        newDistributionPeriod.startBlock      = uint128(startBlock);
        newDistributionPeriod.endBlock        = uint128(endBlock);
        uint256 gbc                           = Maths.wmul(treasury, GLOBAL_BUDGET_CONSTRAINT);  
        newDistributionPeriod.fundsAvailable  = uint128(gbc);

        // decrease the treasury by the amount that is held for allocation in the new distribution period
        treasury -= gbc;

        emit QuarterlyDistributionStarted(
            newDistributionId_,
            startBlock,
            endBlock
        );
    }

    /**
     * @notice Calculates the sum of funding votes allocated to a list of proposals.
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param  proposalIdSubset_ Array of proposal Ids to sum.
     * @return sum_ The sum of the funding votes across the given proposals.
     */
    function _sumProposalFundingVotes(
        uint256[] memory proposalIdSubset_
    ) internal view returns (uint256 sum_) {
        for (uint i = 0; i < proposalIdSubset_.length;) {
            sum_ += uint256(standardFundingProposals[proposalIdSubset_[i]].fundingVotesReceived);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Check an array of proposalIds for duplicate IDs.
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param  proposalIds_ Array of proposal Ids to check.
     * @return Boolean indicating the presence of a duplicate. True if it has a duplicate; false if not.
     */
    function _hasDuplicates(
        uint256[] calldata proposalIds_
    ) internal pure returns (bool) {
        uint256 numProposals = proposalIds_.length;

        for (uint i = 0; i < numProposals; ) {
            for (uint j = i + 1; j < numProposals; ) {
                if (proposalIds_[i] == proposalIds_[j]) return true;

                unchecked { ++j; }

            }

            unchecked { ++i; }

        }
        return false;
    }

    /// @inheritdoc IStandardFunding
    function checkSlate(
        uint256[] calldata proposalIds_,
        uint256 distributionId_
    ) external returns (bool) {
        QuarterlyDistribution storage currentDistribution = distributions[distributionId_];

        uint256 endBlock = currentDistribution.endBlock;

        // check that the function is being called within the challenge period
        if (block.number <= endBlock || block.number > _getChallengeStageEndBlock(endBlock)) {
            return false;
        }

        // check that the slate has no duplicates
        if (_hasDuplicates(proposalIds_)) return false;

        uint256 gbc = currentDistribution.fundsAvailable;
        uint256 sum = 0;
        uint256 totalTokensRequested = 0;
        uint256 numProposalsInSlate = proposalIds_.length;

        // check ways that the potential proposal slate is invalid or worse than existing
        // if worse than existing return false
        for (uint i = 0; i < numProposalsInSlate; ) {

            // check if Proposal is in the topTenProposals list
            if (_findProposalIndex(proposalIds_[i], topTenProposals[distributionId_]) == -1) return false;

            Proposal memory proposal = standardFundingProposals[proposalIds_[i]];

            // account for fundingVotesReceived possibly being negative
            if (proposal.fundingVotesReceived < 0) return false;

            // update counters
            sum += uint256(proposal.fundingVotesReceived);
            totalTokensRequested += proposal.tokensRequested;

            // check if slate of proposals exceeded budget constraint ( 90% of GBC )
            if (totalTokensRequested > (gbc * 9 / 10)) {
                return false;
            }

            unchecked { ++i; }
        }

        // get pointers for comparing proposal slates
        bytes32 currentSlateHash = currentDistribution.fundedSlateHash;
        bytes32 newSlateHash     = keccak256(abi.encode(proposalIds_));

        // check if slate of proposals is new top slate
        bool newTopSlate = currentSlateHash == 0 ||
            (currentSlateHash!= 0 && sum > _sumProposalFundingVotes(fundedProposalSlates[currentSlateHash]));

        // if slate of proposals is new top slate, update state
        if (newTopSlate) {
            uint256[] storage existingSlate = fundedProposalSlates[newSlateHash];

            for (uint i = 0; i < numProposalsInSlate; ) {

                // update list of proposals to fund
                existingSlate.push(proposalIds_[i]);

                unchecked { ++i; }
            }

            // update hash to point to the new leading slate of proposals
            currentDistribution.fundedSlateHash = newSlateHash;

            emit FundedSlateUpdated(
                distributionId_,
                newSlateHash
            );
        }

        return newTopSlate;
    }

    /**
     * @notice Calculate the delegate rewards that have accrued to a given voter, in a given distribution period.
     * @dev    Voter must have voted in both the screening and funding stages, and is proportional to their share of votes across the stages.
     * @param  currentDistribution_ Struct of the distribution period to calculat rewards for.
     * @param  voter_               Struct of the funding stages voter.
     * @return rewards_             The delegate rewards accrued to the voter.
     */
    function _getDelegateReward(
        QuarterlyDistribution memory currentDistribution_,
        QuadraticVoter memory voter_
    ) internal pure returns (uint256 rewards_) {
        // calculate the total voting power available to the voter that was allocated in the funding stage
        uint256 votingPowerAllocatedByDelegatee = voter_.votingPower - voter_.remainingVotingPower;

        // if none of the voter's voting power was allocated, they recieve no rewards
        if (votingPowerAllocatedByDelegatee == 0) return 0;

        // calculate reward
        // delegateeReward = 10 % of GBC distributed as per delegatee Voting power allocated
        rewards_ = Maths.wdiv(
            Maths.wmul(
                currentDistribution_.fundsAvailable,
                votingPowerAllocatedByDelegatee
            ),
            currentDistribution_.fundingVotePowerCast
        ) / 10;
    }

    /// @inheritdoc IStandardFunding
    function claimDelegateReward(
        uint256 distributionId_
    ) external returns(uint256 rewardClaimed_) {
        // Revert if delegatee didn't vote in screening stage 
        if(screeningVotesCast[distributionId_][msg.sender] == 0) revert DelegateRewardInvalid();

        QuarterlyDistribution memory currentDistribution = distributions[distributionId_];

        // Check if Challenge Period is still active 
        if(block.number < _getChallengeStageEndBlock(currentDistribution.endBlock)) revert ChallengePeriodNotEnded();

        // check rewards haven't already been claimed
        if(hasClaimedReward[distributionId_][msg.sender]) revert RewardAlreadyClaimed();

        QuadraticVoter memory voter = quadraticVoters[distributionId_][msg.sender];

        // calculate rewards earned for voting
        rewardClaimed_ = _getDelegateReward(currentDistribution, voter);

        hasClaimedReward[distributionId_][msg.sender] = true;

        emit DelegateRewardClaimed(
            msg.sender,
            distributionId_,
            rewardClaimed_
        );

        // transfer rewards to delegatee
        IERC20(ajnaTokenAddress).safeTransfer(msg.sender, rewardClaimed_);
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /// @inheritdoc IStandardFunding
    function executeStandard(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external nonReentrant returns (uint256 proposalId_) {
        proposalId_ = hashProposal(targets_, values_, calldatas_, descriptionHash_);

        uint256 distributionId = standardFundingProposals[proposalId_].distributionId;

        // check that the distribution period has ended, and one week has passed to enable competing slates to be checked
        if (block.number <= _getChallengeStageEndBlock(distributions[distributionId].endBlock)) revert ExecuteProposalInvalid();

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

        Proposal storage newProposal = standardFundingProposals[proposalId_];

        // check for duplicate proposals
        if (newProposal.proposalId != 0) revert ProposalAlreadyExists();

        QuarterlyDistribution memory currentDistribution = distributions[distributionIdCheckpoints.latest()];

        // cannot add new proposal after end of screening period
        // screening period ends 72000 blocks before end of distribution period, ~ 80 days.
        if (block.number > _getScreeningStageEndBlock(currentDistribution.endBlock)) revert ScreeningPeriodEnded();

        // store new proposal information
        newProposal.proposalId      = proposalId_;
        newProposal.distributionId  = uint120(currentDistribution.id);
        newProposal.tokensRequested = _validateCallDatas(targets_, values_, calldatas_); // check proposal parameters are valid and update tokensRequested

        emit ProposalCreated(
            proposalId_,
            msg.sender,
            targets_,
            values_,
            new string[](targets_.length),
            calldatas_,
            block.number,
            currentDistribution.endBlock,
            description_
        );
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @notice Sum the square of each vote cast by a voter.
     * @dev    Used to calculate if a voter has enough voting power to cast their votes.
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param  votesCast_           The array of votes cast by a voter.
     * @return votesCastSumSquared_ The sum of the square of each vote cast.
     */
    function _sumSquareOfVotesCast(
        FundingVoteParams[] memory votesCast_
    ) internal pure returns (uint256 votesCastSumSquared_) {
        uint256 numVotesCast = votesCast_.length;

        for (uint256 i = 0; i < numVotesCast; ) {
            votesCastSumSquared_ += Maths.wpow(uint256(Maths.abs(votesCast_[i].votesUsed)), 2);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Vote on a proposal in the funding stage of the Distribution Period.
     * @dev    Votes can be allocated to multiple proposals, quadratically, for or against.
     * @param  currentDistribution_  The current distribution period.
     * @param  proposal_             The current proposal being voted upon.
     * @param  account_              The voting account.
     * @param  voter_                The voter data struct tracking available votes.
     * @param  voteParams_           The amount of votes being allocated to the proposal. Not squared. If less than 0, vote is against.
     * @return incrementalVotesUsed_ The amount of funding stage votes allocated to the proposal.
     */
    function _fundingVote(
        QuarterlyDistribution storage currentDistribution_,
        Proposal storage proposal_,
        address account_,
        QuadraticVoter storage voter_,
        FundingVoteParams memory voteParams_
    ) internal returns (uint256 incrementalVotesUsed_) {
        uint8  support = 1;
        uint256 proposalId = proposal_.proposalId;

        // determine if voter is voting for or against the proposal
        voteParams_.votesUsed < 0 ? support = 0 : support = 1;

        uint256 votingPower = voter_.votingPower;

        // the total amount of voting power used by the voter before this vote executes
        uint256 voterPowerUsedPreVote = votingPower - voter_.remainingVotingPower;

        FundingVoteParams[] storage votesCast = voter_.votesCast;

        // check that the voter hasn't already voted on a proposal by seeing if it's already in the votesCast array 
        int256 voteCastIndex = _findProposalIndexOfVotesCast(proposalId, votesCast);

        // voter had already cast a funding vote on this proposal
        if (voteCastIndex != -1) {
            FundingVoteParams storage existingVote = votesCast[uint256(voteCastIndex)];

            // can't change the direction of a previous vote
            if (support == 0 && existingVote.votesUsed > 0 || support == 1 && existingVote.votesUsed < 0) {
                // if the vote is in the opposite direction of a previous vote,
                // and the proposal is already in the votesCast array, revert can't change direction
                revert FundingVoteWrongDirection();
            }
            else {
                // update the votes cast for the proposal
                existingVote.votesUsed += voteParams_.votesUsed;
            }
        }
        // first time voting on this proposal, add the newly cast vote to the voter's votesCast array
        else {
            votesCast.push(voteParams_);
        }

        // calculate the cumulative cost of all votes made by the voter
        uint256 cumulativeVotePowerUsed = _sumSquareOfVotesCast(votesCast);

        // check that the voter has enough voting power remaining to cast the vote
        if (cumulativeVotePowerUsed > votingPower) revert InsufficientVotingPower();

        // update voter voting power accumulator
        voter_.remainingVotingPower = votingPower - cumulativeVotePowerUsed;

        // calculate the change in voting power used by the voter in this vote in order to accurately track the total voting power used in the funding stage
        uint256 incrementalVotingPowerUsed = cumulativeVotePowerUsed - voterPowerUsedPreVote;

        // update accumulator for total voting power used in the funding stage in order to calculate delegate rewards
        currentDistribution_.fundingVotePowerCast += incrementalVotingPowerUsed;

        // update proposal vote tracking
        proposal_.fundingVotesReceived += voteParams_.votesUsed;

        // the incremental additional votes cast on the proposal
        // used as a return value and emit value
        incrementalVotesUsed_ = uint256(Maths.abs(voteParams_.votesUsed));

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        // emits the amount of incremental votes cast for the proposal, not the voting power cost or total votes on a proposal
        emit VoteCast(
            account_,
            proposalId,
            support,
            incrementalVotesUsed_,
            ""
        );
    }

    /**
     * @notice Vote on a proposal in the screening stage of the Distribution Period.
     * @param account_  The voting account.
     * @param proposal_ The current proposal being voted upon.
     * @param votes_    The amount of votes being cast.
     */
    function _screeningVote(
        address account_,
        Proposal storage proposal_,
        uint256 votes_
    ) internal {
        uint256 distributionId = proposal_.distributionId;

        // check that the voter has enough voting power to cast the vote
        if (screeningVotesCast[distributionId][account_] + votes_ > _getVotes(account_, block.number, bytes("Screening"))) revert InsufficientVotingPower();

        uint256[] storage currentTopTenProposals = topTenProposals[distributionId];
        uint256 proposalId = proposal_.proposalId;

        // update proposal votes counter
        proposal_.votesReceived += uint128(votes_);

        // check if proposal was already screened
        int indexInArray = _findProposalIndex(proposalId, currentTopTenProposals);
        uint256 screenedProposalsLength = currentTopTenProposals.length;

        // check if the proposal should be added to the top ten list for the first time
        if (screenedProposalsLength < 10 && indexInArray == -1) {
            currentTopTenProposals.push(proposalId);

            // sort top ten proposals
            _insertionSortProposalsByVotes(currentTopTenProposals);
        }
        else {
            // proposal is already in the array
            if (indexInArray != -1) {
                // re-sort top ten proposals to account for new vote totals
                _insertionSortProposalsByVotes(currentTopTenProposals);
            }
            // proposal isn't already in the array
            else if(standardFundingProposals[currentTopTenProposals[screenedProposalsLength - 1]].votesReceived < proposal_.votesReceived) {
                // replace the least supported proposal with the new proposal
                currentTopTenProposals.pop();
                currentTopTenProposals.push(proposalId);

                // sort top ten proposals
                _insertionSortProposalsByVotes(currentTopTenProposals);
            }
        }

        // record voters vote
        screeningVotesCast[proposal_.distributionId][account_] += votes_;

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        emit VoteCast(
            account_,
            proposalId,
            1,
            votes_,
            ""
        );
    }

    /**
     * @notice Check to see if a proposal is in the current funded slate hash of proposals.
     * @param  proposalId_ The proposalId to check.
     * @return             True if the proposal is in the it's distribution period's slate hash.
     */
    function _standardFundingVoteSucceeded(
        uint256 proposalId_
    ) internal view returns (bool) {
        uint256 distributionId = standardFundingProposals[proposalId_].distributionId;
        return _findProposalIndex(proposalId_, fundedProposalSlates[distributions[distributionId].fundedSlateHash]) != -1;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /// @inheritdoc IStandardFunding
    function getDelegateReward(
        uint256 distributionId_,
        address voter_
    ) external view returns (uint256 rewards_) {
        QuarterlyDistribution memory currentDistribution = distributions[distributionId_];
        QuadraticVoter memory voter = quadraticVoters[distributionId_][voter_];

        rewards_ = _getDelegateReward(currentDistribution, voter);
    }

    /// @inheritdoc IStandardFunding
    function getDistributionIdAtBlock(
        uint256 blockNumber_
    ) external view returns (uint256) {
        return distributionIdCheckpoints.getAtBlock(blockNumber_);
    }

    /// @inheritdoc IStandardFunding
    function getDistributionId() external view returns (uint256) {
        return distributionIdCheckpoints.latest();
    }

    /// @inheritdoc IStandardFunding
    function getDistributionPeriodInfo(
        uint256 distributionId_
    ) external view returns (uint256, uint256, uint256, uint256, uint256, bytes32) {
        return (
            distributions[distributionId_].id,
            distributions[distributionId_].fundingVotePowerCast,
            distributions[distributionId_].startBlock,
            distributions[distributionId_].endBlock,
            distributions[distributionId_].fundsAvailable,
            distributions[distributionId_].fundedSlateHash
        );
    }

    /// @inheritdoc IStandardFunding
    function getFundedProposalSlate(
        bytes32 slateHash_
    ) external view returns (uint256[] memory) {
        return fundedProposalSlates[slateHash_];
    }

    /// @inheritdoc IStandardFunding
    function getFundingPowerVotes(
        uint256 votingPower_
    ) external pure returns (uint256) {
        return Maths.wsqrt(votingPower_);
    }

    /// @inheritdoc IStandardFunding
    function getSlateHash(
        uint256[] calldata proposalIds_
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(proposalIds_));
    }

    /// @inheritdoc IStandardFunding
    function getProposalInfo(
        uint256 proposalId_
    ) external view returns (uint256, uint120, uint128, uint256, int256, bool) {
        return (
            standardFundingProposals[proposalId_].proposalId,
            standardFundingProposals[proposalId_].distributionId,
            standardFundingProposals[proposalId_].votesReceived,
            standardFundingProposals[proposalId_].tokensRequested,
            standardFundingProposals[proposalId_].fundingVotesReceived,
            standardFundingProposals[proposalId_].executed
        );
    }

    /// @inheritdoc IStandardFunding
    function getTopTenProposals(
        uint256 distributionId_
    ) external view returns (uint256[] memory) {
        return topTenProposals[distributionId_];
    }

    /// @inheritdoc IStandardFunding
    function getVoterInfo(
        uint256 distributionId_,
        address account_
    ) external view returns (uint256, uint256, uint256) {
        return (
            quadraticVoters[distributionId_][account_].votingPower,
            quadraticVoters[distributionId_][account_].remainingVotingPower,
            quadraticVoters[distributionId_][account_].votesCast.length
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
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param  proposalId_ The proposalId to search for.
     * @param  array_      The array of proposalIds to search.
     * @return index_      The index of the proposalId in the array, else -1.
     */
    function _findProposalIndex(
        uint256 proposalId_,
        uint256[] memory array_
    ) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array
        int256 arrayLength = int256(array_.length);

        for (int256 i = 0; i < arrayLength;) {
            //slither-disable-next-line incorrect-equality
            if (array_[uint256(i)] == proposalId_) {
                index_ = i;
                break;
            }

            unchecked { ++i; }
        }
    }

    /**
     * @notice Identify where in an array of FundingVoteParams structs the proposal exists.
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param proposalId_ The proposalId to search for.
     * @param voteParams_ The array of FundingVoteParams structs to search.
     * @return index_ The index of the proposalId in the array, else -1.
     */
    function _findProposalIndexOfVotesCast(
        uint256 proposalId_,
        FundingVoteParams[] memory voteParams_
    ) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array

        int256 numVotesCast = int256(voteParams_.length);
        for (int256 i = 0; i < numVotesCast; ) {
            //slither-disable-next-line incorrect-equality
            if (voteParams_[uint256(i)].proposalId == proposalId_) {
                index_ = i;
                break;
            }

            unchecked { ++i; }
        }
    }

    /**
     * @notice Sort the 10 proposals which will make it through screening and move on to the funding round.
     * @dev    Implements the descending insertion sort algorithm.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param arr_ The array of proposals to sort by votes recieved.
     */
    function _insertionSortProposalsByVotes(
        uint256[] storage arr_
    ) internal {
        int256 arrayLength = int256(arr_.length);

        for (int i = 1; i < arrayLength;) {
            Proposal memory key = standardFundingProposals[arr_[uint(i)]];
            int j = i;

            while (j > 0 && key.votesReceived > standardFundingProposals[arr_[uint(j - 1)]].votesReceived) {
                // swap values if left item < right item
                uint256 temp = arr_[uint(j - 1)];
                arr_[uint(j - 1)] = arr_[uint(j)];
                arr_[uint(j)] = temp;

                unchecked { --j; }
            }

            unchecked { ++i; }
        }
    }

}
