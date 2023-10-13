// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { Address }         from "@oz/utils/Address.sol";
import { IERC20 }          from "@oz/token/ERC20/IERC20.sol";
import { IVotes }          from "@oz/governance/utils/IVotes.sol";
import { Math }            from "@oz/utils/math/Math.sol";
import { ReentrancyGuard } from "@oz/security/ReentrancyGuard.sol";
import { SafeCast }        from "@oz/utils/math/SafeCast.sol";
import { SafeERC20 }       from "@oz/token/ERC20/utils/SafeERC20.sol";

import { Storage } from "./base/Storage.sol";

import { IGrantFund }        from "./interfaces/IGrantFund.sol";
import { IGrantFundActions } from "./interfaces/IGrantFundActions.sol";

import { Maths } from "./libraries/Maths.sol";


/**
 *  @title  GrantFund Contract
 *  @notice Entrypoint of GrantFund actions for grant fund actors:
 *          - `Proposers`: Create proposals for transfer of ajna tokens to a list of recipients.
 *          - `Voters`: Vote in the Screening and Funding stages of the distribution period on proposals. Claim delegate rewards if eligible.
 *          - `Slate Updaters`: Submit a list of proposals to be finalized for execution during the Challenge Stage of a distribution period.
 *          - `Distribution Starters`: Calls `startNewDistributionPeriod` to start a new distribution period.
 *          - `Treasury Funders`: Calls `fundTreasury` to fund the treasury with ajna tokens.
 *          - `Executors`: Execute finalized proposals after a distribution period has ended.
 *  @dev    Contract inherits from `Storage` abstract contract to contain state variables.
 *  @dev    Events and proposal function interfaces are compliant with OpenZeppelin Governor.
 *  @dev    Calls logic from internal `Maths` library.
 */
contract GrantFund is IGrantFund, Storage, ReentrancyGuard {

    using SafeERC20 for IERC20;

    /*******************/
    /*** Constructor ***/
    /*******************/

    /**
     *  @notice Deploys the GrantFund contract.
     *  @param ajnaToken_ Address of the token which will be distributed to executed proposals, and eligible delegation rewards claimers.
     */
    constructor(address ajnaToken_) {
        ajnaTokenAddress = ajnaToken_;
    }

    /**************************************************/
    /*** Distribution Management Functions External ***/
    /**************************************************/

    /// @inheritdoc IGrantFundActions
    function startNewDistributionPeriod() external override returns (uint24 newDistributionId_) {
        uint24  currentDistributionId       = _currentDistributionId;
        uint256 currentDistributionEndBlock = _distributions[currentDistributionId].endBlock;

        // check that there isn't currently an active distribution period
        if (block.number <= currentDistributionEndBlock) revert DistributionPeriodStillActive();

        // update Treasury with unused funds from last distribution period
        // checks if any previous distribtuion period exists and its unused funds weren't yet re-added into the treasury
        if (currentDistributionId >= 1 && !_isSurplusFundsUpdated[currentDistributionId]) {
            // Add unused funds to treasury
            _updateTreasury(currentDistributionId);
        }

        // set the distribution period to start at the current block
        uint48 startBlock = SafeCast.toUint48(block.number);
        uint48 endBlock   = startBlock + DISTRIBUTION_PERIOD_LENGTH;

        // set new value for currentDistributionId
        newDistributionId_ = _setNewDistributionId(currentDistributionId);

        // create DistributionPeriod struct
        DistributionPeriod storage newDistributionPeriod = _distributions[newDistributionId_];
        newDistributionPeriod.id              = newDistributionId_;
        newDistributionPeriod.startBlock      = startBlock;
        newDistributionPeriod.endBlock        = endBlock;
        uint256 gbc                           = Maths.wmul(treasury, GLOBAL_BUDGET_CONSTRAINT);
        newDistributionPeriod.fundsAvailable  = SafeCast.toUint128(gbc);

        // decrease the treasury by the amount that is held for allocation in the new distribution period
        treasury -= gbc;

        emit DistributionPeriodStarted(
            newDistributionId_,
            startBlock,
            endBlock
        );
    }

    /// @inheritdoc IGrantFundActions
    function fundTreasury(uint256 fundingAmount_) external override {
        IERC20 token = IERC20(ajnaTokenAddress);

        // update treasury accounting
        uint256 newTreasuryAmount = treasury + fundingAmount_;
        treasury = newTreasuryAmount;

        emit FundTreasury(fundingAmount_, newTreasuryAmount);

        // transfer ajna tokens to the treasury
        token.safeTransferFrom(msg.sender, address(this), fundingAmount_);
    }

    /**************************************************/
    /*** Distribution Management Functions Internal ***/
    /**************************************************/

    /**
     * @notice Get the block number at which this distribution period's challenge stage starts.
     * @param  endBlock_ The end block of a distribution period to get the challenge stage start block for.
     * @return The block number at which this distribution period's challenge stage starts.
    */
    function _getChallengeStageStartBlock(
        uint256 endBlock_
    ) internal pure returns (uint256) {
        return (endBlock_ - CHALLENGE_PERIOD_LENGTH) + 1;
    }

    /**
     * @notice Get the block number at which this distribution period's funding stage ends.
     * @param  startBlock_ The end block of a distribution period to get the funding stage end block for.
     * @return The block number at which this distribution period's funding stage ends.
    */
    function _getFundingStageEndBlock(
        uint256 startBlock_
    ) internal pure returns(uint256) {
        return startBlock_ + SCREENING_PERIOD_LENGTH + FUNDING_PERIOD_LENGTH;
    }

    /**
     * @notice Get the block number at which this distribution period's screening stage ends.
     * @param  startBlock_ The start block of a distribution period to get the screening stage end block for.
     * @return The block number at which this distribution period's screening stage ends.
    */
    function _getScreeningStageEndBlock(
        uint256 startBlock_
    ) internal pure returns (uint256) {
        return startBlock_ + SCREENING_PERIOD_LENGTH;
    }

    /**
     * @notice Updates Treasury with surplus funds from distribution.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length of at most 10.
     * @param distributionId_ distribution Id of updating distribution 
     */
    function _updateTreasury(
        uint24 distributionId_
    ) private {
        DistributionPeriod storage distribution = _distributions[distributionId_];
        bytes32 fundedSlateHash = distribution.fundedSlateHash;
        uint256 fundsAvailable  = distribution.fundsAvailable;

        uint256[] storage fundingProposalIds = _fundedProposalSlates[fundedSlateHash];

        uint256 totalTokenDistributed;
        uint256 numFundedProposals = fundingProposalIds.length;

        for (uint256 i = 0; i < numFundedProposals; ) {

            totalTokenDistributed += _proposals[fundingProposalIds[i]].tokensRequested;

            unchecked { ++i; }
        }

        uint256 totalDelegateRewards;
        // Increment totalDelegateRewards by delegate rewards if anyone has voted during funding voting
        if (_distributions[distributionId_].fundingVotePowerCast != 0) totalDelegateRewards = (fundsAvailable / 10);

        // re-add non distributed tokens to the treasury
        treasury += (fundsAvailable - totalTokenDistributed - totalDelegateRewards);

        _isSurplusFundsUpdated[distributionId_] = true;
    }

    /**
     * @notice Set a new DistributionPeriod Id.
     * @dev    Increments the previous Id nonce by 1.
     * @return newId_ The new distribution period Id.
     */
    function _setNewDistributionId(uint24 currentDistributionId_) private returns (uint24 newId_) {
        newId_ = ++currentDistributionId_;
        _currentDistributionId = newId_;
    }

    /************************************/
    /*** Delegation Rewards Functions ***/
    /************************************/

    /// @inheritdoc IGrantFundActions
    function claimDelegateReward(
        uint24 distributionId_
    ) external override returns (uint256 rewardClaimed_) {
        VoterInfo storage voter = _voterInfo[distributionId_][msg.sender];

        // Revert if delegatee didn't vote in screening stage
        if (voter.screeningVotesCast == 0) revert DelegateRewardInvalid();

        DistributionPeriod storage currentDistribution = _distributions[distributionId_];

        // Check if the distribution period is still active
        if (block.number <= currentDistribution.endBlock) revert DistributionPeriodStillActive();

        // check rewards haven't already been claimed
        if (voter.hasClaimedReward) revert RewardAlreadyClaimed();

        // calculate rewards earned for voting
        rewardClaimed_ = _getDelegateReward(currentDistribution, voter);

        voter.hasClaimedReward = true;

        emit DelegateRewardClaimed(
            msg.sender,
            distributionId_,
            rewardClaimed_
        );

        // transfer rewards to delegatee
        if (rewardClaimed_ != 0) IERC20(ajnaTokenAddress).safeTransfer(msg.sender, rewardClaimed_);
    }

    /**
     * @notice Calculate the delegate rewards that have accrued to a given voter, in a given distribution period.
     * @dev    Voter must have voted in both the screening and funding stages, and is proportional to their share of votes across the stages.
     * @param  currentDistribution_ Struct of the distribution period to calculate rewards for.
     * @param  voter_               Struct of the funding stages voter.
     * @return rewards_             The delegate rewards accrued to the voter.
     */
    function _getDelegateReward(
        DistributionPeriod storage currentDistribution_,
        VoterInfo storage voter_
    ) internal view returns (uint256 rewards_) {
        // calculate the total voting power available to the voter that was allocated in the funding stage
        uint256 votingPowerAllocatedByDelegatee = voter_.fundingVotingPower - voter_.fundingRemainingVotingPower;

        if (votingPowerAllocatedByDelegatee != 0) {
            // take the sqrt of the voting power allocated to compare against the root of all voting power allocated
            // multiply by 1e18 to maintain WAD precision
            uint256 rootVotingPowerAllocatedByDelegatee = Math.sqrt(votingPowerAllocatedByDelegatee * 1e18);

            // calculate reward
            // delegateeReward = 10 % of GBC distributed as per delegatee Voting power allocated
            rewards_ = Math.mulDiv(
                currentDistribution_.fundsAvailable,
                rootVotingPowerAllocatedByDelegatee,
                10 * currentDistribution_.fundingVotePowerCast
            );
        }
    }

    /***********************************/
    /*** Proposal Functions External ***/
    /***********************************/

    /// @inheritdoc IGrantFundActions
    function hashProposal(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external pure override returns (uint256 proposalId_) {
        proposalId_ = _hashProposal(targets_, values_, calldatas_, descriptionHash_);
    }

    /// @inheritdoc IGrantFundActions
    function execute(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external nonReentrant override returns (uint256 proposalId_) {
        proposalId_ = _hashProposal(targets_, values_, calldatas_, descriptionHash_);
        Proposal storage proposal = _proposals[proposalId_];

        uint24 distributionId = proposal.distributionId;

        // check that the distribution period has ended
        if (block.number <= _distributions[distributionId].endBlock) revert ExecuteProposalInvalid();

        // check proposal is successful and hasn't already been executed
        if (!_isProposalFinalized(proposalId_) || proposal.executed) revert ProposalNotSuccessful();

        proposal.executed = true;

        _execute(proposalId_, calldatas_);
    }

    /// @inheritdoc IGrantFundActions
    function propose(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) external override returns (uint256 proposalId_) {
        // check description string isn't empty
        if (bytes(description_).length == 0) revert InvalidProposal();

        proposalId_ = _hashProposal(targets_, values_, calldatas_, _getDescriptionHash(description_));

        Proposal storage newProposal = _proposals[proposalId_];

        // check for duplicate proposals
        if (newProposal.proposalId != 0) revert ProposalAlreadyExists();

        DistributionPeriod storage currentDistribution = _distributions[_currentDistributionId];

        // cannot add new proposal after the screening period ends
        // screening period ends 525_600 blocks after the start of the distribution period, ~73 days.
        if (block.number > _getScreeningStageEndBlock(currentDistribution.startBlock)) revert ScreeningPeriodEnded();

        // store new proposal information
        newProposal.proposalId      = proposalId_;
        newProposal.distributionId  = currentDistribution.id;
        uint128 tokensRequested     = _validateCallDatas(targets_, values_, calldatas_); // check proposal parameters are valid and update tokensRequested
        newProposal.tokensRequested = tokensRequested;

        // revert if proposal requested more tokens than are available in the distribution period
        if (tokensRequested > (currentDistribution.fundsAvailable * 9 / 10)) revert InvalidProposal();

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

    /// @inheritdoc IGrantFundActions
    function state(
        uint256 proposalId_
    ) external view override returns (ProposalState) {
        return _state(proposalId_);
    }

    /// @inheritdoc IGrantFundActions
    function updateSlate(
        uint256[] calldata proposalIds_,
        uint24 distributionId_
    ) external override returns (bool newTopSlate_) {
        DistributionPeriod storage currentDistribution = _distributions[distributionId_];

        // store number of proposals for reduced gas cost of iterations
        uint256 numProposalsInSlate = proposalIds_.length;

        // check the each proposal in the slate is valid, and get the sum of the proposals fundingVotesReceived
        uint256 sum = _validateSlate(
            distributionId_,
            currentDistribution.endBlock,
            currentDistribution.fundsAvailable,
            proposalIds_,
            numProposalsInSlate
        );

        // get pointers for comparing proposal slates
        bytes32 currentSlateHash = currentDistribution.fundedSlateHash;
        bytes32 newSlateHash     = keccak256(abi.encode(proposalIds_));

        // check if slate of proposals is better than the existing slate, and is thus the new top slate
        newTopSlate_ = currentSlateHash == 0 || sum > _sumProposalFundingVotes(_fundedProposalSlates[currentSlateHash]);

        // if slate of proposals is new top slate, update state
        if (newTopSlate_) {
            for (uint256 i = 0; i < numProposalsInSlate; ) {
                // update list of proposals to fund
                _fundedProposalSlates[newSlateHash].push(proposalIds_[i]);

                unchecked { ++i; }
            }

            // update hash to point to the new leading slate of proposals
            currentDistribution.fundedSlateHash = newSlateHash;

            emit FundedSlateUpdated(
                distributionId_,
                newSlateHash
            );
        }
    }

    /***********************************/
    /*** Proposal Functions Internal ***/
    /***********************************/

    /**
     * @notice Execute the calldata of a passed proposal.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param proposalId_ The ID of proposal to execute.
     * @param calldatas_  The list of calldatas to execute.
     */
    function _execute(
        uint256 proposalId_,
        bytes[] memory calldatas_
    ) internal {
        string memory errorMessage = "GF_CALL_NO_MSG";

        uint256 noOfCalldatas = calldatas_.length;
        for (uint256 i = 0; i < noOfCalldatas;) {
            // proposals can only ever target the Ajna token contract, with 0 value
            (bool success, bytes memory returndata) = ajnaTokenAddress.call{value: 0}(calldatas_[i]);
            Address.verifyCallResult(success, returndata, errorMessage);

            unchecked { ++i; }
        }

        // use common event name to maintain consistency with tally
        emit ProposalExecuted(proposalId_);
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

        for (uint256 i = 0; i < numProposals; ) {
            for (uint256 j = i + 1; j < numProposals; ) {
                if (proposalIds_[i] == proposalIds_[j]) return true;

                unchecked { ++j; }
            }

            unchecked { ++i; }

        }
        return false;
    }

    function _getDescriptionHash(
        string memory description_
    ) internal pure returns (bytes32) {
        return keccak256(bytes(description_));
    }

    /**
     * @notice Create a proposalId from a hash of proposal's targets, values, and calldatas arrays, and a description hash.
     * @dev    Consistent with proposalId generation methods used in OpenZeppelin Governor.
     * @param targets_         The addresses of the contracts to call.
     * @param values_          The amounts of ETH to send to each target.
     * @param calldatas_       The calldata to send to each target.
     * @param descriptionHash_ The hash of the proposal's description string. Generated by keccak256(bytes(description))).
     * @return proposalId_     The hashed proposalId created from the provided params.
     */
    function _hashProposal(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) internal pure returns (uint256 proposalId_) {
        proposalId_ = uint256(keccak256(abi.encode(targets_, values_, calldatas_, descriptionHash_)));
    }

    /**
     * @notice Calculates the sum of funding votes allocated to a list of proposals.
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length of at most 10.
     * @param  proposalIdSubset_ Array of proposal Ids to sum.
     * @return sum_ The sum of the funding votes across the given proposals.
     */
    function _sumProposalFundingVotes(
        uint256[] memory proposalIdSubset_
    ) internal view returns (uint128 sum_) {
        uint256 noOfProposals = proposalIdSubset_.length;

        for (uint256 i = 0; i < noOfProposals;) {
            // since we are converting from int128 to uint128, we can safely assume that the value will not overflow
            sum_ += uint128(_proposals[proposalIdSubset_[i]].fundingVotesReceived);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Get the current ProposalState of a given proposal.
     * @dev    Used by GrantFund.state() for analytics compatibility purposes.
     * @param  proposalId_ The ID of the proposal being checked.
     * @return The proposals status in the ProposalState enum.
     */
    function _state(uint256 proposalId_) internal view returns (ProposalState) {
        Proposal memory proposal = _proposals[proposalId_];

        if (proposal.executed)                                                    return ProposalState.Executed;
        else if (_distributions[proposal.distributionId].endBlock > block.number) return ProposalState.Active;
        else if (_isProposalFinalized(proposalId_))                              return ProposalState.Succeeded;
        else                                                                      return ProposalState.Defeated;
    }

    /**
     * @notice Verifies proposal's targets, values, and calldatas match specifications.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param targets_         The addresses of the contracts to call.
     * @param values_          The amounts of ETH to send to each target.
     * @param calldatas_       The calldata to send to each target.
     * @return tokensRequested_ The amount of tokens requested in the calldata.
     */
    function _validateCallDatas(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_
    ) internal view returns (uint128 tokensRequested_) {
        uint256 noOfTargets = targets_.length;

        // check params have matching lengths
        if (
            noOfTargets == 0 || noOfTargets != values_.length || noOfTargets != calldatas_.length
        ) revert InvalidProposal();

        for (uint256 i = 0; i < noOfTargets;) {

            // check targets and values params are valid
            if (targets_[i] != ajnaTokenAddress || values_[i] != 0) revert InvalidProposal();

            // check calldata includes both required params
            if (calldatas_[i].length != 68) revert InvalidProposal();

            // access individual calldata bytes
            bytes memory data = calldatas_[i];

            // retrieve the selector from the calldata
            bytes4 selector;
            // slither-disable-next-line assembly
            assembly {
                selector := mload(add(data, 0x20))
            }
            // check the selector matches transfer(address,uint256)
            if (selector != bytes4(0xa9059cbb)) revert InvalidProposal();

            // https://github.com/ethereum/solidity/issues/9439
            // retrieve recipient and tokensRequested from incoming calldata, accounting for the function selector
            uint256 tokensRequested;
            address recipient;
            // slither-disable-next-line assembly
            assembly {
                recipient := mload(add(data, 36)) // 36 = 4 (selector) + 32 (recipient address)
                tokensRequested := mload(add(data, 68)) // 68 = 4 (selector) + 32 (recipient address) + 32 (tokens requested)
            }

            // check recipient in the calldata is valid and doesn't attempt to transfer tokens to a disallowed address
            if (recipient == address(0) || recipient == ajnaTokenAddress || recipient == address(this)) revert InvalidProposal();

            // update tokens requested for additional calldata
            tokensRequested_ += SafeCast.toUint128(tokensRequested);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Check the validity of a potential slate of proposals to execute, and sum the slate's fundingVotesReceived.
     * @dev    Only iterates through a maximum of 10 proposals that made it through both voting stages.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param  distributionId_                   Id of the distribution period to check the slate for.
     * @param  endBlock                          End block of the distribution period.
     * @param  distributionPeriodFundsAvailable_ Funds available for distribution in the distribution period.
     * @param  proposalIds_                      Array of proposal Ids to check.
     * @param  numProposalsInSlate_              Number of proposals in the slate.
     * @return sum_                              The total funding votes received by all proposals in the proposed slate.
     */
    function _validateSlate(
        uint24 distributionId_,
        uint256 endBlock,
        uint256 distributionPeriodFundsAvailable_,
        uint256[] calldata proposalIds_,
        uint256 numProposalsInSlate_
    ) internal view returns (uint256 sum_) {
        // check that the function is being called within the challenge period,
        // and that there is a proposal in the slate
        if (
            block.number > endBlock ||
            block.number < _getChallengeStageStartBlock(endBlock) ||
            numProposalsInSlate_ == 0
        ) {
            revert InvalidProposalSlate();
        }

        // check that the slate has no duplicates
        if (_hasDuplicates(proposalIds_)) revert InvalidProposalSlate();

        uint256 gbc = distributionPeriodFundsAvailable_;
        uint256 totalTokensRequested = 0;

        // check each proposal in the slate is valid
        for (uint256 i = 0; i < numProposalsInSlate_; ) {
            Proposal storage proposal = _proposals[proposalIds_[i]];

            // check if Proposal is in the topTenProposals list
            if (
                _findProposalIndex(proposalIds_[i], _topTenProposals[distributionId_]) == -1
            ) revert InvalidProposalSlate();

            // account for fundingVotesReceived possibly being negative
            // block proposals that recieve no positive funding votes from entering a finalized slate
            if (proposal.fundingVotesReceived <= 0) revert InvalidProposalSlate();

            // update counters
            // since we are converting from int128 to uint128, we can safely assume that the value will not overflow
            sum_ += uint128(proposal.fundingVotesReceived);
            totalTokensRequested += proposal.tokensRequested;

            unchecked { ++i; }
        }

        // check if slate of proposals exceeded budget constraint ( 90% of GBC )
        if (totalTokensRequested > (gbc * 9 / 10)) revert InvalidProposalSlate();
    }

    /*********************************/
    /*** Voting Functions External ***/
    /*********************************/

    /// @inheritdoc IGrantFundActions
    function fundingVote(
        FundingVoteParams[] calldata voteParams_
    ) external override returns (uint256 votesCast_) {
        uint24 currentDistributionId = _currentDistributionId;

        DistributionPeriod storage currentDistribution = _distributions[currentDistributionId];
        VoterInfo          storage voter               = _voterInfo[currentDistributionId][msg.sender];

        uint256 startBlock = currentDistribution.startBlock;

        uint256 screeningStageEndBlock = _getScreeningStageEndBlock(startBlock);

        // check that the funding stage is active
        if (block.number <= screeningStageEndBlock || block.number > _getFundingStageEndBlock(startBlock)) revert InvalidVote();

        uint128 votingPower = voter.fundingVotingPower;

        // if this is the first time a voter has attempted to vote this period,
        // set initial voting power and remaining voting power
        if (votingPower == 0) {

            // calculate the voting power available to the voting power in this funding stage
            uint128 newVotingPower = SafeCast.toUint128(
                _getVotesFunding(
                    msg.sender,
                    votingPower,
                    voter.fundingRemainingVotingPower,
                    screeningStageEndBlock
                )
            );

            voter.fundingVotingPower          = newVotingPower;
            voter.fundingRemainingVotingPower = newVotingPower;
        }

        uint256 numVotesCast = voteParams_.length;

        for (uint256 i = 0; i < numVotesCast; ) {
            Proposal storage proposal = _proposals[voteParams_[i].proposalId];

            // check that the proposal is part of the current distribution period
            if (proposal.distributionId != currentDistributionId) revert InvalidVote();

            // check that the voter isn't attempting to cast a vote with 0 power
            if (voteParams_[i].votesUsed == 0) revert InvalidVote();

            // check that the proposal being voted on is in the top ten screened proposals
            if (
                _findProposalIndex(voteParams_[i].proposalId, _topTenProposals[currentDistributionId]) == -1
            ) revert InvalidVote();

            // cast each successive vote
            votesCast_ += _fundingVote(
                currentDistribution,
                proposal,
                voter,
                voteParams_[i]
            );

            unchecked { ++i; }
        }
    }

    /// @inheritdoc IGrantFundActions
    function screeningVote(
        ScreeningVoteParams[] calldata voteParams_
    ) external override returns (uint256 votesCast_) {
        uint24 distributionId = _currentDistributionId;
        DistributionPeriod storage currentDistribution = _distributions[distributionId];
        uint256 startBlock = currentDistribution.startBlock;

        // check screening stage is active
        if (
            block.number < startBlock
            ||
            block.number > _getScreeningStageEndBlock(startBlock)
        ) revert InvalidVote();

        uint256 numVotesCast = voteParams_.length;

        VoterInfo storage voter = _voterInfo[distributionId][msg.sender];

        for (uint256 i = 0; i < numVotesCast; ) {
            Proposal storage proposal = _proposals[voteParams_[i].proposalId];

            // check that the proposal is part of the current distribution period
            if (proposal.distributionId != distributionId) revert InvalidVote();

            uint256 votes = voteParams_[i].votes;

            // check that the voter isn't attempting to cast a vote with 0 power
            if (votes == 0) revert InvalidVote();

            // cast each successive vote
            votesCast_ += votes;
            _screeningVote(proposal, voter, votes);

            unchecked { ++i; }
        }
    }

    /*********************************/
    /*** Voting Functions Internal ***/
    /*********************************/

    /**
     * @notice Vote on a proposal in the funding stage of the Distribution Period.
     * @dev    Votes can be allocated to multiple proposals, quadratically, for or against.
     * @param  currentDistribution_  The current distribution period.
     * @param  proposal_             The current proposal being voted upon.
     * @param  voter_                The VoterInfo struct tracking votes.
     * @param  voteParams_           The amount of votes being allocated to the proposal. Not squared. If less than 0, vote is against.
     * @return incrementalVotesUsed_ The amount of funding stage votes allocated to the proposal.
     */
    function _fundingVote(
        DistributionPeriod storage currentDistribution_,
        Proposal storage proposal_,
        VoterInfo storage voter_,
        FundingVoteParams calldata voteParams_
    ) internal returns (uint256 incrementalVotesUsed_) {
        uint8   support = 1;
        uint256 proposalId = proposal_.proposalId;

        // determine if voter is voting for or against the proposal
        voteParams_.votesUsed < 0 ? support = 0 : support = 1;

        uint128 votingPower = voter_.fundingVotingPower;

        // the total amount of voting power used by the voter before this vote executes
        uint128 voterPowerUsedPreVote = votingPower - voter_.fundingRemainingVotingPower;

        FundingVoteParams[] storage votesCast = voter_.votesCast;

        // check that the voter hasn't already voted on a proposal by seeing if it's already in the votesCast array 
        int256 voteCastIndex = _findProposalIndexOfVotesCast(proposalId, votesCast);

        // voter had already cast a funding vote on this proposal
        if (voteCastIndex != -1) {
            // since we are converting from int256 to uint256, we can safely assume that the value will not overflow
            FundingVoteParams storage existingVote = votesCast[uint256(voteCastIndex)];
            int256 votesUsed = existingVote.votesUsed;

            // can't change the direction of a previous vote
            if (
                (support == 0 && votesUsed > 0) || (support == 1 && votesUsed < 0)
            ) {
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
        // and ensure that attempted votes cast doesn't overflow uint128
        uint256 sumOfTheSquareOfVotesCast = _sumSquareOfVotesCast(votesCast);
        uint128 cumulativeVotePowerUsed = SafeCast.toUint128(sumOfTheSquareOfVotesCast);

        // check that the voter has enough voting power remaining to cast the vote
        if (cumulativeVotePowerUsed > votingPower) revert InsufficientRemainingVotingPower();

        // update voter voting power accumulator
        voter_.fundingRemainingVotingPower = votingPower - cumulativeVotePowerUsed;

        // calculate the total sqrt voting power used in the funding stage, in order to calculate delegate rewards.
        // since we are moving from uint128 to uint256, we can safely assume that the value will not overflow.
        // multiply by 1e18 to maintain WAD precision.
        uint256 incrementalRootVotingPowerUsed =
            Math.sqrt(uint256(cumulativeVotePowerUsed) * 1e18) - Math.sqrt(uint256(voterPowerUsedPreVote) * 1e18);

        // update accumulator for total root voting power used in the funding stage in order to calculate delegate rewards
        // check that the voter voted in the screening round before updating the accumulator
        if (voter_.screeningVotesCast != 0) {
            currentDistribution_.fundingVotePowerCast += incrementalRootVotingPowerUsed;
        }

        // update proposal vote tracking
        proposal_.fundingVotesReceived += SafeCast.toInt128(voteParams_.votesUsed);

        // the incremental additional votes cast on the proposal to be used as a return value and emit value
        incrementalVotesUsed_ = Maths.abs(voteParams_.votesUsed);

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        // emits the amount of incremental votes cast for the proposal, not the voting power cost or total votes on a proposal
        emit VoteCast(
            msg.sender,
            proposalId,
            support,
            incrementalVotesUsed_,
            ""
        );
    }

    /**
     * @notice Vote on a proposal in the screening stage of the Distribution Period.
     * @param proposal_ The current proposal being voted upon.
     * @param  voter_   The VoterInfo struct tracking votes.
     * @param votes_    The amount of votes being cast.
     */
    function _screeningVote(
        Proposal storage proposal_,
        VoterInfo storage voter_,
        uint256 votes_
    ) internal {
        uint24 distributionId = proposal_.distributionId;

        // check that the voter has enough voting power to cast the vote
        uint248 pastScreeningVotesCast = voter_.screeningVotesCast;
        if (
            pastScreeningVotesCast + votes_ > _getVotesScreening(distributionId, msg.sender)
        ) revert InsufficientVotingPower();

        uint256[] storage currentTopTenProposals = _topTenProposals[distributionId];
        uint256 proposalId = proposal_.proposalId;

        // update proposal votes counter
        proposal_.votesReceived += SafeCast.toUint128(votes_);

        // check if proposal was already screened
        int256 indexInArray = _findProposalIndex(proposalId, currentTopTenProposals);
        uint256 screenedProposalsLength = currentTopTenProposals.length;

        // check if the proposal should be added to the top ten list for the first time
        if (screenedProposalsLength < 10 && indexInArray == -1) {
            currentTopTenProposals.push(proposalId);

            // sort top ten proposals
            _insertionSortProposalsByVotes(currentTopTenProposals, screenedProposalsLength);
        }
        else {
            // proposal is already in the array
            if (indexInArray != -1) {
                // re-sort top ten proposals to account for new vote totals
                _insertionSortProposalsByVotes(currentTopTenProposals, uint256(indexInArray));
            }
            // proposal isn't already in the array
            else if (_proposals[currentTopTenProposals[screenedProposalsLength - 1]].votesReceived < proposal_.votesReceived) {
                // replace the least supported proposal with the new proposal
                currentTopTenProposals.pop();
                currentTopTenProposals.push(proposalId);

                // sort top ten proposals
                _insertionSortProposalsByVotes(currentTopTenProposals, screenedProposalsLength - 1);
            }
        }

        // record voters vote
        voter_.screeningVotesCast = pastScreeningVotesCast + SafeCast.toUint248(votes_);

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        emit VoteCast(
            msg.sender,
            proposalId,
            1,
            votes_,
            ""
        );
    }

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
        uint256[] storage array_
    ) internal view returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array
        uint256 arrayLength = array_.length;

        for (uint256 i = 0; i < arrayLength;) {
            // slither-disable-next-line incorrect-equality
            if (array_[i] == proposalId_) {
                index_ = int256(i);
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
        FundingVoteParams[] storage voteParams_
    ) internal view returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array

        // since we are converting from uint256 to int256, we can safely assume that the value will not overflow
        uint256 numVotesCast = voteParams_.length;
        for (uint256 i = 0; i < numVotesCast; ) {
            // slither-disable-next-line incorrect-equality
            if (voteParams_[i].proposalId == proposalId_) {
                index_ = int256(i);
                break;
            }

            unchecked { ++i; }
        }
    }

    /**
     * @notice Sort the 10 proposals which will make it through screening and move on to the funding round.
     * @dev    Implements the descending insertion sort algorithm.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @dev    Since we are converting from int256 to uint256, we can safely assume that the values will not overflow.
     * @param proposals_           The array of proposals to sort by votes received.
     * @param targetProposalIndex_ The targeted proposal index to insert in proposals array.
     */
    function _insertionSortProposalsByVotes(
        uint256[] storage proposals_,
        uint256 targetProposalIndex_
    ) internal {
        while (
            targetProposalIndex_ != 0
            &&
            _proposals[proposals_[targetProposalIndex_]].votesReceived > _proposals[proposals_[targetProposalIndex_ - 1]].votesReceived
        ) {
            // swap values if left item < right item
            uint256 temp = proposals_[targetProposalIndex_ - 1];

            proposals_[targetProposalIndex_ - 1] = proposals_[targetProposalIndex_];
            proposals_[targetProposalIndex_] = temp;

            unchecked { --targetProposalIndex_; }
        }
    }

    /**
     * @notice Sum the square of each vote cast by a voter.
     * @dev    Used to calculate if a voter has enough voting power to cast their votes.
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param  votesCast_           The array of votes cast by a voter.
     * @return votesCastSumSquared_ The sum of the square of each vote cast.
     */
    function _sumSquareOfVotesCast(
        FundingVoteParams[] storage votesCast_
    ) internal view returns (uint256 votesCastSumSquared_) {
        uint256 numVotesCast = votesCast_.length;

        for (uint256 i = 0; i < numVotesCast; ) {
            votesCastSumSquared_ += Maths.wpow(Maths.abs(votesCast_[i].votesUsed), 2);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Check to see if a proposal is in it's distribution period's top funded slate of proposals.
     * @param  proposalId_ The proposalId to check.
     * @return             True if the proposal is in the it's distribution period's slate hash.
     */
    function _isProposalFinalized(
        uint256 proposalId_
    ) internal view returns (bool) {
        uint24 distributionId = _proposals[proposalId_].distributionId;
        return _findProposalIndex(proposalId_, _fundedProposalSlates[_distributions[distributionId].fundedSlateHash]) != -1;
    }

    /**
     * @notice Retrieve the number of votes available to an account in the current screening stage.
     * @param  distributionId_ The distribution id to screen votes for.
     * @param  account_        The account to retrieve votes for.
     * @return votes_          The number of votes available to an account in this screening stage.
     */
    function _getVotesScreening(uint24 distributionId_, address account_) internal view returns (uint256 votes_) {
        uint256 startBlock = _distributions[distributionId_].startBlock;
        uint256 snapshotBlock = startBlock - 1;

        // calculate voting weight based on the number of tokens held at the snapshot blocks of the screening stage
        votes_ = _getVotesAtSnapshotBlocks(
            account_,
            snapshotBlock - VOTING_POWER_SNAPSHOT_DELAY,
            snapshotBlock
        );
    }

    /**
     * @notice Retrieve the number of votes available to an account in the current funding stage.
     * @param  account_                The address of the voter to check.
     * @param  votingPower_            The voter's voting power in the funding round. Equal to the square of their tokens in the voting snapshot.
     * @param  remainingVotingPower_   The voter's remaining quadratic voting power in the given distribution period's funding round.
     * @param  screeningStageEndBlock_ The block number at which the screening stage ends.
     * @return votes_                  The number of votes available to an account in this funding stage.
     */
    function _getVotesFunding(
        address account_,
        uint256 votingPower_,
        uint256 remainingVotingPower_,
        uint256 screeningStageEndBlock_
    ) internal view returns (uint256 votes_) {
        // voter has already allocated some of their budget this period
        if (votingPower_ != 0) {
            votes_ = remainingVotingPower_;
        }
        // voter hasn't yet called _castVote in this period
        else {
            uint256 fundingStageStartBlock = screeningStageEndBlock_;
            votes_ = Maths.wpow(
                _getVotesAtSnapshotBlocks(
                    account_,
                    fundingStageStartBlock - VOTING_POWER_SNAPSHOT_DELAY,
                    fundingStageStartBlock
                ),
                2
            );
        }
    }

     /**
     * @notice Retrieve the voting power of an account.
     * @dev    Voting power is the minimum of the amount of votes available at two snapshots:
     *         a snapshot 34 blocks prior to voting start, and the second snapshot the block before the distribution period starts.
     * @param account_        The voting account.
     * @param snapshot_       One of the block numbers to retrieve the voting power at. 34 blocks prior to the block at which a proposal is available for voting.
     * @param voteStartBlock_ The block number the proposal became available for voting.
     * @return                The voting power of the account.
     */
    function _getVotesAtSnapshotBlocks(
        address account_,
        uint256 snapshot_,
        uint256 voteStartBlock_
    ) internal view returns (uint256) {
        IVotes token = IVotes(ajnaTokenAddress);

        // calculate the number of votes available at the first snapshot block
        uint256 votes1 = token.getPastVotes(account_, snapshot_);

        // calculate the number of votes available at the second snapshot occuring the block before the stage's start block
        uint256 votes2 = token.getPastVotes(account_, voteStartBlock_);

        return Maths.min(votes2, votes1);
    }

    /*******************************/
    /*** External View Functions ***/
    /*******************************/

    /// @inheritdoc IGrantFundActions
    function getChallengeStageStartBlock(uint256 endBlock_) external pure override returns (uint256) {
        return _getChallengeStageStartBlock(endBlock_);
    }

    /// @inheritdoc IGrantFundActions
    function getDescriptionHash(
        string memory description_
    ) external pure override returns (bytes32) {
        return _getDescriptionHash(description_);
    }

    /// @inheritdoc IGrantFundActions
    function getDelegateReward(
        uint24 distributionId_,
        address voter_
    ) external view override returns (uint256 rewards_) {
        DistributionPeriod storage currentDistribution = _distributions[distributionId_];
        VoterInfo          storage voter               = _voterInfo[distributionId_][voter_];

        if (voter.screeningVotesCast == 0) return 0;

        rewards_ = _getDelegateReward(currentDistribution, voter);
    }

    /// @inheritdoc IGrantFundActions
    function getDistributionId() external view override returns (uint24) {
        return _currentDistributionId;
    }

    /// @inheritdoc IGrantFundActions
    function getDistributionPeriodInfo(
        uint24 distributionId_
    ) external view override returns (uint24, uint48, uint48, uint128, uint256, bytes32) {
        return (
            _distributions[distributionId_].id,
            _distributions[distributionId_].startBlock,
            _distributions[distributionId_].endBlock,
            _distributions[distributionId_].fundsAvailable,
            _distributions[distributionId_].fundingVotePowerCast,
            _distributions[distributionId_].fundedSlateHash
        );
    }

    /// @inheritdoc IGrantFundActions
    function getFundedProposalSlate(
        bytes32 slateHash_
    ) external view override returns (uint256[] memory) {
        return _fundedProposalSlates[slateHash_];
    }

    /// @inheritdoc IGrantFundActions
    function getFundingStageEndBlock(uint256 startBlock_) external pure override returns (uint256) {
        return _getFundingStageEndBlock(startBlock_);
    }

    /// @inheritdoc IGrantFundActions
    function getFundingVotesCast(
        uint24 distributionId_,
        address account_
    ) external view override returns (FundingVoteParams[] memory) {
        return _voterInfo[distributionId_][account_].votesCast;
    }

    /// @inheritdoc IGrantFundActions
    function getHasClaimedRewards(uint256 distributionId_, address account_) external view override returns (bool) {
        return _voterInfo[distributionId_][account_].hasClaimedReward;
    }

    /// @inheritdoc IGrantFundActions
    function getProposalInfo(
        uint256 proposalId_
    ) external view override returns (uint256, uint24, uint128, uint128, int128, bool) {
        return (
            _proposals[proposalId_].proposalId,
            _proposals[proposalId_].distributionId,
            _proposals[proposalId_].votesReceived,
            _proposals[proposalId_].tokensRequested,
            _proposals[proposalId_].fundingVotesReceived,
            _proposals[proposalId_].executed
        );
    }

    /// @inheritdoc IGrantFundActions
    function getScreeningStageEndBlock(uint256 startBlock_) external pure override returns (uint256) {
        return _getScreeningStageEndBlock(startBlock_);
    }

    /// @inheritdoc IGrantFundActions
    function getScreeningVotesCast(uint256 distributionId_, address account_) external view override returns (uint256) {
        return _voterInfo[distributionId_][account_].screeningVotesCast;
    }

    /// @inheritdoc IGrantFundActions
    function getSlateHash(
        uint256[] calldata proposalIds_
    ) external pure override returns (bytes32) {
        return keccak256(abi.encode(proposalIds_));
    }

    /// @inheritdoc IGrantFundActions
    function getStage() external view returns (bytes32 stage_) {
        DistributionPeriod memory currentDistribution = _distributions[_currentDistributionId];
        uint256 startBlock = currentDistribution.startBlock;
        uint256 endBlock = currentDistribution.endBlock;
        uint256 screeningStageEndBlock = _getScreeningStageEndBlock(startBlock);
        uint256 fundingStageEndBlock = _getFundingStageEndBlock(startBlock);

        if (block.number <= screeningStageEndBlock) {
            stage_ = keccak256(bytes("Screening"));
        }
        else if (block.number > screeningStageEndBlock && block.number <= fundingStageEndBlock) {
            stage_ = keccak256(bytes("Funding"));
        }
        else if (block.number > fundingStageEndBlock && block.number <= endBlock) {
            stage_ = keccak256(bytes("Challenge"));
        }
        else {
            // a new distribution period needs to be started
            stage_ = keccak256(bytes("Pending"));
        }
    }

    /// @inheritdoc IGrantFundActions
    function getTopTenProposals(
        uint24 distributionId_
    ) external view override returns (uint256[] memory) {
        return _topTenProposals[distributionId_];
    }

    /// @inheritdoc IGrantFundActions
    function getVoterInfo(
        uint24 distributionId_,
        address account_
    ) external view override returns (uint128, uint128, uint256) {
        return (
            _voterInfo[distributionId_][account_].fundingVotingPower,
            _voterInfo[distributionId_][account_].fundingRemainingVotingPower,
            _voterInfo[distributionId_][account_].votesCast.length
        );
    }

    /// @inheritdoc IGrantFundActions
    function getVotesFunding(
        uint24 distributionId_,
        address account_
    ) external view override returns (uint256 votes_) {
        DistributionPeriod memory currentDistribution = _distributions[distributionId_];
        VoterInfo          memory voter               = _voterInfo[distributionId_][account_];

        uint256 screeningStageEndBlock = _getScreeningStageEndBlock(currentDistribution.startBlock);

        votes_ = _getVotesFunding(account_, voter.fundingVotingPower, voter.fundingRemainingVotingPower, screeningStageEndBlock);
    }

    /// @inheritdoc IGrantFundActions
    function getVotesScreening(
        uint24 distributionId_,
        address account_
    ) external view override returns (uint256 votes_) {
        votes_ = _getVotesScreening(distributionId_, account_);
    }

}
