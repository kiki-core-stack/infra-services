#!/bin/bash

set -euo pipefail

DRAGONFLY_PASSWORD=''

if [ -r /run/secrets/DRAGONFLY_PASSWORD ]; then
    DRAGONFLY_PASSWORD="$(</run/secrets/DRAGONFLY_PASSWORD)"
    DRAGONFLY_PASSWORD="${DRAGONFLY_PASSWORD#"${DRAGONFLY_PASSWORD%%[![:space:]]*}"}"
    DRAGONFLY_PASSWORD="${DRAGONFLY_PASSWORD%"${DRAGONFLY_PASSWORD##*[![:space:]]}"}"
else
    echo 'Warning: "/run/secrets/DRAGONFLY_PASSWORD" does not exist or is not readable; starting without a password' >&2
fi

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
