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

static const float SRGB_GAMMA = 2.2;

float SrgbToLinear(float srgb) {
	return pow(srgb, SRGB_GAMMA);
}

float3 SrgbToLinear(float3 srgb) {
	return pow(srgb, float3(SRGB_GAMMA));
}

float3 LinearToSrgb(float3 rgb) {
	return pow(rgb, float3(1.0 / SRGB_GAMMA));
}

float4 SrgbToLinear(float4 srgb) {
	return float4(pow(srgb.rgb, float3(SRGB_GAMMA)), srgb.a);
}

float4 LinearToSrgb(float4 rgb) {
	return float4(pow(rgb.rgb, float3(1.0 / SRGB_GAMMA)), rgb.a);
}
