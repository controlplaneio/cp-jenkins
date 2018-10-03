#!/bin/bash

set -eo pipefail

cd "$(dirname "$0")"

echo "Setting up virtual environment"

if [[ ! -d .venv ]]; then
    ./venv-install.sh
fi

. .venv/bin/activate

PYTHONPATH=. pytest $@

BEHAVE_EXIT_STATUS=$?
