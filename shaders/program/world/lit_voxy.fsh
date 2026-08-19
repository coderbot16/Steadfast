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

// With Voxy, we can assume that textureGather is available, as the shader we
// are patched into requires GLSL version 460 (OpenGL 4.6), but textureGather is
// core (not an extension) in OpenGL 4.0. This is nice, because we otherwise
// can't actually explicitly enable an extension in Voxy because it requires
// an #extension directive in the middle of the shader.
#define MC_GL_ARB_texture_gather

#define EXTERNALLY_DEFINED_UNIFORMS
#define NO_HELD_BLOCK_LIGHTING

// Water absorption configuration, has wide-reaching impacts across the codebase
// Uniforms: none
#include "/environment/water/absorption_settings.glsl"

// Water absorption, if being done with the refraction-assisted method.
// Uniforms: none
#include "/environment/water/absorption.glsl"

// Whether to freeze animations (useful for testing).
//#define FREEZE_ANIMATION_TIMER
#ifdef FREEZE_ANIMATION_TIMER
	float timeSeconds = 500.0;
#else
	float timeSeconds = frameTimeCounter;
#endif

#include "/environment/materialIDs.glsl"

#include "/environment/lighting/diffuse.glsl"

layout(location = 0) out vec4 out0;
layout(location = 1) out float out1;

#if defined(TRANSLUCENT)
	#define opaqueDepth vxDepthTexOpaque
	#define projectionMatrix vxProj
	#define inverseProjectionMatrix vxProjInv

	// Sky reflection
	#include "/environment/fog.glsl"
	#include "/environment/sky.glsl"

	#include "/environment/lighting/translucent.glsl"
#elif defined(FANCY_TRANSLUCENTS)
	layout(location = 2) out vec4 out2;
#endif

// sRGB to Linear RGB
// Uniforms: none
#include "/lib/srgb.glsl"

#include "/lib/encoding/lightmap.glsl"

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	float normalSign = (float(int(parameters.face) & 1) * 2.0 - 1.0);
	vec3 worldNormal = normalSign * vec3(
		uint((parameters.face >> 1) == 2),
		uint((parameters.face >> 1) == 0),
		uint((parameters.face >> 1) == 1)
	);

	// Experimentally collected for normal terrain
	//
	// Normal -X -> Tangent +Z = vec3( 0.0, 0.0,  1.0)
	// Normal +X -> Tangent -Z = vec3( 0.0, 0.0, -1.0)
	// Normal -Y -> Tangent +X = vec3( 1.0, 0.0,  0.0)
	// Normal +Y -> Tangent +X = vec3( 1.0, 0.0,  0.0)
	// Normal -Z -> Tangent -X = vec3(-1.0, 0.0,  0.0)
	// Normal +Z -> Tangent +X = vec3( 1.0, 0.0,  0.0)
	vec3 worldTangent = vec3(
		abs(worldNormal.y) + worldNormal.z,
		0.0,
		-1.0 * worldNormal.x
	);

	// Experimentally collected for normal terrain
	// Horizontal normal -> Bitangent -Y = vec3(0.0, -1.0, 0.0)
	// Normal -Y -> Bitangent -Z
	// Normal +Y -> Bitangent +Z
	vec3 worldBitangent = vec3(
		0.0,
		(parameters.face >> 1) == 0 ? 0.0 : -1.0,
		worldNormal.y
	);

	vec4 surfaceColor =
		SrgbToLinear(parameters.sampledColour * parameters.tinting);
	uint materialID = DecodeMaterialID(parameters.customId);

	// Geometry selectors are not applicable on Voxy terrain right now, as the
	// only selector is for diagonal geometry, which is not possible in Voxy.
	if (materialID > 0xFu) {
		materialID = 0u;
	}

	float skyLight = LightMapToLight(parameters.lightMap.y);

	vec4 fragmentColor = vec4(DiffuseLighting(SurfaceFragment(
		// The linear RGB color of the surface at this position, including all
		// AO and tinting.
		surfaceColor.rgb,
		// The predefined material ID of this fragment.
		materialID,
		// The normal vector of the surface where this fragment is, in
		// world-space.
		worldNormal,
		// The sky light strength, where 1 is light level 15 and 0 is no light.
		skyLight,
		// The block light strength, where 1 is light level 15 and 0 is no
		// light.
		LightMapToLight(parameters.lightMap.x),
		// The held light strength, where 1 is light level 15 and 0 is no light.
		0.0
	)), surfaceColor.a);


	#if defined(TRANSLUCENT)
		vec3 ndcPos = gl_FragCoord.xyz * vec3(windowToNdc, 2.0) - 1.0;
		vec4 viewPosH = inverseProjectionMatrix * vec4(ndcPos, 1.0);
		vec3 viewPos = viewPosH.xyz / viewPosH.w;
		vec3 cameraRelativePos =
			(gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

		if (materialID == WATER) {
			fragmentColor = vec4(0.0);
		}

		float reflectionStrength = materialID == WATER ? 1.0 : 0.0;

		fragmentColor = TranslucentLighting(
			fragmentColor,
			worldNormal,
			mat3(
				worldTangent,
				worldBitangent,
				worldNormal
			),
			cameraRelativePos,
			viewPos,
			reflectionStrength,
			skyLight,
			materialID
		);
	#endif

	out0 = fragmentColor;
	out1 = skyLight;

	#if defined(FANCY_TRANSLUCENTS) && !defined(TRANSLUCENT)
		out2 = fragmentColor;
	#endif
}