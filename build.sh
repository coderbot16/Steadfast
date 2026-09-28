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

cat pipeline/pipeline.properties \
	pipeline/profiles.properties \
	pipeline/configs.properties \
	pipeline/uniforms/uncategorized.properties \
	pipeline/uniforms/fog.properties \
	pipeline/uniforms/wind.properties \
	pipeline/uniforms/minishita/common.properties \
	pipeline/uniforms/minishita/sky.properties \
	pipeline/uniforms/minishita/lighting.properties \
	pipeline/uniforms/water/caustics_noise.properties \
	pipeline/uniforms/water/surface_noise_waves.properties \
	pipeline/uniforms/core/vectors.properties \
> shaders/shaders.properties

rm -rf shaders/common && cp -pr src/common shaders/common