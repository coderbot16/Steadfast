#!/bin/sh
mkdir -p build
rustc blocklight_color.rs -o build/blocklight_color && build/blocklight_color \
	> ../src/environment/lighting/blocklight_color.slang
