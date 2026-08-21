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
// Whether to enable fancy translucent effects. When disabled, translucents are
// rendered with the same shading as solids.
#define FANCY_TRANSLUCENTS
#ifdef FANCY_TRANSLUCENTS
	#define TRANSLUCENT
#endif
#define AFTER_DEFERRED
#define ALPHA_TEST_CUTOFF 0.0001
#define HAS_AMBIENT_OCCLUSION
#include "/program/world/lit.fsh"
