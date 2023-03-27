# GrantFund Invariants

## Standard Funding Mechanism Invariants

- #### Distribution Period:
    - **DP1**: Only one distribution period should be active at a time
    - **DP2**: Each winning proposal successfully claims no more that what was finalized in the challenge stage

- #### Screening Stage:
    - **SS1**: Only 10 proposals can advance to the funding stage
    - **SS2**: Users can only vote up to the amount of their voting power at the snapshot blocks.
    - **SS3**: Top ten list of screened proposals should be sorted in descending order.
    - **SS4**: Vote tally for a proposal can only be positive.
    - **SS5**: Votes can only be cast on a proposal in it's distribution period's screening stage.
    - **SS6**: For every proposal, it is included in the top 10 list if, and only if, it has as many or more votes as the last member of the top ten list (typically the 10th of course, but it may be shorter than ten proposals).

- #### Funding Stage:
    - **FS1**: Only 10 proposals can be voted on in the funding stage
    - **FS2**: Votes can only be cast on a proposal in it's distribution period's funding stage.
    - **FS3**: Sum of square of votes cast by a given actor are less than or equal to the actor's Ajna delegated balance, squared.

- #### Challenge Stage:
    - **CS1**: Funded proposal slate's cumulative tokens requested should be less than or equal to 90% of the GBC.
    - **CS2**: Funded proposal slate should be never contain a proposal with negative votes. (Q: is this actually enforced in the code??)
    - **CS3**: Funded proposal slate should contain less than or equal to 10 proposals.
    - **CS3'**: Funded proposals are all a subset of the ones voted on in funding stage

- #### Execute Standard:
    - **ES1**: A proposal can only be executed once.
    - **ES2**: A proposal can only be executed after the challenge stage is complete.

- #### Delegation Rewards:
    - **DR1**: Cumulative delegation rewards should be 10% of a dsitribution periods GBC.
    - **DR2**: Delegation rewards are 0 if voter didn't vote in both stages.
    - **DR3**: Delegation rewards are proportional to voters funding power allocated in the funding stage.

## Extraordinary Funding Mechanism Invariants
    - **EF1**: minimumThresholdPercentage increases by 5% for each successive winning proposal.
    - **EF2**: if a proposal succeeded, the votes for it exceeded the minimumThresholdPercentage times treasury size

- #### Execute Extraordinary:
    - **EE1**: A proposal can only be executed once.
    - **EE2**: A proposal can only be executed after it surpasses the minimum vote threshold.
    - **EE3**: Only 9 proposals can be executed.

- #### Propose Extraordinary:
    - **PE1**: A proposal's proposalId must be unique.
    - **PE2**: A proposal's endBlock must be less than the MAX_EFM_PROPOSAL_LENGTH of 216_000 blocks.
    - **PE3**: A proposal's tokens requested must be less than treasuryBalance * (1 - minimumThresholdPercentage).

- #### Vote Extraordinary:
    - **VE1**: A proposal can only be voted on once.
    - **VE2**: A proposal can only be voted on if the block number is less than or equal to the proposals end block and the MAX_EFM_PROPOSAL_LENGTH of 216_000 blocks.


## Grant Fund Invariants:
   - **GF1**: Unused proposal states should always be 0.
   - **GF2**: Treasury should always be less than or equal to the contract's token blance.