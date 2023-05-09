# GrantFund Invariants

## Treasury Invariants:
   - **T1**: The Grant Fund's `treasury` should always be less than or equal to the contract's token balance.
   - **T2**: The Grant Fund's `treasury` should always be less than or equal to the Ajna token total supply.

## Standard Funding Mechanism Invariants

- #### Distribution Period:
    - **DP1**: Only one distribution period should be active at a time. Each successive distribution period's start block should be greater than the previous periods end block.
    - **DP2**: Each winning proposal successfully claims no more that what was finalized in the challenge stage
    - **DP3**: A distribution's fundsAvailable should be equal to 2% of the treasurie's balance at the block `startNewDistributionPeriod()` is called.
    - **DP4**: A distribution's endBlock should be greater than its startBlock.
    - **DP5**: The treasury balance should be greater than the sum of the funds available in all distribution periods.
    - **DP6**: Surplus funds from distribution periods whose token's requested in the final funded slate was less than the total funds available are readded to the treasury.
    - **DP7**: A distribution period's surplus should only be readded to the treasury once.

- #### Screening Stage:
    - **SS1**: Only 10 proposals can advance to the funding stage
    - **SS2**: Users can only vote up to the amount of their voting power at the snapshot blocks.
    - **SS3**: Top ten list of screened proposals should be sorted in descending order.
    - **SS4**: Screening vote's cast can only be positive.
    - **SS5**: Screening votes can only be cast on a proposal in it's distribution period's screening stage.
    - **SS6**: For every proposal, it is included in the top 10 list if, and only if, it has as many or more votes as the last member of the top ten list (typically the 10th of course, but it may be shorter than ten proposals).
    - **SS7**: A proposal should never receive more vote than the Ajna token supply.
    - **SS8**: A proposal can only receive screening votes if it was created via `proposeStandard()`.
    - **SS9**: A proposal can only be created during a distribution period's screening stage.

- #### Funding Stage:
    - **FS1**: Only 10 proposals can be voted on in the funding stage
    - **FS2**: Proposals not in the top ten proposals should have fundingVotesReceived = 0.
    - **FS3**: Votes can only be cast on a proposal in it's distribution period's funding stage.
    - **FS4**: Sum of square of votes cast by a given actor are less than or equal to the actor's Ajna delegated balance, squared.
    - **FS5**: Sum of voter's votesCast should be equal to the square root of the voting power expended (FS4 restated, but added to test intermediate state as well as final).
    - **FS6**: All voter funding votes on a proposal should be cast in the same direction. Multiple votes on the same proposal should see the voting power increase according to the combined cost of votes.
    - **FS7** List of top ten proposals should never change once the funding stage has started.
    - **FS8**: a voter should never be able to cast more votes than the Ajna token supply.

- #### Challenge Stage:
    - **CS1**: Funded proposal slate's cumulative tokens requested should be less than or equal to 90% of the GBC.
    - **CS2**: Funded proposal slate should contain less than or equal to 10 proposals.
    - **CS3**: Funded proposal slate should be never contain a proposal with negative funding votes.
    - **CS4**: Funded proposals are all a subset of the ones voted on in funding stage.
    - **CS5**: Funded proposal slate's should never contain duplicate proposals.
    - **CS6**: Funded proposal slate's can only be updated during a distribution period's challenge stage.

- #### Execute Standard:
    - **ES1**: A proposal can only be executed if it's listed in the final funded proposal slate at the end of the challenge round.
    - **ES2**: A proposal can only be executed after the challenge stage is complete.
    - **ES3**: A proposal can only be executed once.

- #### Delegation Rewards:
    - **DR1**: Cumulative delegation rewards should be 10% of a distribution periods GBC.
    - **DR2**: Delegation rewards are 0 if voter didn't vote in both stages.
    - **DR3**: Delegation rewards are proportional to voters funding power allocated in the funding stage.

## Extraordinary Funding Mechanism Invariants

- #### Extraordinary Global Invariants:
    - **EG1**: The `minimumThresholdPercentage` variable increases by 5% for each successive executed proposal.

- #### Execute Extraordinary:
    - **EE1**: A proposal can only be executed once.
    - **EE2**: A proposal can only be executed if its `votesReceived` exceeds its `tokensRequested` + the `minimumThresholdPercentage` times the non-treasury token supply at the time of execution.
    - **EE3**: A proposal can only be executed if it's `tokensRequested` is less than `treasury` * (1 - `minimumThresholdPercentage`).
    - **EE4**: Only 9 proposals can be executed.

- #### Propose Extraordinary:
    - **PE1**: A proposal's proposalId must be unique.
    - **PE2**: A proposal's endBlock must be less than the `MAX_EFM_PROPOSAL_LENGTH` of 216_000 blocks.
    - **PE3**: A proposal's tokens requested must be less than treasuryBalance * (1 - `minimumThresholdPercentage`).

- #### Vote Extraordinary:
    - **VE1**: A proposal can only be voted on once.
    - **VE2**: A proposal can only be voted on if the block number is less than or equal to the proposals end block and the `MAX_EFM_PROPOSAL_LENGTH` of 216_000 blocks.
    - **VE3**: Votes cast must always be positive.
    - **VE4**: A voter should never be able to cast more votes than the Ajna token supply.

## Global Invariants:
   - **G1**: A proposal should never enter an unused state (canceled, queued, expired).
