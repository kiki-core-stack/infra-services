#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

find ./stacks -type d \( -name etc -o -name opt \) -exec chmod 755 {} +
find ./stacks -type f -exec chmod 600 {} +
find ./stacks -type f \( \
    -iname '*.conf' -o -iname '*.cnf' -o -iname '*.cfg' -o -iname '*.config' -o -iname '*.ini' \
    -o -iname '*.json' -o -iname '*.jsonc' -o -iname '*.yaml' -o -iname '*.yml' \
    -o -iname '*.toml' -o -iname '*.xml' -o -iname '*.properties' \
    -o -iname '*.js' -o -iname '*.mjs' -o -iname '*.cjs' \
    \) -exec chmod 644 {} +

find ./stacks -type f -name '*.sh' -exec chmod 755 {} +

for arg in "$@"; do
    if [[ "${arg}" == '-p' ]]; then
        docker compose pull
        break
    fi
done

docker compose up -d --remove-orphans
