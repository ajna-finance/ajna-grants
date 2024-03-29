# GrantFund Invariants

- #### Distribution Period:
    - **DP1**: Only one distribution period should be active at a time. Each successive distribution period's start block should be greater than the previous periods end block.
    - **DP2**: Each winning proposal successfully claims no more that what was finalized in the challenge stage
    - **DP3**: A distribution's fundsAvailable should be equal to 3% of the treasury's balance at the block `startNewDistributionPeriod()` is called.
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
    - **SS7**: Screening votes on a proposal should cause addition to the topTenProposals if no proposal has been added yet
    - **SS8**: A proposal should never receive more screening votes than the Ajna token supply.
    - **SS9**: A proposal can only receive screening votes if it was created via `propose()`.
    - **SS10**: A proposal can only be created during a distribution period's screening stage.
    - **SS11**: A proposal's tokens requested must be <= 90% of GBC.

- #### Funding Stage:
    - **FS1**: Only 10 proposals can be voted on in the funding stage
    - **FS2**: Proposals not in the top ten proposals should have fundingVotesReceived = 0.
    - **FS3**: Votes can only be cast on a proposal in it's distribution period's funding stage.
    - **FS4**: Sum of square of votes cast by a given actor are less than or equal to the actor's Ajna delegated balance, squared.
    - **FS5**: Sum of voter's votesCast should be equal to the square root of the voting power expended (FS4 restated, but added to test intermediate state as well as final).
    - **FS6**: All voter funding votes on a proposal should be cast in the same direction. Multiple votes on the same proposal should see the voting power increase according to the combined cost of votes.
    - **FS7**: List of top ten proposals should never change once the funding stage has started.
    - **FS8**: a voter should never be able to cast more votes than the Ajna token supply.

- #### Challenge Stage:
    - **CS1**: Funded proposal slate's cumulative tokens requested should be less than or equal to 90% of the GBC.
    - **CS2**: Funded proposal slate should contain less than or equal to 10 proposals.
    - **CS3**: Funded proposal slate should be never contain a proposal with negative funding votes.
    - **CS4**: Funded proposals are all a subset of the ones voted on in funding stage.
    - **CS5**: Funded proposal slate's should never contain duplicate proposals.
    - **CS6**: Funded proposal slate's can only be updated during a distribution period's challenge stage.
    - **CS7**: The highest submitted funded proposal slate should have won or tied depending on when it was submitted.

- #### Execute:
    - **ES1**: A proposal can only be executed if it's listed in the final funded proposal slate at the end of the challenge round.
    - **ES2**: A proposal can only be executed after the challenge stage is complete.
    - **ES3**: A proposal can only be executed once.
    - **ES4**: A proposal can only be executed if it was in the top ten screened proposals at the end of the screening stage.
    - **ES5**: An executed proposal should only ever transfer tokens <= 90% of GBC.

- #### Delegation Rewards:
    - **DR1**: Cumulative delegation rewards should be <= 10% of a distribution periods GBC.
    - **DR2**: Delegation rewards are 0 if voter didn't vote in both stages.
    - **DR3**: Delegation rewards are proportional to voters funding power allocated in the funding stage, as compared to all funding power allocated.
    - **DR4**: Delegation rewards can only be claimed for a distribution period after it ended.
    - **DR5**: Cumulative rewards claimed should be within 99.99% of all available delegation rewards.

- #### Proposal:
    - **P1**: A proposal should never enter an unused state (pending, canceled, queued, expired).
    - **P2**: A proposal's proposalId must be unique.

- #### Treasury:
   - **T1**: The Grant Fund's `treasury` should always be less than or equal to the contract's token balance.
   - **T2**: The Grant Fund's `treasury` should always be less than or equal to the Ajna token total supply.
