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
#define HAS_BLOCK_ATTRIBUTES
// TODO: Create Aeronautics uses the terrain shader, but passes a non-identity
//       normal matrix, and we have no easy way to detect or differentiate, so
//       we have to turn off this optimization.
// #define NORMALS_ARE_IN_WORLD_SPACE
// Whether to enable fancy translucent effects. When disabled, translucents are
// rendered with the same shading as solids.
#define FANCY_TRANSLUCENTS
#ifdef FANCY_TRANSLUCENTS
	#define TRANSLUCENT
	#define ALLOW_CLIPPING_WATER_TO_COVER_SCREEN
#endif
#include "/program/world/lit.vsh"
