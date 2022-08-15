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
make test
```

<!-- TODO: Determine how to run off-chain integration tests -->

# Research
- https://forum.openzeppelin.com/t/uups-proxies-tutorial-solidity-javascript/7786 

# Questions
- Tax / regulatory implications of full mint by multisig and subsequent transfers of tokens, vs partial mint by multisig and subsequent mint to governance for community distributions?
