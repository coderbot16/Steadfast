#!/bin/sh

expand -t 4 \
  shaders/*.glsl \
  shaders/**/*.glsl \
  shaders/**/**/*.glsl \
  shaders/*.fsh \
  shaders/*.vsh \
  shaders/program/**/*.fsh \
  shaders/program/**/*.vsh \
| grep '^.\{81\}'
