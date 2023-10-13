
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
tests                                :; forge clean && forge test --mt test --optimize --optimizer-runs 1000000 -v # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report                 :; forge clean && forge build && forge test --mt test --optimize --optimizer-runs 1000000 -v --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
test-unit							 :; forge clean && forge test --no-match-test invariant --optimize --optimizer-runs 1000000 -v # --ffi # enable if you need the `ffi` cheat code on HEVM
test-invariant                       :; ./test/invariants/test-invariant.sh ${SCENARIO} ${NUM_ACTORS} ${NUM_PROPOSALS} ${PER_ADDRESS_TOKEN_REQ_CAP}
test-invariant-all                   :; forge clean && forge t --mt invariant
test-invariant-multiple-distribution :; forge clean && ./test/invariants/test-invariant.sh MultipleDistribution 2 25 200
coverage                             :; forge coverage

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot --optimize --optimize-runs 1000000

# Deployment
deploy-ajnatoken:
	eval MINT_TO_ADDRESS=${mintto}
	forge script script/AjnaToken.s.sol:DeployAjnaToken \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv --verify
deploy-grantfund:
	eval AJNA_TOKEN=${ajna}
	forge script script/GrantFund.s.sol:DeployGrantFund \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv --verify
deploy-burnwrapper:
	eval AJNA_TOKEN=${ajna}
	forge script script/BurnWrapper.s.sol:DeployBurnWrapper \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv --verify
deploy-grantfund-deployer:
	forge create --rpc-url ${ETH_RPC_URL} --keystore ${DEPLOY_KEY} --verify src/grants/Deployer.sol:Deployer
