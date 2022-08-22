
# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install build

# Clean the repo
clean  :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build  :; forge clean && forge build --optimize --optimizer-runs 1000000

# Tests
tests   :; forge clean && forge test --optimize --optimizer-runs 1000000 -v # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report   :; forge clean && forge build && forge test --optimize --optimizer-runs 1000000 -v --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
coverage   :; forge coverage

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot --optimize --optimize-runs 1000000

# Deployment
# use the "@" to hide the command from your shell 
deploy-contract :; @forge script script/${contract}.s.sol:Deploy${contract} --rpc-url ${RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY}  -vvvv