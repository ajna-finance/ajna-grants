# Ajna Ecosystem Coordination

## **Contracts**

## [Grant Fund](./src/grants/GRANT_FUND.md)

## [Ajna Token](./src/token/AJNA_TOKEN.md)


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
- Make a copy of .env.example and name it .env. Add the values for
  - `ETH_RPC_URL` - required by forge to fork chain
- Run
```bash
make all
```

### Contract Deployment
Ensure the following env variables are in your `.env` file or exported into your environment.
| Environment Variable | Purpose |
|----------------------|---------|
| `DEPLOY_ADDRESS`     | address from which you wish to deploy
| `DEPLOY_KEY`         | path to the JSON keystore file for the deployment address
| `ETHERSCAN_API_KEY`  | required to verify contracts
| `ETH_RPC_URL`        | node on your target deployment network


Here's an example:
```
DEPLOY_ADDRESS=0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc
DEPLOY_KEY=~/hush/deployment.json
ETHERSCAN_API_KEY=55ORCKI875XKNO89475DNOCHDPINI54OFY
ETH_RPC_URL=http://127.0.0.1:8545
```

You will be prompted for your key's password interactively.

⚠ The `ETH_RPC_URL` you provide determines the deployment network for your contract.

If you wish to deploy against an `anvil` or `ganache` endpoint, edit the `Makefile`, replacing `--keystore ${DEPLOY_KEY}` with `--private-key ${DEPLOY_PRIVATE_KEY}`.  In your environment, set `DEPLOY_ADDRESS` to one of the pre-funded accounts and `DEPLOY_PRIVATE_KEY` to the unencrypted private key.


#### AJNA token
Deployment of the AJNA token requires an argument stating where minted tokens should be sent.  AJNA has already been deployed to Goerli and Mainnet; see [AJNA_TOKEN.md](src/token/AJNA_TOKEN.md#ajna-token) for addresses.  There is no reason to deploy the AJNA token to L2s or sidechains; see [MULTICHAIN_STRATEGY.md](MULTICHAIN_STRATEGY.md) for details.  Upon deployment, minted tokens are transferred to a user-specified address which must be specified in make arguments.  To run a new deployment on a test network or local testchain, run:
```
make deploy-ajnatoken mintto=<MINT_TO_ADDRESS>
```
Record the address of the token upon deployment.  See [AJNA_TOKEN.md](src/token/AJNA_TOKEN.md#deployment) for validation.

#### Grant Fund
Deployment of the Grant Coordination Fund requires an argument to specify the address of the AJNA token. The deployment script also uses the token address to determine funding level.

Before deploying, edit `src/grants/base/Storage.sol` to set the correct AJNA token address for the target chain.

To deploy, run:
```
make deploy-grantfund ajna=<AJNA_TOKEN_ADDRESS>
```

See [GRANT_FUND.md](src/grants/GRANT_FUND.md#deployment) for next steps.
