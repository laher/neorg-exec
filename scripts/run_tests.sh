#!/usr/bin/env bash

HERE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
cd $HERE/..

run() {
    nvim --headless \
        -c "PlenaryBustedDirectory $1"
            # when this works then great { minimal_init = './scripts/minimal_init.lua' }"
}

if [[ $2 = '--summary' ]]; then
    ## really simple results summary by filtering plenary busted output
    run tests/$1  2> /dev/null | grep -E '^\S*(Testing|Success|Failed|Errors)\s*:'
else
    run tests/$1
fi
