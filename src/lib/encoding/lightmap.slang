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

// Decode a lightmap texel coordinate to a scaled 0 to 1 light value / strength.
float LightMapToLight(float lightMap) {
	// As this is a texture coordinate, we need to subtract half of a texel
	// so that it starts from 0.0 instead of the middle of a texel. Otherwise
	// everything will be tinted wih the color of blocklight.
	//
	// Note: min of 0.000000001 due to odd bug when this hits 0.0?
	return clamp((lightMap - (0.5 / 16.0)) * (16.0 / 15.0), 0.000000001, 1.0);
}
