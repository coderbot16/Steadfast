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

// Include guard to permit every file that requires this function to include it,
// independent of other files.
#if !defined(BAYER8_ALREADY_INCLUDED)
#define BAYER8_ALREADY_INCLUDED

// Based on "Ordered Dithering (Bayer)" by Tech_
// https://www.shadertoy.com/view/7sfXDn
float Bayer2(float2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float Bayer4(float2 a) {
	return Bayer2(0.5 * a) * 0.25 + Bayer2(a);
}

// NB: The result isn't actually in the range of 0 to 1 but rather 0 to 1.3125.
// 
// Mathematically equivalent to:
//
// return dot(
// 	vec3(
// 		0.0625,
// 		0.25,
// 		1.0
// 	),
// 	vec3(
// 		Bayer2(a * 0.25),
// 		Bayer2(a * 0.5),
// 		Bayer2(a)
// 	)
// );
float Bayer8(float2 a) {
	return (Bayer4(0.5 * a) * 0.25 + Bayer2(a)) / 1.3;
}

#endif
