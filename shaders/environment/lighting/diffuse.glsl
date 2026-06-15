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

// This is a high-performance lighting model that delivers pleasing visuals
// while requiring only shadow mapping. By carefully tweaking ambient lighting,
// a look similar to indirect lighting can be achieved without the associated
// complexity and performance cost.

// Whether to use the new direct lighting model with atmospheric scattering.
#define MINISHITA_LIGHTING
#ifdef MINISHITA_LIGHTING
	// Actual effect is in shaders.properties
#endif

#define STEADFAST BY_CODERBOT // Authorship attribution. [BY_CODERBOT]

#define FANTASY 0
#define SEMI_NATURAL 1
#define RETRO 2

// The style of direct and ambient sky lighting to use during the day.
#define DAY_SKY_LIGHTING SEMI_NATURAL // [FANTASY SEMI_NATURAL RETRO]

// The style of direct and ambient sky lighting to use at night.
#define NIGHT_SKY_LIGHTING FANTASY // [FANTASY SEMI_NATURAL RETRO]

// Whether real-time shadows using shadow mapping are enabled for entities.
#define REAL_TIME_ENTITY_SHADOWS
#ifdef REAL_TIME_ENTITY_SHADOWS
	// Actual effect is in shaders.properties
#endif

// Whether real-time shadows using shadow mapping are enabled for block entities
// (chests, beds, etc).
// #define REAL_TIME_BLOCK_ENTITY_SHADOWS
#ifdef REAL_TIME_BLOCK_ENTITY_SHADOWS
	// Actual effect is in shaders.properties
#endif

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform vec3 minAmbient;
	uniform vec3 skyAmbient;
	uniform float blocklightSuppression;
	uniform float nightVision;
#endif

float AmbientStrength(float worldDirY) {
	// Mimic vanilla directional lighting by varying the strength of ambient
	// lighting based on whether the face is facing upwards, downwards, or
	// sideways.
	return (0.67 + worldDirY * 0.33);
}

vec3 AmbientSkyLighting(float skyLightStrength, float ambientStrength) {
	// x^3 falloff to have a more even transition
	float skyLight = pow(skyLightStrength, 3);

	// Whether sky light intensity should be directly based on the face
	// direction.
	#define DIRECTIONAL_SKYLIGHT_SHADING 

	// Fade sky ambient lighting away as sky light fades away, as that helps us
	// rather convincingly approximate indirect lighting. But, have a "minimum"
	// ambient color so that caves are not completely black.
	#ifdef DIRECTIONAL_SKYLIGHT_SHADING
		return ambientStrength * (minAmbient + skyLight * skyAmbient);
	#else
		return ambientStrength * minAmbient + skyLight * skyAmbient;
	#endif
}

// Desaturate terrain that receives moonlight without being lit by block light.
#define NIGHT_DESATURATION_EFFECT 
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	#ifdef NIGHT_DESATURATION_EFFECT
		uniform float desaturationIntensity;
	#else
		const float desaturationIntensity = 0.0;
	#endif
#endif

// Whether blocks in your hand should dynamically cast light on surroundings.
#if !defined(NO_HELD_BLOCK_LIGHTING)
	#define HELD_BLOCK_LIGHTING 
#endif

#ifdef HELD_BLOCK_LIGHTING
	#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
		uniform float heldLightBaseStrength;
		uniform float heldLightSuppression;
	#endif
#else
	const float heldLightBaseStrength = 0.0;
	const float heldLightSuppression = 0.0;
#endif

float HeldLightStrength(vec3 cameraRelativePos) {
	// This is an attempt to model held light strength off of the same scale as
	// Minecraft block lights use.
	//
	// Previously, this used the inverse-square law, but this lead to held light
	// having an impact very far away from the player, which felt implausible.
	//
	// Implicitly, the light position is centered on the camera. This might not
	// be desired, so to adjust, simply subtract the light position from the
	// desired light position.
	float fragDistance = length(cameraRelativePos);
	return clamp(heldLightBaseStrength - fragDistance / 15.0, 0.0, 1.0);
}

// Desaturate terrain that receives moonlight without being lit by block light.
float NightDesaturation(float skyLight, float blockLight) {
	#ifndef NIGHT_DESATURATION_EFFECT
		return 0.0;
	#endif

	// Nighttime desaturation is applied to surfaces that are exposed to the sky
	// but not subject to block light.
	return desaturationIntensity * skyLight * (1.0 - blockLight);
}

#ifdef NIGHT_DESATURATION_EFFECT
	#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
		uniform vec3 desaturationColor;
	#endif

	vec3 Desaturate(vec3 color, float desaturation) {
		// Rec601 luma from https://en.wikipedia.org/wiki/Luma_(video)
		// TODO: Use luminance, luma is for sRGB only.
		float luma = dot(color, vec3(0.299, 0.587, 0.114));

		// Fade the pre-lighting color to the desaturation color
		return mix(color, luma * desaturationColor, desaturation);
	}
#endif

#include "blocklight_color.glsl"
#define BLOCKLIGHT_LUMINANCE 2.0 // [0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.25 2.5 2.75 3.0 3.25 3.5 3.75 4.0]

vec3 BlockLighting(float skyLight, float blockLight, float heldLight) {
	const vec3 blocklightColor = BLOCKLIGHT_COLOR * BLOCKLIGHT_LUMINANCE;

	// Give block lighting a strong but visually appealing falloff.
	float blockLightIntensity = pow(blockLight, 4.0);
	float heldLightIntensity = pow(heldLight, 4.0);

	// Apply block light suppression (see details in shaders.properties).
	//
	// sqrt(skyLight) makes the suppression affect most areas impacted
	// by skylight.
	blockLightIntensity *= 1.0 - sqrt(skyLight) * blocklightSuppression;

	// For held light, we also suppress it if the player is standing in sky
	// light, so that suppressed light held by the player doesn't still get
	// cast into a cave or dark area nearby.
	float heldLightSkyLight = sqrt(max(skyLight, heldLightSuppression));
	heldLightIntensity *= 1.0 - heldLightSkyLight * blocklightSuppression;

	// This method of combining held light and block light avoids weird lines
	// where the lights intersect.
	return blocklightColor * min(1.0, blockLightIntensity + heldLightIntensity);
}

// The returned color is the adjusted block lighting of this fragment, and the
// alpha is the emissiveness for bloom and similar effects.
vec4 EmissiveDetection(vec3 blockLighting, uint materialID, vec3 surfaceColor) {
	if (materialID == EMITTER_MAGIC) {
		// This material applies to crying obsidian and the nether portal, this
		// is a way of isolating the "tears" out of crying obsidian without
		// impacting nether portals.
		bool magic = dot(surfaceColor, vec3(2.5, -10.0, 5.0)) > 1.0;
		bool glowstone = dot(surfaceColor, vec3(6.0, 6.0, -10.0)) > 1.0;

		if (magic || glowstone) {
			// The colors in vanilla crying obsidian tears and nether portals
			// are tuned to its yellowish block lighting, so we need to mimic
			// that to get reasonable colors.
			return vec4(BLACKBODY_4000K * BLOCKLIGHT_LUMINANCE, 1.0);
		}
	}

	// TODO
	// bool torch = dot(surfaceColor, vec3(2.0, 0.0, 0.0)) > 1.0;

	return vec4(blockLighting, 0.0);
}

// Tilt the path of the sun sideways. This is a standard shader effect that
// makes shadows look much better.
const float	sunPathRotation	= -40.0f;

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
		uniform int isEyeInWater;
	#endif

	uniform vec3 directLightSurface;
	uniform vec3 directLightUnderwater;
	uniform vec3 worldLightVector;
#endif

void ApplyWaterAbsorption(
	// Water depth in meters
	float wdepth,
	out vec3 directLightColor,
	inout vec3 lighting,
	vec3 blocklightIndirect
) {
	// Determine the tint needed to simulate water absorption
	vec3 waterAbsorption = WaterAbsorption(wdepth);

	// Fade direct light color to its luminance to avoid odd colors
	// when orange sunrise light goes through water
	directLightColor = mix(directLightSurface, directLightUnderwater, wdepth);

	// Tint lighting (direct and ambient, but not block lighting) by the water
	// absorption
	directLightColor *= waterAbsorption;

	// Near the water surface, make water absorption apply to block light, but
	// do not apply it fully when deep underwater. This is so that lights in
	// underwater bases are not completely overwhelmed by the water absorption,
	// but also so that lights placed near the surface do not appear to pass
	// through the surface and ignore it completely.
	//
	// This is critical because in environments where the sky is not very
	// bright, for example, the semi-natural profile at night, we rely on the
	// water absorption to communicate that there is water. Without this, block
	// light completely breaks the illusion.
	//
	// Even though at maximum depth we still only allow 33% of the block light
	// to pass unaffected by water absorption, the original color of the block
	// light is visible just darker than usual, as at maximum depth water
	// absorption eliminates most light.
	float blocklightNotAbsorbed = 0.33 * wdepth;
	lighting += blocklightIndirect * (1.0 - blocklightNotAbsorbed);

	// Apply water absorption and then add in the block light not affected by
	// water absorption.
	lighting *= waterAbsorption;
	lighting += blocklightIndirect * blocklightNotAbsorbed;
}

struct SurfaceFragment {
	#if defined(REAL_TIME_SHADOWS)
		vec3 cameraRelativePos;
		// The projected shadow map position to sample from.
		//
		// X and Y are coordinates in the shadow map texture, and Z is the
		// depth value to compare the sampled shadow depth against to
		// determine to what extent the fragment is or is not in shadow.
		vec3 shadowPos;
	#endif
	// The linear RGB color of the surface at this position, including all AO
	// and tinting.
	vec3 surfaceColor;
	// The predefined material ID of this fragment.
	uint materialID;
	// The normal vector of the surface where this fragment is, in world-space.
	vec3 worldNormal;
	// The sky light strength, where 1 is light level 15 and 0 is no light.
	float skyLight;
	// The block light strength, where 1 is light level 15 and 0 is no light.
	float blockLight;
	// The held light strength, where 1 is light level 15 and 0 is no light.
	float heldLight;
};

float DirectLighting(SurfaceFragment fragment, bool subsurfaceScatter) {
	// Derive the direct lighting contribution (directLightStrength), which for
	// most surfaces is Lambertian:
	//
	// - Only faces directly facing the light source receive the full intensity
	// - Faces gradually darken as the angle between them and the light
	//   approaches 90 degrees
	// - Faces that are facing away from the light receive none of the light
	float directLightStrength = dot(fragment.worldNormal, worldLightVector);

	// Foliage and glass diverge from the pure Lambertian lighting model to
	// account for their subsurface scattering, which lets sunlight partially
	// pass through the foliage surface.
	if (subsurfaceScatter) {
		// The direct light strength is overridden in the shadow-mapping code to
		// 0.7071 (~= cos(pi/4)) within the shadow map for materials with
		// subsurface scattering.
		//
		// Outside of the shadow map, that would be too bright, so we darken
		// based on direction like so:
		if (fragment.materialID == LEAVES) {
			directLightStrength = directLightStrength * 0.50 + 0.50;
		} else {
			directLightStrength = directLightStrength * 0.35 + 0.65;
		}
	} else if (fragment.materialID == GLASS) {
		// Because glass is transparent / translucent and does not cast shadows,
		// directional shading looks implausible on it, hence we use a different
		// shading model.
		directLightStrength = fragment.worldNormal.y * 0.2071 + 0.5;
	} else {
		#ifndef DIRECTIONAL_SKYLIGHT_SHADING
			// Stylized lighting model:
			//
			// - Faces facing the light source in nearly any way receive the
			//   full light intensity
			// - Faces that approach 90 degrees or more away from the light
			//   rapidly fade to dark
			// - Faces that are facing away from the light receive no light
			directLightStrength = smoothstep(-0.05, 0.05, directLightStrength);
		#else
			directLightStrength = max(directLightStrength, 0.0);
		#endif

		// Only sample the shadow map if this face can receive shadows. Glass
		// and materials with subsurface scattering can always receive shadows.
		if (directLightStrength < 0.0001) {
			return 0.0;
		}
	}

	// Fade away direct lighting based on the sky lighting.
	//
	// Otherwise, the intensity of direct sunlight would otherwise be the same
	// as on land even for deep underwater terrain!
	//
	// In addition, as ambient light brightness decreases as the sky light
	// strength decreases, this is necessary even if we are not underwater, as
	// otherwise darker ambient environments look really odd when the direct
	// light is bright but the ambient light is dark.
	//
	// However, we allow a very very small direct light lower bound to allow for
	// some shadows deep underwater / etc.
	//
	// TODO: This is also the only reason why there is any light in the End.
	directLightStrength *= max(fragment.skyLight, 0.125 / 16.0);

	// This static (lightmap) shadowing technique is a way of treating areas
	// with less than a full skylight level as being shaded. At a distance, it
	// is difficult to notice, and far more visually appealing than terrain
	// without any shadows. The technique and tuned fading factors are from:
	//
	// - Photon Shaders by SixthSurge:
	//   https://github.com/sixthsurge/photon
	//   
	//   File /shaders/include/lighting/shadows.glsl#L56-L59 as of commit
	//   26c2906ee02cc484359b835fba6993d443d45966
	float shadowSample = smoothstep(
		// Everything darker than this will be fully in shadow
		13.5 / 15.0,
		// Everything lighter than this will be fully lit
		14.5 / 15.0,
		fragment.skyLight);

	#ifdef REAL_TIME_SHADOWS
		return ShadowMapping(
			fragment.materialID,
			shadowSample,
			subsurfaceScatter,
			directLightStrength,
			fragment.shadowPos,
			fragment.cameraRelativePos);
	#else
		return directLightStrength * shadowSample;
	#endif
}

vec3 DiffuseLighting(SurfaceFragment fragment) {
	// Part of approximating subsurface scattering
	bool subsurfaceScatter = fragment.materialID == SUBSURFACE_SCATTERING \
		|| fragment.materialID == GROUND_FOLIAGE \
		|| fragment.materialID == LEAVES;

	vec3 lighting = AmbientSkyLighting(
		// When night vision is active, treat everything as fully lit by sky
		// light.
		max(fragment.skyLight, nightVision),
		// Strength of the ambient lighting contribution (sky & min ambient)
		AmbientStrength(subsurfaceScatter ? 0.7071 : fragment.worldNormal.y)
	);

	// Compute the contribution to indirect lighting from block light without
	// immediately applying it. When water absorption is enabled, for gameplay
	// purposes we tweak the amount of water absorption applied to blocklight
	// based on depth to avoid ruining submerged bases.
	vec3 blocklightIndirect = BlockLighting(
		fragment.skyLight,
		fragment.blockLight,
		fragment.heldLight
	);

	float emission = 0.0;

	// Detection of emissive pixels from vanilla-like textures with hardcoded
	// color values.
	#define EMISSIVE_DETECTION
	#ifdef EMISSIVE_DETECTION
		vec4 detection = EmissiveDetection(
			blocklightIndirect,
			fragment.materialID,
			fragment.surfaceColor
		);

		blocklightIndirect = detection.rgb;
		emission = max(float(fragment.blockLight > 0.995), detection.a);

		// TODO: Use emission in bloom
	#endif

	vec3 directLightColor = directLightSurface;

	#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
		// With refraction-assisted water absorption, we need an alternate way
		// to apply water absorption when the viewpoint is itself underwater, as
		// in this case, we can see the underwater terrain without it being
		// behind any refractive surface.
		// 
		// Minecraft helpfully puts water surfaces around glass and similar, so
		// underwater bases in glass domes for example will work fine when
		// applying water absorption just on refraction, but if the view is
		// actually within water, then we can utilize the skylight based water
		// depth to apply absorption.
		//
		// The only difficult part is the transition between above water and
		// underwater. This is because we can be in a state where the bottom of
		// the screen is underwater, even though the center of the screen is
		// above and can see above water. In this case, it is not trivial to
		// tell if any given piece of terrain should receive water absorption.
		//
		// We rectify this with a clever hack that aims to cover the bottom half
		// of the screen with water until the player's eyes are actually
		// underwater, which takes place near the end of the lit vertex shader.
		if (isEyeInWater == 1) {
			// TODO: Water depth calculation copied from
			// /environment/water/absorption_refraction.glsl
			// It should be in a common function
			float waterDepth = (-15.0 / 16.0) * fragment.skyLight + 1.0;

			ApplyWaterAbsorption(
				waterDepth,
				directLightColor,
				lighting,
				blocklightIndirect);
		} else {
			lighting += blocklightIndirect;
		}
	#else
		lighting += blocklightIndirect;
	#endif

	// If the direct light strength is nonzero, add in direct lighting
	// based on sampling the shadow map.
	#if !defined(NEVER_RECEIVES_SHADOWS)
		float directLightStrength = DirectLighting(fragment, subsurfaceScatter);
	#else
		float directLightStrength = 1.0;
	#endif

	lighting += directLightStrength * directLightColor;

	vec3 surfaceColor = fragment.surfaceColor;

	#ifdef NIGHT_DESATURATION_EFFECT
		float desaturation = NightDesaturation(
			fragment.skyLight,
			max(max(fragment.blockLight, emission), fragment.heldLight)
		);

		surfaceColor = Desaturate(surfaceColor, desaturation);
	#endif

	//#define EMISSIVE_DETECTION_DEBUG
	#ifdef EMISSIVE_DETECTION_DEBUG
		lighting *= mix(0.001, 1.0, emission);
	#endif

	return surfaceColor * lighting;
}
