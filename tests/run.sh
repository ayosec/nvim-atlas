#!/usr/bin/env bash
#
# Executes the specs under the tests/specs directory.
#
# If the environment variable ATLAS_SPECS is defined, it must be
# a comma-separated list of patterns to specify which spec files
# must be executed. Each pattern will be surrounded by `*`, so
# `foo` is `*foo*`.
#
#   $ nix develop --command env ATLAS_SPECS='pipeline,parser' make test


set -euo pipefail

if [ $# -ne 1 ]
then
    echo "Usage: $0 PLENARY_DIR"
    exit 1
fi

export PLENARY="$1"

runtest=(
    nvim
        --clean
        --headless
        -u tests/init.lua
)

# Executes all specs if ATLAS_SPECS is empty.
if [ -z "${ATLAS_SPECS:-}" ]
then
    exec "${runtest[@]}" -c "PlenaryBustedDirectory tests/specs { minimal_init = './tests/init.lua' }"
fi



# Find the spec files, and executes each one in their own
# Neovim process.
#
# To collect the required files, a find(1) command like
# this is built from the patterns:
#
#     find tests/specs -name '*_spec.lua' \( -path '*foo*' -or -path '*bar*' \)

exitcode=0
findpaths=()

IFS=, read -rs -a specs_patterns <<<"$ATLAS_SPECS"

for specs_pattern in "${specs_patterns[@]}"
do
    if [ "${#findpaths[@]}" -ne 0 ]
    then
        findpaths+=(-or)
    fi

    findpaths+=(-path "*${specs_pattern}*")
done

mapfile -t files < <(find tests/specs -name '*_spec.lua' \( "${findpaths[@]}" \))
for filename in "${files[@]}"
do
    if ! "${runtest[@]}" -c "PlenaryBustedFile $filename"
    then
        exitcode=1
    fi
done

exit $exitcode
