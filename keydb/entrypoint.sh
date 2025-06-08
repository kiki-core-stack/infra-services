#!/bin/sh

set -e

KEYDB_PASSWORD=$(cat /run/secrets/KEYDB_PASSWORD)

if [ -n "${KEYDB_PASSWORD}" ]; then
    if [ "${#KEYDB_PASSWORD}" -ge 96 ]; then
        exec keydb-server /etc/keydb/keydb.conf --requirepass "${KEYDB_PASSWORD}"
    else
        echo 'Error: "KEYDB_PASSWORD" length must be at least 96 characters.' >&2
        exit 1
    fi
else
    exec keydb-server /etc/keydb/keydb.conf
fi
