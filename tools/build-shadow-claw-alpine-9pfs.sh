#!/usr/bin/env bash

# change directory
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/.." || exit 1

mkdir -p build \
  && make build/v86.wasm \
  && make build/libv86.mjs \
  && tools/docker/alpine/build.sh \
  && echo \
  && echo Use the following files: \
  && echo \
  && echo bios/seabios.bin \
  && echo bios/vgabios.bin \
  && echo build/libv86.mjs \
  && echo build/v86.wasm \
  && echo images/alpine-fs.json \
  && echo \
  && echo And Directory: \
  && echo \
  && echo images/alpine-rootfs-flat
