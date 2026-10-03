#!/bin/sh

expand -t 4 \
  src/*.slang \
  src/**/*.slang \
  src/**/**/*.slang \
  shaders/*.fsh \
  shaders/*.vsh \
  src/program/**/*.fsh \
  src/program/**/*.vsh \
| grep '^.\{81\}'
