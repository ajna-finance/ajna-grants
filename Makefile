
# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install build

# Clean the repo
clean  :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build  :; forge clean && forge build

# Tests
tests   :; forge clean && forge test -v # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report   :; forge clean && forge build && forge test -v --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
coverage   :; forge coverage

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot

# Deployment
deploy-ajnatoken:
	eval MINT_TO_ADDRESS=${mintto}
	forge script script/AjnaToken.s.sol:DeployAjnaToken \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv
deploy-grantfund:
	eval AJNA_TOKEN=${ajna}
	forge script script/GrantFund.s.sol:DeployGrantFund \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv
