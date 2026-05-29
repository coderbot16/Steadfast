#!/bin/sh
mkdir -p build
rustc dec4x8-poc.rs -o build/dec4x8-poc && build/dec4x8-poc
