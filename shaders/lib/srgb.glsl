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

// Standard approximations for converting to and from sRGB.
// 
// See http://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
// for more information. We can do better but 2.2 is good enough.

const float SRGB_GAMMA = 2.2;

float SrgbToLinear(float srgb) {
	return pow(srgb, SRGB_GAMMA);
}

vec3 SrgbToLinear(vec3 srgb) {
	return pow(srgb, vec3(SRGB_GAMMA));
}

vec3 LinearToSrgb(vec3 linear) {
	return pow(linear, vec3(1.0 / SRGB_GAMMA));
}

vec4 SrgbToLinear(vec4 srgb) {
	return vec4(pow(srgb.rgb, vec3(SRGB_GAMMA)), srgb.a);
}

vec4 LinearToSrgb(vec4 linear) {
	return vec4(pow(linear.rgb, vec3(1.0 / SRGB_GAMMA)), linear.a);
}
