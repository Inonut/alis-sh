#!/usr/bin/env bash
set -e

function foo() {
  while IFS= read -r line
  do
    if [ -n "$line" ]; then
      eval "local $line"
    fi
  done < <(grep -v '^ *#' < alis.conf)

  echo "$DEVICE"
}

foo
echo "$DEVICE"
