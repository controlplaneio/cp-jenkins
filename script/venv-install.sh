#!/bin/bash

set -eo pipefail

cd "$(dirname "$0")"

virtualenv .venv
. .venv/bin/activate

pip install -r requirements.txt
pip install -r test-requirements.txt
