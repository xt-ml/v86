#!/usr/bin/env bash

# change directory
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/.." || exit 1

mkdir -p images \
  && curl \
    --compressed \
    --output-dir images/ \
    --remote-name-all "https://i.copy.sh/{linux.iso,linux3.iso,linux4.iso,buildroot-bzimage68.bin,...}"

