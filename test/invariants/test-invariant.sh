#!/bin/bash
set -ex

echo "Exporting environment variables"

# export environment variables retrieved from user input
export SCENARIO=${1:-${SCENARIO}}
export LOGS_VERBOSITY=${2:-${LOGS_VERBOSITY}}
export NUM_ACTORS=${3:-${NUM_ACTORS}}
export NUM_PROPOSALS=${4:-${NUM_PROPOSALS}}
export PER_ADDRESS_TOKEN_REQ_CAP=${5:-${PER_ADDRESS_TOKEN_REQ_CAP}}

echo "Running invariant test"

# run invariant test
forge t --mc $SCENARIO
