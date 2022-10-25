// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/governance/Governor.sol";
import "@oz/governance/extensions/GovernorVotes.sol";
import "@oz/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@oz/governance/IGovernor.sol";
import "@oz/governance/utils/IVotes.sol";
import "@oz/security/ReentrancyGuard.sol";
import "@oz/utils/Checkpoints.sol";

import "./libraries/Maths.sol";

import "./interfaces/IGrowthFund.sol";

import "./AjnaToken.sol";


contract GrowthFund is IGrowthFund, Governor, GovernorVotesQuorumFraction, ReentrancyGuard {

    using Checkpoints for Checkpoints.History;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 internal extraordinaryFundingBaseQuorum;

    address public   votingTokenAddress;
    AjnaToken  internal ajnaToken;

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
    Checkpoints.History private _distributionIdCheckpoints;

    /**
     * @notice Mapping of quarterly distributions from the growth fund.
     * @dev distributionId => QuarterlyDistribution
     */
    mapping(uint256 => QuarterlyDistribution) distributions;

    /**
     * @notice Mapping checking if a voter has voted on a proposal during the screening stage in a quarter.
     * @dev Reset to false at the start of each new quarter.
     */
    mapping(address => bool) hasScreened;

    /**
     * @dev Mapping of all proposals that have ever been submitted to the growth fund for screening.
     * @dev distribution.id => proposalId => Proposal
     */
    mapping(uint256 => Proposal) proposals;

    /**
     * @dev Mapping of distributionId to a sorted array of 10 proposals with the most votes in the screening period.
     * @dev distribution.id => Proposal[]
     * @dev A new array is created for each distribution period
     */
    mapping(uint256 => Proposal[]) topTenProposals;

    /**
     * @notice Mapping of quarterly distributions to a hash of a proposal slate to a list of funded proposals.
     * @dev distributionId => slate hash => Proposal[]
     */
    mapping(uint256 => mapping(bytes32 => Proposal[])) fundedProposalSlates;

    /**
     * @notice Mapping of quarterly distributions to voters to a Quadratic Voter info struct.
     * @dev distributionId => voter address => QuadraticVoter 
     */
    mapping (uint256 => mapping(address => QuadraticVoter)) quadraticVoters;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    /**
     * @notice Ensure a proposal matches GrowthFund specifications.
     * @dev Targets_ should be the Ajna token contract, values_ should be 0, and calldatas_ should be transfer().
     * @param targets_   List of contract addresses the proposal interacts with.
     * @param values_    List of wei amounts to call the target address with.
     * @param calldatas_ List of calldatas to execute if the proposal is successful.
     */
    modifier checkProposal(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_) {
        // check proposal can only execute one calldata, with one target
        if (targets_.length != 1 || values_.length != 1 || calldatas_.length != 1) {
            revert InvalidProposal();
        }

        if (targets_[0] != votingTokenAddress) revert InvalidTarget();
        if (values_[0] != 0) revert InvalidValues();

        // check calldata function selector is transfer()
        bytes memory dataWithSig = calldatas_[0];
        bytes4 selector;
        //slither-disable-next-line assembly
        assembly {
            selector := mload(add(dataWithSig, 0x20))
        }
        if (selector != bytes4(0xa9059cbb)) revert InvalidSignature();
        _;
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(IVotes token_)
        Governor("AjnaEcosystemGrowthFund")
        GovernorVotes(token_) // token that will be used for voting
        GovernorVotesQuorumFraction(4) // percentage of total voting power required; updateable via governance proposal
    {
        extraordinaryFundingBaseQuorum = 50; // initialize base quorum percentrage required for extraordinary funding to 50%

        votingTokenAddress = address(token_);
        ajnaToken          = AjnaToken(address(token_));
    }

    /*****************************************/
    /*** Distribution Management Functions ***/
    /*****************************************/

    /**
     * @notice Retrieve the current QuarterlyDistribution distributionId.
     */
    function getDistributionId() public view returns (uint256) {
        return _distributionIdCheckpoints.latest();
    }

    /**
     * @notice Calculate the block at which the screening period of a distribution ends.
     * @dev    Screening period is 80 days, funding period is 10 days. Total distribution is 90 days.
     */
    function getScreeningPeriodEndBlock(QuarterlyDistribution memory currentDistribution_) public pure returns (uint256) {
        // 10 days is equivalent to 72,000 blocks (12 seconds per block, 86400 seconds per day)
        return currentDistribution_.endBlock - 72000;
    }

    /**
     * @notice Generate a unique hash of a list of proposals for usage as a key for comparing proposal slates.
     * @param  proposals_ Array of proposals to hash.
     * @return Bytes32 hash of the list of proposals.
     */
    function getSlateHash(Proposal[] calldata proposals_) public pure returns (bytes32) {
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
     * @notice Start a new Distribution Period and reset appropriate state.
     * @dev    Can be kicked off by anyone assuming a distribution period isn't already active.
     * @return newDistributionId_ The new distribution period Id.
     */
    function startNewDistributionPeriod() external returns (uint256 newDistributionId_) {
        QuarterlyDistribution memory lastDistribution = distributions[getDistributionId()];

        // check that there isn't currently an active distribution period
        if (block.number <= lastDistribution.endBlock) revert DistributionPeriodStillActive();

        // set the distribution period to start at the current block
        uint256 startBlock = block.number;
        uint256 endBlock = startBlock + DISTRIBUTION_PERIOD_LENGTH;

        // set new value for currentDistributionId
        newDistributionId_ = _setNewDistributionId();

        // create QuarterlyDistribution struct
        QuarterlyDistribution storage newDistributionPeriod = distributions[newDistributionId_];
        newDistributionPeriod.id = newDistributionId_;
        newDistributionPeriod.startBlock = startBlock;
        newDistributionPeriod.endBlock = endBlock;

        emit QuarterlyDistributionStarted(newDistributionId_, startBlock, endBlock);
    }

    function _sumBudgetAllocated(Proposal[] memory proposalSubset_) internal pure returns (uint256 sum) {
        sum = 0;
        for (uint i = 0; i < proposalSubset_.length;) {
            sum += uint256(proposalSubset_[i].qvBudgetAllocated);

            unchecked {
                ++i;
            }
        }
    }

    function _updateFundedSlate(Proposal[] calldata fundedProposals_, QuarterlyDistribution storage currentDistribution_, bytes32 slateHash_) internal {
        for (uint i = 0; i < fundedProposals_.length; ) {

            // update list of proposals to fund
            fundedProposalSlates[currentDistribution_.id][slateHash_].push(fundedProposals_[i]);

            unchecked {
                ++i;
            }
        }

        // update hash to point to the new leading slate of proposals
        currentDistribution_.fundedSlateHash = slateHash_;
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

        uint256 gbc = maximumQuarterlyDistribution();
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

            // check if slate of proposals exceeded budget constraint
            if (totalTokensRequested > gbc) {
                return false;
            }

            unchecked {
                ++i;
            }
        }

        // get pointers for comparing proposal slates
        bytes32 currentSlateHash = currentDistribution.fundedSlateHash;
        bytes32 newSlateHash = getSlateHash(fundedProposals_);

        // check if current slate received more support than the current leading slate
        if (currentSlateHash != 0) {
            if (sum > _sumBudgetAllocated(fundedProposalSlates[distributionId_][currentSlateHash])) {

                _updateFundedSlate(fundedProposals_, currentDistribution, newSlateHash);
                return true;
            }
        }
        // set as first slate of funded proposals
        else {
            _updateFundedSlate(fundedProposals_, currentDistribution, newSlateHash);
            return true;
        }

        return false;
    }

    /**
     * @notice Get the current maximum possible distribution of Ajna tokens that will be released from the treasury this quarter.
     */
    function maximumQuarterlyDistribution() public view returns (uint256) {
        uint256 growthFundBalance = ajnaToken.balanceOf(address(this));
        return Maths.wmul(growthFundBalance, globalBudgetConstraint);
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Submit a new proposal to the Growth Coordination Fund
     * @dev    All proposals can be submitted by anyone. There can only be one value in each array. Interface inherits from OZ.propose().
     * @param  targets_ List of contracts the proposal calldata will interact with. Should be the Ajna token contract for all proposals.
     * @param  values_ List of values to be sent with the proposal calldata. Should be 0 for all proposals.
     * @param  calldatas_ List of calldata to be executed. Should be the transfer() method.
     * @return proposalId The id of the newly created proposal.
     */
    function propose(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) public override(Governor) checkProposal(targets_, values_, calldatas_) returns (uint256) {
        uint256 proposalId = hashProposal(targets_, values_, calldatas_, keccak256(bytes(description_)));

        // https://github.com/ethereum/solidity/issues/9439
        // retrieve tokensRequested from incoming calldata, accounting for selector and recipient address
        bytes memory dataWithSig = calldatas_[0];
        uint256 tokensRequested;

        //slither-disable-next-line assembly
        assembly {
            tokensRequested := mload(add(dataWithSig, 68))
        }

        // store new proposal information
        Proposal storage newProposal = proposals[proposalId];
        newProposal.proposalId = proposalId;
        newProposal.distributionId = _distributionIdCheckpoints.latest();
        newProposal.tokensRequested = tokensRequested;

        return super.propose(targets_, values_, calldatas_, description_);
    }

    /**
     * @notice Execute a proposal that has been approved by the community.
     * @dev    Calls out to Governor.execute()
     * @return proposalId of the executed proposal.
     */
    function execute(address[] memory targets_, uint256[] memory values_, bytes[] memory calldatas_, bytes32 descriptionHash_) public payable override(Governor) nonReentrant returns (uint256) {
        uint256 proposalId = hashProposal(targets_, values_, calldatas_, descriptionHash_);
        Proposal storage proposal = proposals[proposalId];

        // check if propsal is in the fundedProposalSlates list
        if (_findProposalIndex(proposalId, fundedProposalSlates[proposal.distributionId][distributions[proposal.distributionId].fundedSlateHash]) == -1) {
            revert ProposalNotFunded();
        }

        // check that the distribution period has ended, and it hasn't already been executed
        if (block.number <= distributions[proposal.distributionId].endBlock + 50400 || proposals[proposalId].executed) revert ExecuteProposalInvalid();

        // update proposal state
        proposal.succeeded = true;
        proposal.executed = true;

        super.execute(targets_, values_, calldatas_, descriptionHash_);
        return proposalId;
    }

    /**
     * @dev Required override; we don't currently have a threshold to create a proposal so this returns the default value of 0
     */
    function proposalThreshold() public view override(Governor) returns (uint256) {
        return super.proposalThreshold();
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    // TODO: may want to replace the conditional checks of stage here with the DistributionPhase enum
    /**
     * @notice Vote on a proposal in the screening or funding stage of the Distribution Period.
     * @dev Override channels all other castVote methods through here.
     * @param proposalId_ The current proposal being voted upon.
     * @param account_    The voting account.
     * @param params_     The amount of votes being allocated in the funding stage.
     */
     function _castVote(uint256 proposalId_, address account_, uint8, string memory, bytes memory params_) internal override(Governor) returns (uint256) {
        Proposal storage proposal = proposals[proposalId_];
        QuarterlyDistribution memory currentDistribution = distributions[proposal.distributionId];

        uint256 screeningPeriodEndBlock = getScreeningPeriodEndBlock(currentDistribution);
        bytes memory stage;
        uint256 votes;

        // screening stage
        if (block.number >= currentDistribution.startBlock && block.number <= screeningPeriodEndBlock) {
            Proposal[] storage currentTopTenProposals = topTenProposals[proposal.distributionId];
            stage = bytes("Screening");
            votes = _getVotes(account_, block.number, stage);

            return _screeningVote(currentTopTenProposals, account_, proposal, votes);
        }

        // funding stage
        else if (block.number > screeningPeriodEndBlock && block.number <= currentDistribution.endBlock) {
            stage = bytes("Funding");

            QuadraticVoter storage voter = quadraticVoters[currentDistribution.id][account_];

            // this is the first time a voter has attempted to vote this period
            if (voter.votingWeight == 0) {
                voter.votingWeight = Maths.wpow(super._getVotes(account_, getScreeningPeriodEndBlock(currentDistribution) - 33, ""), 2);
                voter.budgetRemaining = int256(voter.votingWeight);
            }

            // amount of quadratic budget to allocated to the proposal
            int256 budgetAllocation = abi.decode(params_, (int256));

            // check if the voter has enough budget remaining to allocate to the proposal
            if (voter.budgetRemaining == 0 || budgetAllocation > voter.budgetRemaining) revert InsufficientBudget();

            return _fundingVote(proposal, account_, voter, budgetAllocation);
        }

        // TODO: implement extraordinary funding mechanism pathway
    }

    /**
     * @notice Vote on a proposal in the funding stage of the Distribution Period.
     * @dev    Votes can be allocated to multiple proposals, quadratically, for or against.
     * @param  proposal_ The current proposal being voted upon.
     * @param  account_  The voting account.
     * @param  voter_    The voter data struct tracking available votes.
     * @param  budgetAllocation_ The amount of votes being allocated to the proposal.
     * @return The amount of votes allocated to the proposal.
     */
    function _fundingVote(Proposal storage proposal_, address account_, QuadraticVoter storage voter_, int256 budgetAllocation_) internal returns (uint256) {
        int256 allocationUsed = 0;
        uint8  support = 1;

        // case where voter is voting against the proposal
        if (budgetAllocation_ < 0) {
            allocationUsed -= budgetAllocation_;
            support = 0;

            // update voter and proposal vote tracking
            voter_.budgetRemaining -= allocationUsed;
            proposal_.qvBudgetAllocated -= allocationUsed;
        }
        // voter is voting in support of the proposal
        else {
            allocationUsed = budgetAllocation_;

            // update voter and proposal vote tracking
            voter_.budgetRemaining -= allocationUsed;
            proposal_.qvBudgetAllocated += allocationUsed;
        }

        // update proposal vote tracking in top ten array
        topTenProposals[proposal_.distributionId][uint256(_findProposalIndex(proposal_.proposalId, topTenProposals[proposal_.distributionId]))].qvBudgetAllocated = proposal_.qvBudgetAllocated;

        // emit VoteCast instead of VoteCastWithParams to maintain compatibility with Tally
        emit VoteCast(account_, proposal_.proposalId, support, uint256(allocationUsed), "");
        return uint256(allocationUsed);
    }

    /**
     * @notice Vote on a proposal in the screening stage of the Distribution Period.
     * @param currentTopTenProposals_ List of top ten vote receiving proposals that made it through the screening round.
     * @param account_                The voting account.
     * @param proposal_               The current proposal being voted upon.
     * @param votes_                  The amount of votes being cast.
     * @return                        The amount of votes cast.
     */
    function _screeningVote(Proposal[] storage currentTopTenProposals_, address account_, Proposal storage proposal_, uint256 votes_) internal returns (uint256) {
        if (hasScreened[account_]) revert AlreadyVoted();

        // update proposal votes counter
        proposal_.votesReceived += votes_;

        // check if proposal was already screened
        int indexInArray = _findProposalIndex(proposal_.proposalId, currentTopTenProposals_);
        uint256 screenedProposalsLength = currentTopTenProposals_.length;

        // check if the proposal should be added to the top ten list for the first time
        if (screenedProposalsLength < 10 && indexInArray == -1) {
            currentTopTenProposals_.push(proposal_);
        }
        else {
            // proposal is already in the array
            if (indexInArray != -1) {
                currentTopTenProposals_[uint256(indexInArray)] = proposal_;

                // sort top ten proposals
                _insertionSortProposalsByVotes(currentTopTenProposals_);
            }
            // proposal isn't already in the array
            else if(currentTopTenProposals_[screenedProposalsLength - 1].votesReceived < proposal_.votesReceived) {
                // replace least supported proposal with the new proposal
                currentTopTenProposals_.pop();
                currentTopTenProposals_.push(proposal_);

                // sort top ten proposals
                _insertionSortProposalsByVotes(currentTopTenProposals_);
            }
        }

        // ensure proposal list is within expected bounds
        require(topTenProposals[proposal_.distributionId].length <= 10 && topTenProposals[proposal_.distributionId].length > 0, "CV:LIST_MALFORMED");

        // record voters vote
        hasScreened[account_] = true;

        // vote for the given proposal
        return super._castVote(proposal_.proposalId, account_, 1, "", "");
    }

    /**
     * @notice Calculates the number of votes available to an account depending on the current stage of the Distribution Period.
     * @dev    Overrides OpenZeppelin _getVotes implementation to ensure appropriate voting weight is always returned.
     * @dev    Snapshot checks are built into this function to ensure accurate power is returned regardless of the caller.
     * @dev    Number of votes available is equivalent to the usage of voting weight in the super class.
     * @param  account_     The voting account.
     * @param  blockNumber_ The block number to check the snapshot at.
     * @param  stage_       The stage of the distribution period, or signifier of the vote being part of the extraordinary funding mechanism.
     * @return The number of votes available to an account in a given stage.
     */
    function _getVotes(address account_, uint256 blockNumber_, bytes memory stage_) internal view override(Governor, GovernorVotes) returns (uint256) {
        QuarterlyDistribution memory currentDistribution = distributions[getDistributionId()];

        // within screening period 1 token 1 vote
        if (keccak256(stage_) == keccak256(bytes("Screening"))) {
            // calculate voting weight based on the number of tokens held before the start of the distribution period
            return currentDistribution.startBlock == 0 ? 0 : super._getVotes(account_, currentDistribution.startBlock - 33, "");
        }
        // else if in funding period quadratic formula squares the number of votes
        else if (keccak256(stage_) == keccak256(bytes("Funding"))) {
            QuadraticVoter memory voter = quadraticVoters[currentDistribution.id][account_];
            // this is the first time a voter has attempted to vote this period
            if (voter.votingWeight == 0) {
                return Maths.wpow(super._getVotes(account_, getScreeningPeriodEndBlock(currentDistribution) - 33, ""), 2);
            }
            // voter has already allocated some of their budget this period
            else {
                return uint256(voter.budgetRemaining);
            }
        }
        // one token one vote for extraordinary funding
        else if (keccak256(stage_) == keccak256(bytes("Extraordinary"))) {
            return super._getVotes(account_, blockNumber_, "");
        }
        // voting is not possible for non-specified pathways
        else {
            return 0;
        }
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    //slither-disable-next-line naming-convention
    function COUNTING_MODE() public pure override(IGovernor) returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @notice Restrict voter to only voting once during the screening stage.
     * @dev    See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256, address account_) public view override(IGovernor) returns (bool) {
        return hasScreened[account_];
    }

    /**
     * @notice Required override; not currently used due to divergence in voting logic.
     * @dev    See {IGovernor-_countVote}.
     */
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory) internal override(Governor) {}

    /**
     * @notice Required override used in Governor.state()
     * @dev See {IGovernor-quorumReached}.
     */
    function _quorumReached(uint256) internal pure override(Governor) returns (bool) {
        return true;
    }

    function _voteSucceeded(uint256 proposalId_) internal view override(Governor) returns (bool) {
        return proposals[proposalId_].succeeded;
    }

    /**
     * @notice Required ovverride.
     * @dev    Since no voting delay is implemented, this is hardcoded to 0.
     */
    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculates the remaining blocks left in the current voting period
     * @dev    Required ovverride; see {IGovernor-votingPeriod}.
     * @return The remaining number of blocks.
     */
    function votingPeriod() public view override(IGovernor) returns (uint256) {
        QuarterlyDistribution memory currentDistribution = distributions[getDistributionId()];
        uint256 screeningPeriodEndBlock = getScreeningPeriodEndBlock(currentDistribution);

        if (block.number < screeningPeriodEndBlock) {
            return screeningPeriodEndBlock - block.number;
        }
        else if (block.number > screeningPeriodEndBlock && block.number < currentDistribution.endBlock) {
            return currentDistribution.endBlock - block.number;
        }
        // TODO: implement exraordinary funding mechanism
        else {
            return 0;
        }
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

    // TODO: implement this -> uses enums instead of block number to determine what phase for voting
    //         DistributionPhase phase = distributionPhase()
    function getDistributionPhase(uint256 distributionId_) external view returns (DistributionPhase) {}

    function getDistributionPeriodInfo(uint256 distributionId_) external view returns (uint256, uint256, uint256, uint256, bytes32) {
        QuarterlyDistribution memory distribution = distributions[distributionId_];
        return (
            distribution.id,
            distribution.votesCast,
            distribution.startBlock,
            distribution.endBlock,
            distribution.fundedSlateHash
        );
    }

    /**
     * @notice Get the funded proposal slate for a given distributionId, and slate hash
     */
    function getFundedProposalSlate(uint256 distributionId_, bytes32 slateHash_) external view returns (Proposal[] memory) {
        return fundedProposalSlates[distributionId_][slateHash_];
    }

    /**
     * @notice Get the current state of a given proposal.
     */
    function getProposalInfo(uint256 proposalId_) external view returns (uint256, uint256, uint256, uint256, int256, bool, bool) {
        Proposal memory proposal = proposals[proposalId_];
        return (
            proposal.proposalId,
            proposal.distributionId,
            proposal.votesReceived,
            proposal.tokensRequested,
            proposal.qvBudgetAllocated,
            proposal.succeeded,
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

    function getTopTenProposals(uint256 distributionId_) external view returns (Proposal[] memory) {
        return topTenProposals[distributionId_];
    }

    /*****************************/
    /*** Extraordinary Funding ***/
    /*****************************/

    /**
     * @notice Get the current extraordinaryFundingBaseQuorum required to pass an extraordinary funding proposal.
     */
    function getExtraordinaryFundingQuorum(uint256 blockNumber, uint256 tokensRequested) external view returns (uint256) {
    }

    // TODO: implement custom override - need to support both regular votes, and the extraordinaryFunding mechanism
    function quorum(uint256 blockNumber) public view override(IGovernor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    // TODO: move this into a sort library; investigate replacement with simple iterative sort
    /*************************/
    /*** Sorting Functions ***/
    /*************************/

    // return the index of the proposalId in the array, else -1
    function _findProposalIndex(uint256 proposalId, Proposal[] memory array) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array

        for (int256 i = 0; i < int256(array.length);) {
            //slither-disable-next-line incorrect-equality
            if (array[uint256(i)].proposalId == proposalId) {
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
    function _insertionSortProposalsByVotes(Proposal[] storage arr) internal {
        for (int i = 1; i < int(arr.length); i++) {
            Proposal memory key = arr[uint(i)];
            int j = i;

            while (j > 0 && key.votesReceived > arr[uint(j - 1)].votesReceived) {
                // swap values if left item < right item
                Proposal memory temp = arr[uint(j - 1)];
                arr[uint(j - 1)] = arr[uint(j)];
                arr[uint(j)] = temp;

                j--;
            }
        }
    }

}
