#!/usr/bin/env bash
set -e

{ # try

    echo 'aaaaaaaaaa'
    #save your output

} || { # catch
    # save log for exception
    echo "asd"
}

echo 'asdasdasd'
