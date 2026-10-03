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

#define float2 vec2
#define float3 vec3
#define float4 vec4
#define double2 dvec2
#define double3 dvec3
#define double4 dvec4
#define bool2 bvec2
#define bool3 bvec3
#define bool4 bvec4
#define int2 ivec2
#define int3 ivec3
#define int4 ivec4
#define uint2 uvec2
#define uint3 uvec3
#define uint4 uvec4

#define float2x2 mat2
#define float2x2 mat2x2
#define float3x2 mat2x3
#define float4x2 mat2x4
#define float2x3 mat3x2
#define float3x3 mat3
#define float3x3 mat3x3
#define float4x3 mat3x4
#define float2x4 mat4x2
#define float3x4 mat4x3
#define float4x4 mat4
#define float4x4 mat4x4

float lerp(float x, float y, float a) {
	return mix(x, y, a);
}

float2 lerp(float2 x, float2 y, float a) {
	return mix(x, y, a);
}

float3 lerp(float3 x, float3 y, float a) {
	return mix(x, y, a);
}

float4 lerp(float4 x, float4 y, float a) {
	return mix(x, y, a);
}

float2 lerp(float2 x, float2 y, float2 a) {
	return mix(x, y, a);
}

float3 lerp(float3 x, float3 y, float3 a) {
	return mix(x, y, a);
}

float4 lerp(float4 x, float4 y, float4 a) {
	return mix(x, y, a);
}

float4 mul(float4x4 m, float4 v) {
	return m * v;
}

float3 mul(float3x3 m, float3 v) {
	return m * v;
}

float3 mul(float3x2 m, float2 v) {
	return m * v;
}

float2 mul(float2x3 m, float3 v) {
	return m * v;
}

#define static

// TODO: This is an escape hatch for when the abstractions above don't work, we
// should sweep all usages and replace it with better approaches.
#define NO_SLANG
