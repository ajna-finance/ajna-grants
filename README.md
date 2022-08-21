# Ajna Token

Ajna ERC20 Token contract

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
```

Once the above variables are set run the following:
WARNING: THE RPC_URL PASSED IN WILL DETERMINE WHAT NETWORK YOUR CONTRACT IS DEPLOYED ON.
```
make deploy-contract contract=<CONTRACT_NAME_HERE> RPC_URL=<RPC_URL_HERE>
```






<!-- TODO: Determine how to run off-chain integration tests -->

# Research
- https://forum.openzeppelin.com/t/uups-proxies-tutorial-solidity-javascript/7786 
- https://github.com/jordaniza/OZ-Upgradeable-Foundry
- https://github.com/beskay/UUPS_Proxy/blob/main/src/test/Implementation.t.sol
- https://docs.openzeppelin.com/contracts/4.x/api/proxy#transparent-vs-uups
- https://eips.ethereum.org/EIPS/eip-1822

# Questions
- Tax / regulatory implications of full mint by multisig and subsequent transfers of tokens, vs partial mint by multisig and subsequent mint to governance for community distributions?
