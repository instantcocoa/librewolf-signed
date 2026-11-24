#!/usr/bin/env bash
# Upstream (>= 160.0) dropped the `version` and `release` files and moved the
# values into the Makefile (VERSION / RELEASE). Our workflows still read the
# files, so regenerate them from the Makefile after every sync.
set -euo pipefail
make -s version > version
make -s release > release
echo "version=$(cat version) release=$(cat release)"
