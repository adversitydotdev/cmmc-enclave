#!/usr/bin/env bash
# Builds build/ for terraform's archive_file (module workspace_audit, var.source_dir).
# Run before terraform plan/apply:  collectors/workspace_audit/build.sh
# Wheels are fetched for the Lambda arm64 / python3.12 target, not the host.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir build
pip install --quiet --no-compile --target build \
  --platform manylinux2014_aarch64 --implementation cp --python-version 3.12 \
  --only-binary=:all: -r requirements.txt
cp src/*.py build/
echo "built $(pwd)/build"
