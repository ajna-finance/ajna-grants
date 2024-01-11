# Ajna Grant Coordination Fund

As a decentralized protocol with no external governance, Ajna requires a sustainable mechanism by which to coordinate ecosystem growth in a scalable and decentralized way. The grant coordination mechanism is premised upon the idea that the AJNA token has value from the buy and burn mechanism. Upon launch, the Ajna community will be given a fixed portion of the total AJNA token supply, which will be held and distributed by the Grant Coordination Fund.

| Deployment | Address |
| ---------: | ------- |
| Mainnet    | (net yet deployed) |
| Goerli     | [0x54110a15011bcb145a8CD4f5adf108B2B6939A1e](https://goerli.etherscan.io/address/0xc9216387C7920C8a7b6C2cE4A44dEd5776a3B5B4) |

## Design

The Grant Coordination Fund will distribute funds through the two sub-mechanisms defined below. It is based upon Openzeppelin's Governor contract.

![System Architecture](../../docs/GrantFund.jpg)

### **Standard Funding Mechanism**

On a quarterly basis, a portion of the treasury is distributed to facilitate growth of the Ajna system.  Projects submit proposals for funding, denominated in a fixed amount of Ajna tokens, that are then voted on by Ajna token holders.  The result of this voting is binary: either the proposal wins and is funded with the requested tokens, or fails and receives nothing.  The overall set of approved proposals is decided upon by maximizing the number of votes for them, subject to an overall budgetary constraint. 

The voting system has three stages. First, a screening stage (525,600 blocks long), in which the list of possible winning projects is culled down to 10 candidates using a simple 1-token-1-vote method. Next there is a quadratic voting or Funding stage (72,000 blocks long), where voters are able to cast votes for or against proposals up to the cumulative sum of the square of their votes, further filtering the propsosals. Finally there is a challenge stage (50,400 blocks long), in which anyone can submit the set of proposals from the filtered top ten list which received the most net votes, and which doesn't exceed the token budget for that distribution period. The distribution period as a whole lasts for 648,000 blocks. New distribution periods cannot be started until the previous distribution period has ended (the number of blocks has elapsed), and must be started by calling `startNewDistributionPeriod`.

For more information, see the Ajna Protocol Whitepaper.

<br>

## Deployment

See [README.md](../../README.md) for instructions using the `Makefile` target.

Output should confirm the AJNA token address, provid the GrantFund address, and the amount of AJNA which should be transferred to the GrantFund adress:
```
== Logs ==
  Deploying GrantFund to chain
  GrantFund deployed to 0xc9216387C7920C8a7b6C2cE4A44dEd5776a3B5B4
  Please transfer 300000000 AJNA (300000000000000000000000000 WAD) into the treasury
```

Record the deployment address in your environment as `GRANTFUND_ADDRESS`.

The Grant Fund is by default deployed without any Ajna tokens in it's treasury. To add tokens, someone must call `fundTreasury(uint256)` with the amount of Ajna tokens to transfer to the Grant Fund. **WARNING**: Ajna tokens transferred directly to the smart contract won't be credited to the treasury balance if `fundTreasury` is circumvented.

To perform the transfer, set `TREASURY_ADDRESS` and `TREASURY_KEY` to the appropriate values and run the following:

```
cast send ${AJNA_TOKEN} "approve(address,uint256)" ${GRANTFUND_ADDRESS} 300000000000000000000000000 --from ${TREASURY_ADDRESS} --keystore ${TREASURY_KEY} --rpc-url ${ETH_RPC_URL} 
cast send ${GRANTFUND_ADDRESS} "fundTreasury(uint256)" 300000000000000000000000000 --from ${TREASURY_ADDRESS} --keystore ${TREASURY_KEY} --rpc-url ${ETH_RPC_URL} 
```
