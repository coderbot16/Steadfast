#!/bin/sh

grep '^.\{81\}' \
  src/*.slang \
  src/**/*.slang \
  src/**/**/*.slang \
  shaders/*.fsh \
  shaders/*.vsh \
  src/program/**/*.fsh \
  src/program/**/*.vsh

grep '^.\{81\}' \
  shaders/*.properties \
  pipeline/*.properties \
  pipeline/**/*.properties \
  pipeline/**/**/*.properties
