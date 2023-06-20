#!/bin/bash
set -ex

echo "Exporting environment variables"

# export environment variables retrieved from user input
export SCENARIO=${1:-${SCENARIO}}
export NUM_ACTORS=${2:-${NUM_ACTORS}}
export NUM_PROPOSALS=${3:-${NUM_PROPOSALS}}
export PER_ADDRESS_TOKEN_REQ_CAP=${4:-${PER_ADDRESS_TOKEN_REQ_CAP}}

echo "Running invariant test"

# run invariant test
forge t --mc $SCENARIO
