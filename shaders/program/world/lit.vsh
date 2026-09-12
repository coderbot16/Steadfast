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

#define REAL_TIME_SHADOWS // Whether real-time shadow mapping is enabled.
#ifndef REAL_TIME_SHADOWS
	#define NEVER_RECEIVES_SHADOWS
#endif

// Water clipping hack for refraction assisted water absorption
#if defined(ALLOW_CLIPPING_WATER_TO_COVER_SCREEN)
	// Water absorption configuration.
	#include "/environment/water/absorption_settings.glsl"

	#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
		// Used for the clipping hack at the bottom for refraction-assisted
		// water absorption.
		uniform int isEyeInWater;

		// Workaround for when the camera is intersecting water but can see some
		// underwater terrain without isEyeInWater reflecting this.
		#define CLIP_WATER_TO_COVER_SCREEN // Clipping hack to cover the screen.
	#endif
#endif

// Note: using #if defined for most of these instead of #ifdef to prevent them
// from being picked up as shader configuration options.
#if defined(HAS_BLOCK_ATTRIBUTES)
	// Block identification
	in vec4 mc_Entity;
	in vec3 at_midBlock;
#endif

#if !defined(COLORWHEEL)
	// The interpolated vertex color directly from the vertex buffer.
	out vec4 tinting;

	// The lightmap texture coordinates, ranging from 0.03125 to 0.96875.
	// The x / "s" component is the block light, and the y / "t" component is
	// the sky light.
	out vec2 lightMap;
#endif

#if !defined(NO_GTEXTURE)
	// The interpolated texture coordinate directly from the vertex buffer.
	out vec2 texcoord;
#endif

#if !defined(NEVER_RECEIVES_SHADOWS)
	// The projected shadowmap position to sample from.
	//
	// X and Y are coordinates in the shadowmap texture, and Z is the
	// depth value to compare the sampled shadow depth against to
	// determine to what extent the fragment is or is not in shadow.
	out vec3 shadowPos;

	// Shadow distortion
	#include "/lib/distort.glsl"

	uniform mat4 shadowProjection;
	uniform mat4 shadowModelView;
	uniform vec3 worldLightVector;
#endif

// Per-face data encoded by EncodePerFace (/lib/encoding/face.glsl)
#include "/lib/encoding/face.glsl"
#include "/environment/materialIDs.glsl"
flat out uint perFace;

#if defined(HAS_WAVING_FOLIAGE)
	#define WAVING_FOLIAGE // Waving foliage (optional but basically free).

	uniform vec3 cameraPosition;

	// WindDisplacement
	#include "/environment/wind.glsl"

	void WaveFoliage(uint materialID, inout vec4 cameraRelativePos) {
		// at_midBlock is the offset to the center of the block.
		// So if these are the top vertices, then the offset to the center
		// will be negative as the center is below these vertices.
		bool topOfFoliage = at_midBlock.y < 0.0;
		bool wavingGroundFoliage = materialID == GROUND_FOLIAGE;
		bool wavingLeaves = materialID == LEAVES;

		if (wavingLeaves || (wavingGroundFoliage && topOfFoliage)) {
			vec3 worldPos = cameraRelativePos.xyz + cameraPosition;
			vec3 displacement = WindDisplacement(worldPos);
			displacement.y = wavingGroundFoliage ? 0.0 : displacement.y;
			cameraRelativePos.xyz += displacement;
		}
	}
#endif

// This is an Iris-exclusive uniform added in Iris 1.6.0 (Minecraft 1.19.4), but
// it is a super convenient way to apply integrated PBR effects to blocks in all
// other scenarios other than terrain rendering. Important, it is consistent,
// so the item will look the same whether it is in the player's hand or on their
// head.
//
// Doing the same with just gbuffers_hand and heldItemId / heldItemId2 is much
// more of a hassle and more difficult to make consistent, and honestly I don't
// feel like trying it when using this uniform is this easy. It's not the end of
// the world if we miss item effects on ancient shader mod versions.
uniform int currentRenderedItemId;

uint FetchMaterialID(vec3 worldNormal) {
	#if defined(HAS_BLOCK_ATTRIBUTES)
		uint materialID = DecodeMaterialID(mc_Entity.x);

		#if defined(TRANSLUCENT) || defined(TRANSLUCENT_LIGHTING)
			if (materialID == GENERIC) {
				// Use a slightly different lighting approximation for
				// translucents, as traditional directional lighting as
				// implemented below looks odd as our translucents don't cast
				// shadows and let a lot of light pass through.
				//
				// For now, use the same lighting as glass by treating all
				// unknown translucents as glass.
				return GLASS;
			}
		#endif

		uint geometrySelector = materialID >> 4u;

		if (geometrySelector == GEOMETRY_HORIZONTAL_DIAGONAL_ONLY) {
			bool horizontal = abs(worldNormal.y) < 0.01;
			bool diag = abs(worldNormal.x) < 0.95 && abs(worldNormal.z) < 0.95;
			
			return horizontal && diag ? materialID & 0xFu : GENERIC;
		}

		return materialID;
	#elif defined(HAS_DH_MATERIAL_ID)
		if (dhMaterialId == DH_BLOCK_LEAVES) {
			return LEAVES;
		} else if (dhMaterialId == DH_BLOCK_WATER) {
			return WATER;
		} else {
			return GENERIC;
		}
	#else
		return DecodeMaterialID(currentRenderedItemId);
	#endif
}

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

vec3 FetchWorldVector(vec3 v) {
	#if defined(NORMALS_ARE_IN_WORLD_SPACE)
		// If gl_Normal is already in world space, then skip two matrix-vector
		// multiplies that are otherwise completely unnecessary!
		return v;
	#else
		// Otherwise, get the view-space normal and then convert to world-space
		// by multiplying with the inverse view matrix. For example, on some
		// versions of Minecraft normals on entities are in view-space, but this
		// is no longer the case with Minecraft 1.21 and up.
		//
		// We pass up on that optimization opportunity since entities are
		// generally not vertex shader bound and mods can do whatever they want,
		// we can really only make the assumption safely on terrain.
		//
		// We simplify the calculation per the following identity:
		//
		// transpose(inverse(gbufferModelViewInverse))
		// = transpose(gbufferModelView)
		//
		// Note that the transpose & mat3 operations are cheap because they are
		// just renaming / excluding variables used for the underlying matrix
		// multiplication.
		vec3 world = transpose(mat3(gbufferModelView)) * (gl_NormalMatrix * v);

		// If the transformed vector and the original vector are approximately
		// the same, then it was probably already in world space. In that case,
		// use the original vector, to avoid numerical precision / instability.
		//
		// This mitigates some weird glitching on the water surface when moving
		// around and with TBN_MATRIX enabled.
		//
		// TODO: Quantitatively test TBN encoding for accuracy & stability
		if (dot(world, v) > 0.9999) {
			return v;
		}

		return world;
	#endif
}

vec3 FetchWorldNormal() {
	return FetchWorldVector(gl_Normal);
}

in vec4 at_tangent;

vec3 FetchWorldTangent() {
	return FetchWorldVector(at_tangent.xyz);
}

bool FetchTangentHandedness() {
	return at_tangent.w > 0.0;
}

#if !defined(NEVER_RECEIVES_SHADOWS)
	vec3 ShadowMapPosition(vec4 cameraRelativePos, vec3 worldNormal) {
		float NdotL = dot(worldNormal, worldLightVector);

		// Shadow bias method inspired by:
		//
		// - Complementary Reimagined by Emin:
		//   https://github.com/ComplementaryDevelopment/ComplementaryReimagined
		//   
		//   File /shaders/lib/lighting/mainLighting.glsl#L150-L154 as of commit
		//   b511bc03e3fd27023d8ea649e8621bb485518c43
		//
		// - Photon by SixthSurge:
		//   https://github.com/sixthsurge/photon
		//   
		//   File /shaders/include/light/distortion.glsl#L31-L47as of commit 
		//   e253cefc5ff1382f5758834a2d293749a814c724
		//
		// We do this a bit differently. I observed that varying the offset
		// along the normal vector is not only necessary, but rather directly
		// related to shadow distortion.

		// First, transform the position using the shadow matrices. We use the
		// same length calculation, but depart by keeping this variable term
		// separate. Multiplying it by 1.5 was a hack necessary to remove acne
		// on far-away mountain tops.
		vec4 shadowViewPosDistort = shadowModelView * cameraRelativePos;
		vec3 shadowPosDistort = (shadowProjection * shadowViewPosDistort).xyz;
		float distanceFactor = 1.5 * length(shadowPosDistort.xy);

		// However, for the fixed term, we decrease it for faces towards the
		// light to prevent artifacts at closer distances where shadows appear
		// out of sync on different sides of blocks.
		distanceFactor += SHADOW_DISTORT_FACTOR * (1.0 - max(NdotL, 0.0));

		// Finally, offset the shadow map sampling position along the surface
		// normal, accounting for distortion effects and the facing. This allows
		// us to have an adaptive shadow bias that gives us the best of both
		// worlds - no acne, but also no peter panning.
		vec4 shadowBias = vec4(worldNormal * distanceFactor, 0.0);

		// Project to NDC space
		vec4 shadowViewPos = shadowModelView * (cameraRelativePos + shadowBias);
		vec3 shadowPos = (shadowProjection * shadowViewPos).xyz;

		// Distort relative to the center of the shadow map
		shadowPos = distort(shadowPos);

		// Viewport transform: convert from (-1, 1) space to (0.0, 1.0) texture
		// space
		shadowPos = shadowPos * 0.5 + 0.5;

		// Very minor fixed depth bias because we have normal depth bias.
		shadowPos.z -= 0.00001;

		return shadowPos;
	}
#endif

void main() {
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

	// This is effectively as if we multiplied with the model matrix, because we
	// do not get the model matrix separate from the model view matrix.
	//
	// gbufferModelView is a misnomer, it is actually just the view matrix. Same
	// with gbufferModelViewInverse - it is the inverse view matrix.
	// 
	// So the inverse of the view matrix times the model view matrix is the
	// model matrix, which gives us camera-relative coordinates.
	vec4 cameraRelativePos = gbufferModelViewInverse * viewPos;

	// Colorwheel passes its own copies of these values and provides them for us
	// in the material shader we evaluate in the fragment shader, so there is no
	// need for us to pass our own copy in this case.
	#if !defined(COLORWHEEL)
		tinting = gl_Color;
		lightMap = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	#endif

	#if !defined(NO_GTEXTURE)
		texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	#endif

	vec3 worldNormal = FetchWorldNormal();
	vec3 worldTangent = FetchWorldTangent();
	bool handedness = FetchTangentHandedness();
	uint materialID = FetchMaterialID(worldNormal);

	// Note: The vertex normal isn't actually guaranteed to be the same for all
	// vertices of a triangle, but this is the case in practice for almost all
	// mods and even Iris makes this assumption. The only case I know of that
	// breaks this assumption is PhysicsMod snow which has smooth normals.
	//
	// TODO: Allow some geometry to have smooth normals (like PhysicsMod snow),
	// I wonder if this could be done with manual interpolation in the fragment
	// shader / barycentrics instead of just giving up and passing in the full
	// normal or even TBN matrix through varyings.
	perFace = EncodePerFace(worldNormal, worldTangent, handedness, materialID);

	#if !defined(NEVER_RECEIVES_SHADOWS)
		shadowPos = ShadowMapPosition(cameraRelativePos, worldNormal);
	#endif

	#ifdef WAVING_FOLIAGE
		WaveFoliage(materialID, cameraRelativePos);
		viewPos = gbufferModelView * cameraRelativePos;
	#endif

	#ifdef LOWER_DISTANT_WATER_HEIGHT
		if (materialID == WATER) {
			// By default, Distant Horizons renders water as a full block. This
			// leads to a more abrupt transition, so this is a hack to lower the
			// distant water faces to the same height as normal water faces.
			cameraRelativePos.y -= 2.0 / 16.0;
			viewPos = gbufferModelView * cameraRelativePos;
		}
	#endif

	// Transform to clip position.
	gl_Position = gl_ProjectionMatrix * viewPos;

	#ifdef CLIP_WATER_TO_COVER_SCREEN
		// This is a fairly novel hack to overcome a minor, but extremely
		// noticeable limitation of our water absorption method.
		//
		//To reiterate, we rely on two methods of applying absorption:
		//
		// 1. When in water, we apply water absorption to everything.
		// 2. When not in water, we apply absorption to everything behind a
		//    refractive water surface.
		//
		// What happens when both are the case? That is, we are half-submerged,
		// with the upper half of the screen viewing above water, and the lower
		// half underwater?
		//
		// (1) will not apply any absorption because we are not actually fully
		//     underwater yet.
		// (2) will not apply absorption to the lower half, because that half of
		//     the screen is not behind a refractive water surface.
		//
		// This otherwise results in a quite visible flash of underwater terrain
		// brightly lit as if outside in broad daylight, before we actually
		// cross below the water surface and apply absorption. This problem
		// affects almost every shader pack, and even vanilla Minecraft. But, it
		// looks way more noticeable than vanilla due to how our lighting works.
		//
		// Try it yourself - run this command and see how nearly every shader
		// pack looks bugged:
		//
		// /tp @p ~ 61.26889 ~ 0 0
		//
		// The reason why this happens is that while we should be able to see a
		// water surface in front of us before we actually hit underwater, that
		// portion of the surface gets hidden by near-plane clipping (and other
		// things) - that is, the surface is behind the 0.05 meter near plane.
		// Unfortunately, while Iris or vanilla Minecraft could utilize depth
		// clamping or some other method to ensure that this does not happen, we
		// cannot really influence clipping from the shader side.
		//
		// Keyword "really" - we still can influence clipping! Essentially, if
		// we are NOT yet underwater, we can detect when this vertex is going to
		// be clipped by the near clipping plane based on the depth (z) of the
		// vertex. If it would be clipped (outside of -1 to 1 in NDC), then we
		// clamp the NDC z-coordinate to -1.0 by setting the clip-space
		// z-coordinate to -w.
		//
		// This gets us some of the way there, but then we have the jagged edges
		// of triangles on screen, as their neighbors were culled due to being
		// off-screen entirely. This gets us to the second part - we move the
		// Y coordinate to very far below the screen, effectively stretching the
		// triangle downwards. As a result, we basically stretch the would-be
		// clipped geometry to cover the whole bottom half of the screen.
		//
		// This does NOT work when the player is looking more than 45 degrees
		// downwards, as in that case the water faces are clipped off screen
		// entirely on the vertical axis. But this is better than nothing!
		// In my personal testing, this fix is good enough that the problem is
		// no longer noticeable, and we basically need to make zero sacrifices
		// in terms of performance (ie, reworking water to use a more expensive
		// and more robust method) or in terms of compatibility (ie, requiring a
		// very specific shader mod version). Sometimes, a well executed hack is
		// just good engineering, and this is one of those times!
		if (materialID == WATER
			// If we are not already in water...
			&& isEyeInWater == 0
			// If we would be clipped due to the depth being too close to the
			// camera...
			&& gl_Position.z < -gl_Position.w
			// But, we would NOT be clipped on the Y axis already in either
			// direction...
			&& abs(gl_Position.y) < abs(gl_Position.w)
			// And if the face is facing upwards...
			&& worldNormal.y > 0.9999
			// And, if flat, this face must also be high enough that it is not
			// just the flat center of flowing water as well.
			//
			// at_midBlock is the distance to the center of the block multiplied
			// by 64. Because the top face of still water is above the center,
			// this is negative as the center of the block is below. So, this
			// actually means: is this vertex more than 23/64th of a block above
			// its center?
			//
			// If you look at still water in vanilla, the surface lies 2 pixels
			// below the top of a nearby solid block. 2/16 is 0.875, which would
			// be 24 / 64 (0.375) + half (0.5). So, 23/64 just allows for some
			// imprecision, but without allowing a still center of flowing water
			// which is below this threshold (3 pixels below, a 20/64 offset).
			&& at_midBlock.y < -23.0
			// Last but not least, the water face must have a normal actually
			// facing us, too. Because we know that worldNormal is (0, 1, 0)
			// or a very close approximation of it, instead of checking the
			// dot product of the world direction (which is cameraRelativePos
			// normalized) with the worldNormal, we can just check the Y value
			// like this.
			&& cameraRelativePos.y < 0.0
		) {
			// Then use clipping to stretch this face downward across the
			// screen, vertically.
			gl_Position.yz = vec2(-1000.0, -gl_Position.w);
		}
	#endif
}
