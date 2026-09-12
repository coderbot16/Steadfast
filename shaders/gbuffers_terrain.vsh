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
#define HAS_WAVING_FOLIAGE
// TODO: Create Aeronautics uses the terrain shader, but passes a non-identity
//       normal matrix, and we have no easy way to detect or differentiate, so
//       we have to turn off this optimization.
//#define CREATE_AERONAUTICS_COMPATIBILITY
#ifndef CREATE_AERONAUTICS_COMPATIBILITY
	#define NORMALS_ARE_IN_WORLD_SPACE
#endif
#include "/program/world/lit.vsh"
