# Ajna Token

Ajna ERC20 Token contract

## Deployment
Configure environment with `ETH_RPC_URL` pointing to the target chain for deployment.  Set `DEPLOY_ADDRESS` to the deployment address and `DEPLOY_KEY` to the JSON keystore file.  If you want initial tokens to go to a different address than the deploying address, update constructor arguments accordingly.

Run
```
forge create --rpc-url ${ETH_RPC_URL} \
	--keystore ${DEPLOY_KEY} src/AjnaToken.sol:AjnaToken \
	--constructor-args ${DEPLOY_ADDRESS}
```
and interactively enter your password.  Add `--verify` switch once repository has been made public.

Record the `Deployed to` address returned, exporting to your environment as `AJNA_TOKEN`.

Run the following to validate AJNA token balance:
```
cast call ${AJNA_TOKEN} "balanceOf(address)" ${DEPLOY_ADDRESS} --rpc-url ${ETH_RPC_URL}
```


<br>

# Design

### **Immutable implementation of [OpenZeppelin ERC20](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20) with the following extensions:**
* [ERC20Votes](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC20Votes)
    - Implements delegation, voting weights, and voting power calculations in the style of Compound governance
    - Used by Uniswap, Compound, Tally
* [ERC20Burnable](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC20Burnable)
    - Allows the burning of tokens. This would be useful with the reserve pool to burn Ajna tokens for a given pool’s quote tokens in a standardized way.
* [ERC20Permit](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC20Permit)
    - Useful UX improvement that allows users to transfer tokens with a signature argument to transfer as opposed to having to execute separate approve and transfer transactions.

### **External Methods:**
* approve
    - Allows an external address to spend a user’s tokens
* burn
    - Sends a user’s tokens to the 0x0 address
* burnFrom
    - External address sends a user’s tokens to the 0x0 address    
* delegate
    - Delegates votes from sender to delegatee
* delegateBySig
    - Delegates votes from signer to delegatee
* decreaseAllowance
    - Decrease the amount of tokens an external address is allowed to spend for a user
* increaseAllowance
    - Increase the amount of tokens an external address is allowed to spend for a user
* permit
    - Approve an external address to spend a user’s tokens by signature
* transfer
    - Transfer a user’s tokens to another address
* transferFrom
    - Transfer tokens from one address to another
* transferFromWithPermit
    - Transfer tokens from one address to another using Permit and avoiding a separate approval tx

<br>

# Development

Install Foundry [instructions](https://github.com/gakonst/foundry/blob/master/README.md#installation)  then, install the [foundry](https://github.com/gakonst/foundry) toolchain installer (`foundryup`) with:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

To get the latest `forge` or `cast` binaries, tun

```bash
foundryup
```

#### Project Setup

```bash
make all
```

#### Run Tests

```bash
make tests
```


### Contract Deployment
Ensure the following env variables are set in your env file `.env`

```
PRIVATE_KEY = <PRIVATE_KEY_HERE>
ETHERSCAN_API_KEY = <ETHERSCAN_API_KEY_HERE>
MINT_TO_ADDRESS = <MINT_TO_ADDRESS_HERE>
```

Once the above variables are set run the following:
WARNING: THE RPC_URL PASSED IN WILL DETERMINE WHAT NETWORK YOUR CONTRACT IS DEPLOYED ON.
```
make deploy-contract contract=<CONTRACT_NAME_HERE> RPC_URL=<RPC_URL_HERE>
```


### Governance Design Research:
*OpenZeppelin Guides*
- https://docs.openzeppelin.com/contracts/4.x/governance
- https://wizard.openzeppelin.com/#governor
- https://twitter.com/OpenZeppelin/status/1448054190631051266

*ENS*
- https://github.com/ensdomains/governance-docs/blob/main/process/README.md
- https://github.com/ensdomains/governance 

*HOP*
- https://github.com/hop-protocol/governance

*OP*
- https://github.com/ethereum-optimism/optimism/tree/develop/packages/contracts-governance

*Multichain Governance*
- https://doseofdefi.substack.com/p/multichain-governance-how-can-daos
- https://github.com/gnosis/zodiac
- https://ethereum-magicians.org/t/eip-draft-multi-chain-governance/9284

*General Governance Research*
- https://github.com/D3LAB-DAO/Governor-C

*Potential Vote Counting structures*
- https://github.com/bokkypoobah/BokkyPooBahsRedBlackTreeLibrary


*QV*
- https://github.com/VirginiaBlockchain/QuadraticVotingDapp
- https://blog.tally.xyz/a-simple-guide-to-quadratic-voting-327b52addde1

*Tally*
- https://docs.tally.xyz/user-guides/tally-contract-compatibility


*https://www.daomasters.xyz/*