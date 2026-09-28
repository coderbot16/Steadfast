#!/bin/sh
# Steadfast is a fast and high-quality graphical overhaul for Minecraft (JE)
# Copyright (C) 2026 coderbot
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

cp src/java/NoiseWave.java src/java/Caustic.java generators/
java generators/NoiseWaveIrisUniforms.java > \
	pipeline/uniforms/water/surface_noise_waves.properties
java generators/CausticIrisUniforms.java > \
	pipeline/uniforms/water/caustics_noise.properties
