# Multichain Strategy

## Design

Ajna deployments to each chain are sovereign and independant. Each chain will utilize the AJNA token address on that chain for the burn-and-buy mechanism. The grant fund will remain entirely on L1, with only L1 token delegates able to vote.

L1 AJNA should be burn-wrapped before being bridged to any L2 solution. To facilitate this, a `BurnWrapper` contract shall be deployed to L1 to create a canonical L1 bwAJNA. The `BurnWrapper` contract enables L1 Ajna tokens to be wrapped via OpenZeppelin's _ERC20Wrapper_ extension, and converted into bwAJNA tokens. These tokens cannot be unwrapped.

### Rollups

Ajna pool factories may be deployed on Ethereum L2 rollups, with each pool pointing at the bwAJNA token address created by sending L1 bwAJNA across the rollup's canonical bridge. This token address is deterministic and tied to the L1 address, so it doesn't matter who bridges the token first. This behaviour is the same across rollups (Arbitrum, Optimism, Zksync).

Third party bridges can be used as support is added via bridge governance. Third party bridges point at the token address created by the standard token bridges.

NOTE (11/16/22): Starknet doesn't currently support non-whitelisted ERC20 tokens. ZKSync is permissionless, but only supports testnet tokens for permissionless bridging.

<br>

### Sidechains

Due to the lower safety of sidechain bridges, bwAJNA tokens should be double-wrapped by a sidechain-specific `BurnWrapper` also deployed on the L1. This design prevents double-spends of the bwAJNA token due to sidechain bridges being compromised and releasing bwAJNA tokens incorrectly, artifically increasing the token supply available for burn-and-buy on other L2 solutions.

#### Polygon 

bwAJNA tokens must be mapped to the polygon sidechain prior to bridging. This mapping will create a unique address for bwAJNA on the sidechain. Once this address has been created, it can be referenced permissionlessly in either of the Polygon POS, or Polygon Plasma bridges.

#### Binance

Requires a Binance account to use the canonical binance bridge. Third-party bridges rely on the binance bridge as a source of truth. Don't necessarily have to be listed to use the bridge, but unclear.

<br>

## Resources

**Arbitrum**
1. https://developer.offchainlabs.com/asset-bridging
2. https://community.optimism.io/docs/developers/bridge/basics/
3. https://github.com/OffchainLabs/token-bridge-contracts/blob/main/contracts/tokenbridge/test/TestArbCustomToken.sol

**Base**
1. https://docs.base.org/tools/bridges
2. https://docs.base.org/tools/bridge-faq

**Optimism**
1. https://community.optimism.io/docs/developers/bridge/standard-bridge/#adding-an-erc20-token-to-the-standard-bridge

**ZkSync**
1. https://portal.zksync.io/bridge
2. https://v2-docs.zksync.io/dev/developer-guides/bridging/bridging-asset.html#introduction

**Starknet**
1. https://medium.com/@starkscan/how-to-bridge-between-starknet-and-ethereum-3f1b9704aed2

**Polygon**
1. https://wiki.polygon.technology/docs/develop/ethereum-polygon/getting-started
2. https://wiki.polygon.technology/docs/develop/ethereum-polygon/pos/mapping-assets

**BSC**
1. https://www.bnbchain.org/en/bridge
