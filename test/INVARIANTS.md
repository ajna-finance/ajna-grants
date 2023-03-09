# GrantFund Invariants

## Standard Funding Mechanism Invariants

- #### Distribution Period:
    - **DP1**: Only one distribution period should be active at a time

- #### Screening Stage:
    - **SS1**: Only 10 proposals can advance to the funding stage
    - **SS2**: Users can only vote up to the amount of their voting power at the snapshot blocks.
    - **SS3**: Top ten list of screened proposals should be sorted in descending order.
    - **SS4**: Vote tally for a proposal can only be positive.
    - **SS5**: Votes can only be cast on a proposal in it's distribution period's screening stage.


- #### Funding Stage:
    - **FS1**: Only 10 proposals can be voted on in the funding stage
    - **FS2**: Votes can only be cast on a proposal in it's distribution period's funding stage.
    - **FS3**: Cumulative votes cast should be less than or equal to the sum of the squares of the votes cast.    

- #### Challenge Stage:
    - **CS1**: Funded proposal slate's cumulative tokens requested should be less than or equal to 90% of the GBC.
    - **CS2**: Funded proposal slate should be never contain a proposal with negative votes.
    - **CS3**: Funded proposal slate should contain less than or equal to 10 proposals.

- #### Execute Standard:
    <!-- - **ES1**: Only t -->

- #### Delegation Rewards:
    - **DR1**: Cumulative delegation rewards should be 10& of a dsitribution periods GBC.
    - **DR2**: Delegation rewards are 0 if voter didn't vote in both stages.
    - **DR3**: Delegation rewards are proportional to voters funding power allocated in the funding stage.

## Extraordinary Funding Mechanism Invariants

