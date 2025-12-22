#!/bin/bash

set -euo pipefail

DRAGONFLY_PASSWORD="$(cat /run/secrets/DRAGONFLY_PASSWORD 2>/dev/null || echo '')"

if [ -n "${DRAGONFLY_PASSWORD}" ]; then
    if [ "${#DRAGONFLY_PASSWORD}" -ge 96 ]; then
        exec dragonfly --logtostderr --requirepass "${DRAGONFLY_PASSWORD}"
    else
        echo 'Error: "DRAGONFLY_PASSWORD" length must be at least 96 characters' >&2
        exit 1
    fi
else
    exec dragonfly --logtostderr
fi
