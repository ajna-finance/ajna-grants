#!/bin/bash

set -e

source_list=('./test/utils/harness/grants/ExtraordinaryFunding.sol' './test/utils/harness/grants/StandardFunding.sol')
harness_list=('./src/grants/base/ExtraordinaryFunding.sol' './src/grants/base/StandardFunding.sol')
offset_source=('12' '14')
offset_harness=('13' '15')

for i in "${!harness_list[@]}"; do
    source_file=$(sed -n "${offset_source[i]},\$p" "${source_list[i]}")
    harness_file=$(sed -n "${offset_harness[i]},\$p" "${harness_list[i]}")

    set +e
    differences=$(diff -u --label "Source file: ${source_list[i]}" <(echo "$source_file") --label "Harness file: ${harness_list[i]}" <(echo "$harness_file"))
    diff_exit_code=$?
    set -e

    if [ $diff_exit_code -eq 0 ]; then
        echo "The files are the same."
    else
        echo "The files are different:"
        echo "----"
        echo "$differences"
        echo "----"
        exit 2
    fi
done
