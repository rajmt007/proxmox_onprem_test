#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml

echo
echo "Setup complete. Activate the environment with:"
echo "  source \"$ROOT_DIR/.venv/bin/activate\""
echo "Copy .env.example to .env, fill local values, and source it before running playbooks."
