# Ajna Ecosystem Coordination

## **Contracts**

## [GRANT COORDINATION FUND](./src/GRANT_FUND.md)

## [Ajna Token](./src/AJNA_TOKEN.md)


<br>

## **Development**

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
