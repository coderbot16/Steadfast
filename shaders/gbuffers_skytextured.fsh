// Steadfast is a fast and high-quality graphical overhaul for Minecraft (JE)
// Copyright (C) 2026 coderbot
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#version 150 compatibility
#include "/environment/tonemap_settings.glsl"
// The Uchimura and Uncharted 2 tonemaps have a much different white point, so
// for the sun and moon we need a bit of hardcoding per tonemap for now.
#if TONEMAP == TONEMAP_UNCHARTED2
	#define UNLIT_BRIGHTNESS 12.0
#else
	#define UNLIT_BRIGHTNESS 2.0
#endif
#include "/program/world/unlit_sky.fsh"
