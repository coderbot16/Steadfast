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

// "Building an Orthonormal Basis, Revisited"
// https://jcgt.org/published/0006/01/01/
//
// Modified to swap Y/Z as most water faces are either mostly vertical or
// entirely horizontal, the discontinuity as we go from +Y to -Y is not
// noticeable.
//
// I previously tried setting worldTangent to the vector rejection of the down
// vector from the normal (or up vector when the normal pointed down), but the
// below method doesn't look visually different, lacks the same discontinuities
// caused by special casing vertical faces, and is faster due to avoiding
// normalization!
//
// Details on vector rejection: https://en.wikipedia.org/wiki/Vector_projection
void WaterTBN(float3 normal, out float3 tangent, out float3 binormal) {
	float sign = normal.y >= 0.0 ? 1.0 : -1.0;
	float a = -1.0 / (sign + normal.y);
	float b = normal.x * normal.z * a;

	tangent = float3(
		1.0 + sign * normal.x * normal.x * a,
		-sign * normal.x,
		sign * b
	);

	binormal = float3(
		b,
		-normal.z,
		sign + normal.z * normal.z * a
	);
}

#define BASIC 0
#define NOISE 1
// The water surface model. Each option has varying quality and performance.
#define WATER_SURFACE NOISE // [BASIC NOISE]
#if WATER_SURFACE == NOISE
	#include "surface_noise.slang"
	#define WATER_PARALLAX
#else /* WATER_SURFACE == BASIC */
	#include "surface_basic.slang"
	// TODO: Support water parallax on the basic water surface
#endif

#ifdef WATER_PARALLAX
	#include "parallax.slang"

	// Distance in meters to apply parallax mapping to the water surface.
	#define WATER_PARALLAX_DISTANCE 48.0 // [8.0 16.0 24.0 32.0 48.0 64.0]
#endif

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	// These are the view-space vectors that represent a one-pixel offset along
	// the X and Y axis in screen-space, respectively.
	uniform float3 viewOffsetPixelX;
	uniform float3 viewOffsetPixelY;
#endif

// This function is a method of computing the partial derivative of the world
// space position with respect to the screen space position (screen space
// partial derivative) using triangle intersections and the finite-difference
// method, but without requiring the calculations of a neighboring fragment.
//
// This technique is strongly inspired by the following paper:
//
//   Christopher A. Burns and Warren A. Hunt, The Visibility Buffer:
//   A Cache-Friendly Approach to Deferred Shading, Journal of Computer Graphics
//   Techniques (JCGT), vol. 2, no. 2, 55-69, 2013
//   Available online http://jcgt.org/published/0002/02/04/
//
// However, this implementation is a simpler variant that excludes the logic
// required for vertex attribute interpolation and fetching vertex positions,
// in favor of constructing a "hypothetical triangle" for the purpose of the
// intersection test that simplifies the resulting derivative calculations.
void dWorldPosdxdy(
	float4x4 gbufferModelView,
	// View position of the fragment
	float3 viewPos,
	float3 worldTangent,
	float3 worldBinormal,
	// ddx(worldPos), computed with the finite distance method
	out float3 ddxWorldPos,
	// ddy(worldPos), computed with the finite distance method
	out float3 ddyWorldPos
) {
	// Form a triangle in view-space with edge lengths of 1 with a plane that is
	// parallel to and overlapping the triangle plane that this fragment came
	// from. This "hypothetical triangle" is just to make our calculations more
	// straightforward but does not change their results.
	float3 edge1 = mul(gbufferModelView, float4(worldTangent, 0.0)).xyz;
	float3 edge2 = mul(gbufferModelView, float4(worldBinormal, 0.0)).xyz;

	// This is the Möller–Trumbore intersection algorithm:
	// https://en.wikipedia.org/wiki/Möller–Trumbore_intersection_algorithm
	//
	// I am summarizing the relevant part of the paper here.
	//
	// Given a triangle with vertices v0, v1, v2, we can define the following:
	//
	// edge1 = v1 - v0
	// edge2 = v2 - v0
	//
	// Then, for a ray with origin O and direction D, the ray distance (t) and
	// barycentric coordinates u and v are given by the following system of
	// equations, with T defined as O - v0:
	//
	//                        [ t ]
	// [ -D, edge1, edge2 ] * [ u ] = T
	//                        [ v ]
	//
	// Per Cramer's Rule, the solution is given by:
	//
	// [ t ]             1              [ det( T, edge1, edge2) ]
	// [ u ] =  --------------------- * [ det(-D,     T, edge2) ]
	// [ v ]    det(-D, edge1, edge2)   [ det(-D, edge1,     T) ]
	//
	// We do not care about the value of t here, and can simplify to:
	//
	//                   1
	// [ u ] =  --------------------- * [ det(-D,     T, edge2) ]
	// [ v ]    det(-D, edge1, edge2)   [ det(-D, edge1,     T) ]
	//
	// We trace from an origin of (0, 0, 0), so the vector from viewPos to the
	// origin is just -viewPos. Because the negatives cancel out below, we can
	// just treat the vector from the center vertex (v0, viewPos) to the origin
	// as viewPos. Therefore, we can set T as viewPos.
	//
	// From linear algebra:
	// det(A, B, C)
	// = dot(cross(A, B), C)
	// = -dot(cross(A, C), B)
	// = -dot(cross(C, B), A)
	//
	// Expanding these determinants as cross products:
	//
	//                   1
	// [ u ] =  --------------------------- * [ dot(cross(D, edge2), viewPos) ]
	// [ v ]    dot(cross(D, edge2), edge1)   [ dot(cross(viewPos, edge1), D) ]
	//
	// To avoid repetition, we introduce two variables:
	//
	// q = cross(viewPos, edge1)
	// p = cross(D, edge2)
	float3 q = cross(viewPos, edge1);

	// These directions set up the intersection calculation we are using to find
	// the screen-space partial derivatives. We trace towards the triangle in
	// the direction of the current fragment, but then add one pixel up and one
	// pixel to the side for each trace.
	float3 incident = normalize(viewPos);
	float3 offsetX = incident + viewOffsetPixelX;
	float3 offsetY = incident + viewOffsetPixelY;

	// Intersection for the trace along the screen in the X direction, in
	// barycentric coordinates.
	float3 pdx = cross(offsetX, edge2);
	float invdetdx = 1.0f / dot(pdx, edge1);
	float dudx = invdetdx * dot(pdx, viewPos);
	float dvdx = invdetdx * dot(offsetX, q);

	// Intersection for the trace along the screen in the Y direction, in
	// barycentric coordinates.
	float3 pdy = cross(offsetY, edge2);
	float invdetdy = 1.0f / dot(pdy, edge1);
	float dudy = invdetdy * dot(pdy, viewPos);
	float dvdy = invdetdy * dot(offsetY, q);

	// Transform the screen-space derivative from barycentric coordinates back
	// to world-space. The first barycentric coordinate is the movement toward
	// the first vertex, and the second is the movement towards the second
	// vertex.
	ddxWorldPos = worldTangent * dudx + worldBinormal * dvdx;
	ddyWorldPos = worldTangent * dudy + worldBinormal * dvdy;
}
