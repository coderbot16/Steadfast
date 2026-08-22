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

#ifdef MC_GL_ARB_texture_gather
	// If textureGather is available, use that to fade away caustics, otherwise
	// we will fall back to texelFetch.
	#define CAUSTICS_FADE_METHOD_GATHER
#endif

// Just for shadow mapping constants
// Uniforms: none
#include "/lib/distort.glsl"

// Enable PCF (shadowHardwareFiltering) on both shadowmaps
const bool shadowHardwareFiltering0 = true;
const bool shadowHardwareFiltering1 = true;

// Whether to enable fancy translucent effects. When disabled, translucents are
// rendered with the same shading as solids.
#define FANCY_TRANSLUCENTS 
#ifdef FANCY_TRANSLUCENTS
	uniform sampler2DShadow shadowtex1;
	#define shadowSampler shadowtex1

	// Whether underwater terrain will have an antimated water caustics overlay.
	#define WATER_CAUSTICS
#else
	uniform sampler2DShadow shadowtex0;
	#define shadowSampler shadowtex0
#endif

#if defined(WATER_CAUSTICS)
	uniform sampler2D shadowcolor0;
	uniform float causticsFade;
	#define shadowWaterSampler shadowcolor0
#endif

// Higher shadow map resolutions give sharper shadows at the expense of
// perfomance.
const int shadowMapResolution = 1536; // [1024 1536 2048 3072 4096]

// Render distance of the shadow map, in blocks. No objects outside of this
// distance cast or receive real-time shadows.
const float shadowDistance = 160; // [32 48 64 80 96 112 128 144 160 192 256]
const float shadowDistanceRenderMul = 1.0;
const float entityShadowDistanceMul = 0.25;

// Samples the shadow map additional times to soften shadows.
#define SOFTER_SHADOWS
#ifdef SOFTER_SHADOWS
	float SampleShadows(vec3 shadowPos) {
		// Controls softness and pixelation of shadows
		#define SHADOW_SOFTNESS 0.5 // [0.05 0.10 0.25 0.33 0.5 0.66]
		const float spread = SHADOW_SOFTNESS / shadowMapResolution;

		// Make 4 taps on the shadowmap, where each tap is itself a hardware
		// accelerated 2x2 PCF tap, ending up with sampling up to 16 different
		// texels in the shadowmap. However, at low values of shadow softness,
		// the taps overlap.
		vec3 tap1 = vec3(shadowPos.xy + vec2(spread, spread), shadowPos.z);
		vec3 tap2 = vec3(shadowPos.xy + vec2(-spread, spread), shadowPos.z);
		vec3 tap3 = vec3(shadowPos.xy + vec2(spread, -spread), shadowPos.z);
		vec3 tap4 = vec3(shadowPos.xy + vec2(-spread, -spread), shadowPos.z);

		return 0.25 * texture(shadowSampler, tap1)
		     + 0.25 * texture(shadowSampler, tap2)
		     + 0.25 * texture(shadowSampler, tap3)
		     + 0.25 * texture(shadowSampler, tap4);
	}
#else
	float SampleShadows(vec3 shadowPos) {
		return texture(shadowSampler, shadowPos);
	}
#endif

#ifdef WATER_CAUSTICS
#include "/environment/water/caustics_noise.glsl"

float SampleWaterCaustics(
	float shadowSample,
	float withinShadowMap,
	vec2 shadowPos,
	vec3 cameraRelativePos
) {
	// Distance in meters to apply parallax mapping to the water surface.
	#define WATER_CAUSTICS_DISTANCE 48.0 // [8.0 16.0 24.0 32.0 48.0 64.0]

	// This method of water caustics depends on the shadow map for water depth
	// information, which is not available outside of the shadow map render
	// distance.
	//
	// In addition, rendering caustics far away from the player is still costly
	// and unnoticable after a certain distance, so it is a good optimization to
	// give them a render distance limit.
	float causticsStrength = causticsFade * withinShadowMap;
	causticsStrength *= 1.0 - smoothstep(
		WATER_CAUSTICS_DISTANCE,
		WATER_CAUSTICS_DISTANCE + 4.0,
		length(cameraRelativePos));

	if (causticsStrength < 0.0001) {
		return shadowSample;
	}

	#ifdef CAUSTICS_FADE_METHOD_GATHER
		// Water height values are discrete and not meant to be interpolated
		// linearly. This is normally not significant, however, if there is
		// something casting a shadow on the water at a given texel in the
		// shadow map, if we only fetched that texel we would be missing water
		// depth data since the water would not be drawn & write the water depth
		// value.
		//
		// Using textureGather allows us to access the height values of
		// neighboring texels, so we can use a gradual, almost un-noticeable
		// fade-out.
		vec4 encodedWaterHeights = textureGather(shadowWaterSampler, shadowPos);
		float encodedWaterHeight = min(
			min(encodedWaterHeights.x, encodedWaterHeights.y),
			min(encodedWaterHeights.z, encodedWaterHeights.w)
		);
	#else
		// If textureGather is not available, then just use nearest-neighbor
		// sampling, and a less ideal fade-out down below.
		ivec2 texel = ivec2(shadowMapResolution * shadowPos);
		float encodedWaterHeight = texelFetch(shadowWaterSampler, texel, 0).r;
	#endif

	// Decode the water height and calculate the distance between this fragment
	// and the water surface. Note that this will clamp out at +/- 1024 blocks
	// above or below the camera, but because we limit water caustics to much
	// more nearby than that, this is not an issue.
	//
	// See: shadow.fsh for the encoding. TODO: Make this a common function
	float waterYCameraRelative = (1.0 - 2.0 * encodedWaterHeight) * 1024.0;
	float causticsWaterDepth = waterYCameraRelative - cameraRelativePos.y;

	// Smoothly fade out caustics near the water surface (over 1/16th of a
	// block, aka 1 visible block pixel with default textures) to avoid a
	// visible, abrupt transition.
	causticsStrength *= smoothstep(0.0, 1.0 / 16.0, causticsWaterDepth);

	// Smoothly fade out caustics at the edges of shadows. This is necessary
	// because we lose water depth information in shadowed areas, so we need to
	// fade them away in areas where we still do have water depth information.
	causticsStrength *= smoothstep(
		#ifdef CAUSTICS_FADE_METHOD_GATHER
			// If we are using textureGather, we can still calculate the water
			// height even with just one of 4 texels not in shadow (25%), so we
			// can smoothly fade from 25% coverage to 75% coverage.
			0.25,
			0.75,
		#else
			// However, with texelFetch, we can only calculate the water height
			// when the immediate texel is not in shadow, even if its neighbors
			// are in shadow. While the true resulting range SHOULD be 0.75 to
			// 1.0, I brought the lower bound down a bit to make the transition
			// look less abrupt.
			0.675,
			1.0,
		#endif
		shadowSample
	);

	vec3 worldPos = cameraRelativePos + cameraPosition;
	float caustics = WaterCaustics(worldPos, timeSeconds);
	return shadowSample * max(0.0, 1.0 + causticsStrength * caustics);
}

#endif /* WATER_CAUSTICS */

float ShadowMapping(
	uint materialID,
	float shadowSample,
	bool subsurfaceScatter,
	float directLightStrength,
	vec3 shadowPos,
	vec3 cameraRelativePos,
	float ao
) {
	// The culling enabled by shadowDistanceRenderMul takes the form of an
	// axis-aligned box centered on the camera. As a result, we evaluate the
	// distance of a fragment as the maximum along any axis to ensure we stay
	// within the bounding box.
	float boxDistance = max(abs(cameraRelativePos.x),
		max(abs(cameraRelativePos.y), abs(cameraRelativePos.z)));

	// Fade in static shadows first (5 - 10 blocks away from the bounds of the
	// shadow distance)...
	float staticShadowStrength = smoothstep(
		shadowDistance - 10.0,
		shadowDistance - 5.0,
		boxDistance);
	shadowSample = 1.0 - staticShadowStrength * (1.0 - shadowSample);

	// Then fade out real-time shadows once static shadows are fully faded in
	// (5 or fewer blocks from the bounds).
	float withinShadowMap = 1.0 - smoothstep(
		shadowDistance - 5.0,
		shadowDistance,
		boxDistance);

	// Only sample the shadow map if we are within the real-time shadowing
	// bounding box.
	if (withinShadowMap < 0.0001) {
		return directLightStrength * shadowSample;
	}

	// When applying real-time shadowing, if this surface has subsurface
	// scattering enabled, then modify the direct light strength accordingly.
	//
	// We do not use 1.0 here just because that is a bit too bright. This is as
	// if the foliage affected by SSS is facing just a little bit away from the
	// light at all times.
	//
	// More specifically, cos(pi/4) ~= 0.7071, ie, a 45 degree angle with the
	// light.
	if (subsurfaceScatter) {
		directLightStrength = mix(directLightStrength, 0.7071, withinShadowMap);
	}

	float shadowMapSample = mix(1.0, SampleShadows(shadowPos), withinShadowMap);

	if (subsurfaceScatter) {
		shadowMapSample *= ao;
	} else {
		#define DIRECT_LIGHT_AMBIENT_OCCLUSION 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
		shadowMapSample *= mix(1.0, ao, DIRECT_LIGHT_AMBIENT_OCCLUSION);
	}

	shadowSample = min(shadowSample, shadowMapSample);

	#ifdef WATER_CAUSTICS
		// Do not apply caustics to water itself.
		// Note: Caustics can be enabled even if FANCY_TRANSLUCENTS
		// is not, though that is an odd configuration to use.
		if (materialID != WATER) {
			shadowSample = SampleWaterCaustics(
				shadowSample,
				withinShadowMap,
				shadowPos.xy,
				cameraRelativePos);
		}
	#endif

	return directLightStrength * shadowSample;
}
