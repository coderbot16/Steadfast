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
	// This needs to be at the top of the preprocessed shader
	#extension GL_ARB_texture_gather : require
#endif

// Water absorption configuration, has wide-reaching impacts across the codebase
// Uniforms: none
#include "/environment/water/absorption_settings.glsl"

// Water absorption, if being done with the refraction-assisted method.
// Uniforms: none
#include "/environment/water/absorption.glsl"

// Used to covert viewPos to worldPos.
uniform vec3 cameraPosition;

// Water waves and caustics scrolling
uniform float frameTimeCounter;

// Whether to freeze animations (useful for testing).
//#define FREEZE_ANIMATION_TIMER
#ifdef FREEZE_ANIMATION_TIMER
	float timeSeconds = 500.0;
#else
	float timeSeconds = frameTimeCounter;
#endif

#include "/environment/materialIDs.glsl"

#if !defined(NEVER_REALTIME_SHADOWS) && !defined(NEVER_RECEIVES_SHADOWS)
	#define REAL_TIME_SHADOWS // Enables real-time shadows using shadow mapping.
#endif

#if defined(REAL_TIME_SHADOWS)
	#include "/environment/lighting/shadowmap.glsl"
	in vec3 shadowPos;
#endif

#include "/environment/lighting/diffuse.glsl"
#include "/environment/lighting/blocklight_color_detection.glsl"

#if defined(AFTER_DEFERRED)
	#define APPLY_FOG
#endif

#if WATER_ABSORPTION_METHOD != REFRACTION_ASSISTED && !defined(VOXY)
	#define APPLY_FOG
#endif

#if defined(TRANSLUCENT) || defined(APPLY_FOG)
	#include "/environment/fog.glsl"

	// Sky reflection
	#include "/environment/sky.glsl"
#endif

#if defined(TRANSLUCENT) || defined(EXPLICIT_OPAQUE_DEPTH_TEST)
	// Used for SSR tracing and for depth-testing on DH translucents
	uniform sampler2D depthtex1;
#endif

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

// Distant Horizons terrain is rendered with a different projection matrix, and
// we must be aware of it in our transformations.
#if defined(DH_TERRAIN)
	uniform mat4 dhProjection;
	uniform mat4 dhProjectionInverse;
	uniform sampler2D dhDepthTex1;

	// Workaround for an apparent Iris bug:
	//
	// gl_ProjectionMatrixInverse is well-defined with Distant Horizons, but
	// dhProjectionInverse (what you are supposed to use) is not correct.
	#define inverseProjectionMatrix gl_ProjectionMatrixInverse
	#define projectionMatrix gl_ProjectionMatrix
	#define opaqueDepth dhDepthTex1
#else
	// Workaround continues:
	//
	// Naturally, since things couldn't be that simple, 
	// gl_ProjectionMatrixInverse seems to have garbage outside of Distant
	// Horizons passes, but gbufferProjectionInverse is identical.
	#define inverseProjectionMatrix gbufferProjectionInverse
	#define projectionMatrix gbufferProjection
	#define opaqueDepth depthtex1

	#ifdef DISTANT_HORIZONS
		uniform mat4 dhProjection;
		uniform mat4 dhProjectionInverse;
		uniform sampler2D dhDepthTex1;

		// TODO: It seems like this is still not correct and leads to
		//       discontinuities in things like fog between nearby water
		//       reflecting distant terrain and distant terrain reflecting
		//       distant terrain, unfortunately I am not sure how to work around
		//       this.
		#define inverseProjectionMatrixDistant dhProjectionInverse
		#define projectionMatrixDistant dhProjection
		#define opaqueDepthDistant dhDepthTex1
	#endif
#endif

uniform vec2 windowToNdc;

// Note: using #if defined instead of #ifdef to prevent this from being picked
// up as a shader configuration option.
#if defined(TRANSLUCENT)
	#include "/environment/lighting/translucent.glsl"
#endif

#ifdef DISTANT_HORIZONS
	// Needed for stippling between vanilla and distant terrain during the
	// transition between the two near the edge of vanilla render distance.
	uniform float far;
	#include "/lib/bayer8.glsl"
#endif

// sRGB to Linear RGB
// Uniforms: none
#include "/lib/srgb.glsl"

#if !defined(COLORWHEEL)
	// The interpolated vertex color directly from the vertex buffer.
	in vec4 tinting;

	// The lightmap texture coordinates, ranging from 0.03125 to 0.96875.
	// The x / "s" component is the block light, and the y / "t" component is
	// the sky light. The block light will be negative when this face can be
	// emissive.
	in vec2 lightMap;

	// Note: using #if defined instead of #ifdef to prevent this from being
	// picked up as a shader configuration option.
	#if defined(MIX_ENTITY_COLOR)
		// This is an overlay color used when rendering entities in some cases.
		// It has two functions:
		// 
		// 1. Implement the about-to-explode flash on creepers and primed TnT
		//    (white direction of overlay texture)
		// 2. Implement the red hurt flash on damaged entities
		//    (red direction of overlay texture)
		// 
		// However, that is abstracted away from us. All we have to care about
		// is that we have an RGB color, and an interpolation factor from 0.0 to
		// 1.0 (0.0 = no overlay visible, 1.0 = only overlay visible).
		// 
		// File reference on how this relates to the Minecraft concept in Iris:
		// 
		// https://github.com/IrisShaders/Iris
		// Commit: f0f6a27453d44a18e1c655880dca0baf2de03c9a
		// /src/main/java/net/coderbot/iris/pipeline/transform/transformer
		// /AttributeTransformer.java#L139-L229
		uniform vec4 entityColor;
	#endif
#endif

// Note: using #if defined instead of #ifdef to prevent this from being picked
// up as a shader configuration option.
#if !defined(NO_GTEXTURE)
	// The base material (block/entity/etc) texture
	uniform sampler2D gtexture;

	// The interpolated texture coordinate directly from the vertex buffer.
	in vec2 texcoord;
#endif

#define STANDARD 1
#define NONE 2
#define VERTEX_COLOR 3
#define WORLD_POSITION 4
#define WORLD_NORMAL 5
#define SURFACE_COLORS STANDARD // [STANDARD NONE VERTEX_COLOR WORLD_POSITION WORLD_NORMAL]

// Alpha test threshold - any pixels with an alpha less than this will be
// discarded.
#if !defined(ALPHA_TEST_CUTOFF)
	uniform float alphaTestRef;
#else
	#define alphaTestRef ALPHA_TEST_CUTOFF
#endif

#include "/lib/encoding/lightmap.glsl"

// Per-face data encoded by EncodePerFace (/lib/encoding/face.glsl)
#include "/lib/encoding/face.glsl"
flat in uint perFace;

void main() {
	// Transform back from window coordinates to view-space position and world
	// space positions (camera-relative and absolute).
	//
	// It is cheaper to do this transform back from the fragment coordinates in
	// the fragment shader rather than passing these positions as varyings from
	// the vertex shader, as the cost of buffering and interpolating is more
	// expensive than the following matrix math.
	vec3 ndcPos = gl_FragCoord.xyz * vec3(windowToNdc, 2.0) - 1.0;
	vec4 viewPosH = inverseProjectionMatrix * vec4(ndcPos, 1.0);
	vec3 viewPos = viewPosH.xyz / viewPosH.w;
	vec3 cameraRelativePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

	// Distant Horizons translucent terrain needs a manual depth test against
	// the non distant depth buffer.
	//
	// It is rendered after all opaque objects but before translucent normal
	// terrain, but uses the depth buffer for distant terrain.
	#if defined(EXPLICIT_OPAQUE_DEPTH_TEST)
		float opaqueDepth = texelFetch(depthtex1, ivec2(gl_FragCoord), 0).r;

		if (opaqueDepth != 1.0) {
			// Project back to view space from the fragment coordinates
			vec3 ndcPosOpaque = vec3(ndcPos.xy, opaqueDepth * 2.0 - 1.0);
			vec4 ndcPosHOpaque = vec4(ndcPosOpaque, 1.0);
			vec4 viewPosOpaque = gbufferProjectionInverse * ndcPosHOpaque;

			if (viewPosOpaque.z / viewPosOpaque.w > viewPos.z) {
				discard;
				return;
			}
		}
	#endif

	uint materialID = DecodePerFaceMaterialID(perFace);
	vec3 worldNormal = DecodePerFaceWorldNormal(perFace);

	vec4 surfaceColor;
	vec4 sampledColor;

	#if defined(COLORWHEEL)
		vec4 entityColor;
		vec2 lightMap;
		float ignoredAo;

		sampledColor = texture(gtexture, texcoord);

		#if SURFACE_COLORS == VERTEX_COLOR
			sampledColor.rgb = vec3(1.0);
		#endif

		clrwl_computeFragment(
			// Input: the result obtained from sampling gtexture.
			sampledColor,
			// Output: the result of sampledColor times the tinting (vertex 
			// color), with ambient occlusion applied.
			surfaceColor,
			// Output: the final lightmap value, with values ranging from
			// 0.03125 to 0.96875.
			lightMap,
			// Output: the ambient occlusion value, not needed in our case.
			ignoredAo,
			// Output: equivalent to entityColor.
			entityColor);
	#else
		sampledColor = vec4(1.0);
		surfaceColor = tinting;
	#endif

	float skyLight = LightMapToLight(lightMap.y);

	#if defined(TRANSLUCENT)
		// The strenght of sky reflections (separate from terrain reflections)
		// 0.0 to 1.0, this is modulated into the fresnel value.
		// 
		// Only ice and water can reflect the sky / terrain currently.
		//
		// We only enable sky & terrain reflections on faces pointing upwards.
		// This is due to a few factors:
		//
		// - The player view angle is generally horizontal. As a result, when
		//   looking at upwards-facing water surfaces, generally there are
		//   plenty of things in the background to reflct, so upwards-facing
		//   faces look good as a baseline.
		//
		// - When looking at the sides of faces, the screenspace reflections
		//   cannot often actually trace to what the block is reflecting, due to
		//   either there being things in the way or the object-to-be-reflected
		//   simply not being on screen.
		//
		// - Flowing water sides should be rough anyways and should not have
		//   glassy, specular reflections. We do not support rough reflections,
		//   so even if we permitted reflections on the sides of water, it looks
		//   bad.
		//
		// - Reflecting underwater terrain while underwater is OK, but is
		//   not really impactful and not particularly worth our time, so we can
		//   skip it.
		//
		// TODO: Bring back fancy flowing / sideways water
		if (materialID == WATER && worldNormal.y <= 0.9999) {
			materialID = GENERIC;
		}

		// Fade out reflections to zero as the skylight goes away, needed to
		// avoid water being reflective underground which looks bad.
		bool reflective = materialID == WATER || materialID == ICE;
		float reflectionStrength = reflective ? skyLight : 0.0;
	#endif

	// No need for this with Colorwheel as it handles this in its material
	// shader.
	#if !defined(NO_GTEXTURE) && !defined(COLORWHEEL)
		#if defined(TRANSLUCENT)
			if (materialID == WATER) {
				// This alpha value is tuned for clear water but you can
				// increase it for dirtier/murkier water (it might be better to
				// adjust the water absorption though.)
				//
				// Note: When underground, don't tint the water with the sky
				// color.
				
				// Whether to enable a different style water.
				//#define VANILLA_ISH_WATER 
				#ifndef VANILLA_ISH_WATER
					// TODO: Use dedicated water color uniform?
					sampledColor = vec4(1.0);
					surfaceColor.rgb = mix(
						surfaceColor.rgb,
						skyAmbient,
						reflectionStrength);
					surfaceColor.a = 0.25 * (1.0 - reflectionStrength);
				#else
					sampledColor = texture(gtexture, texcoord);
					surfaceColor *= sampledColor;

					// We blend in HDR, meaning that there can be a large
					// difference in brightness between the water surface
					// and the background.
					//
					// To maintain a similar level of perceptual opacity,
					// we need to scale the alpha value accordingly.
					surfaceColor.a *= 0.25;
				#endif
			} else {
		#endif
				sampledColor = texture(gtexture, texcoord);
				surfaceColor *= sampledColor;
		#if defined(TRANSLUCENT)
			}
		#endif
	#endif

	#if SURFACE_COLORS == NONE
		surfaceColor.rgb = vec3(1.0);
	#elif SURFACE_COLORS == VERTEX_COLOR && !defined(COLORWHEEL)
		surfaceColor.rgb = tinting.rgb;
	#elif SURFACE_COLORS == WORLD_POSITION
		// In this case, we only care about the offset of the camera position
		// relative to the block grid. Then, offsetting with the normal vector
		// gives us consistent results for the positions that exactly on the
		// grid.
		vec3 worldPosOffset = fract(cameraPosition) - 0.025 * worldNormal;
		surfaceColor.rgb = fract(cameraRelativePos + worldPosOffset);
	#elif SURFACE_COLORS == WORLD_NORMAL
		surfaceColor.rgb = 0.5 * worldNormal + 0.5;
	#endif

	// TODO: For now, we make all water fully reflective with Distant Horizons
	#if defined(NO_GTEXTURE) && defined(TRANSLUCENT) && defined(DH_TERRAIN)
		materialID = WATER;

		if (materialID == WATER) {
			surfaceColor = vec4(0.0);
			reflectionStrength = 1.0;
		}
	#else

	// Reduce alpha of weather (rain, snow) for better visibility
	//
	// Note: using #if defined instead of #ifdef to prevent this from being
	// picked up as a shader configuration option.
	#if defined(WEATHER)
		surfaceColor.a *= 0.5;
	#endif

	#endif
	
	#if defined(MIX_ENTITY_COLOR)
		// Apply hurt flash / tnt flash on entities.
		surfaceColor.rgb = mix(
			surfaceColor.rgb, entityColor.rgb, entityColor.a);
	#endif

	#if !defined(SKIP_ALPHA_TEST)
		// Run the alpha test immediately to avoid shading fragments
		// that would fail the alpha test.
		// 
		// There's no penalty to running it early as we have to run it
		// either way, but if it lets us skip a whole block of pixels
		// (think player shoving their camera into a block of leaves),
		// then maybe we will get a little boost!
		// 
		// Ideally, this helps us save on memory bandwidth when
		// and sampling the shadowmap as well as overall TMU load.
		//
		// Note: Even if you discard, you must also explicitly
		// return or else shader execution will continue with
		// some drivers (NVIDIA).
		//
		// - https://community.khronos.org/t/use-of-discard-and-return/68293/3
		// - https://community.khronos.org/t/probable-nvidia-glsl-compiler-bug/66129/2
		//
		// > An implementation might or might not continue executing the shader,
		// > but it is guaranteed that there is no effect on the framebuffer.
		//
		// The reason why is likely - "Non-uniform_flow_control":
		// https://wikis.khronos.org/opengl/Sampler_(GLSL)
		//
		// You cannot retrieve implicit derivatives (dFdx / etc) or sample with
		// mipmapping after this location if any of the materials you render are
		// subject to alpha testing.
		if (surfaceColor.a < alphaTestRef) { 
			discard;
			return;
		}
	#endif

	// Because of the significant difference in style between Distant Horizons
	// terrain and vanilla terrain, to avoid significant pop-in we need to fade
	// between the two.
	//
	// Distant Horizons has a feature called "overdraw", where it will draw
	// distant terrain even within the vanilla render distance, which gives us
	// the opportunity to fade between vanilla and distant terrain.
	//
	// However, one challenge is that we do not have the straightforward ability
	// to use translucency (alpha blending) to implement this fade. As a result,
	// we need to resort to alternatives, in this case, stippling.
	//
	// To remain seamless, this fade progresses in 5 stages as we get farther
	// from the camera:
	//
	// 1. Vanilla terrain only
	// 2. Fading in distant terrain
	// 3. Distant terrain and vanilla terrain both visible
	// 4. Fading out vanilla terrain
	// 5. Distant terrain only
	//
	// We cannot trivially fade in distant terrain at the same time as we fade
	// out vanilla terrain, as otherwise we would end up with holes where the
	// vanilla and distant terrain have different geometry.
	//
	// TODO: (3) does not work with non-fancy translucents, which get double
	// blended! It only works with opaques! This breaks Retro / vanilla water.
	//
	// TODO: These thresholds were iterated on before I discovered and fixed a
	//       bug causing a discontinuity in cameraRelativePos between DH and non
	//       DH terrain, so they should be redone.
	float fragDistance = length(cameraRelativePos);

	#if (!defined(AFTER_DEFERRED) || defined(FANCY_TRANSLUCENTS)) \
		&& defined(DISTANT_HORIZONS)
		float stipple = Bayer8(gl_FragCoord.xy);

		#if defined(DH_TERRAIN)
			if (smoothstep(far - 8, far - 6, fragDistance) <= stipple) {
				discard;
				return;
			}
		#elif defined(DISTANT_HORIZONS)
			if (1.0 - smoothstep(far - 2, far, fragDistance) <= stipple) {
				discard;
				return;
			}
		#endif
	#elif defined(DH_TERRAIN)
		surfaceColor.a *= smoothstep(far - 5, far - 3, fragDistance);
	#elif defined(DISTANT_HORIZONS)
		surfaceColor.a *= 1.0 - smoothstep(far - 2, far, fragDistance);
	#endif

	vec4 fragmentColor = vec4(vec3(0.0), surfaceColor.a);

	// Apply sRGB to linear conversion
	//
	// We do this after multiplying texture color with vertex color
	// and after including entity color (if applicable) as to mimic
	// Minecraft, as it does the same multiplications (incorrectly)
	// in sRGB color space.
	surfaceColor.rgb = SrgbToLinear(surfaceColor.rgb);

	float blockLight = LightMapToLight(lightMap.x);
	vec3 blockLightColor = BLOCKLIGHT_COLOR;

	// Detection of emissive pixels from vanilla-like textures with hardcoded
	// color values.
	#define EMISSIVE_DETECTION
	#ifdef EMISSIVE_DETECTION
		EmissiveDetection(
			materialID,
			// It's important that we use the original color sampled from the
			// texture rather than the surface color with tinting applied. Else
			// we get bogus emissive detection results when in surface debug
			// modes
			sampledColor.rgb,
			blockLight,
			blockLightColor
		);
	#endif

	// Skip all these lighting calculations if we are going to throw away the
	// result anyhow.
	#if defined(SKIP_ALPHA_TEST)
		if (fragmentColor.a > 0.01) {
	#endif
		fragmentColor.rgb = DiffuseLighting(SurfaceFragment(
			#if defined(REAL_TIME_SHADOWS)
				cameraRelativePos,
				// The projected shadowmap position to sample from.
				shadowPos,
			#endif
			// The linear RGB color of the surface at this position, including
			// all AO and tinting.
			surfaceColor.rgb,
			// The predefined material ID of this fragment.
			materialID,
			// The normal vector of the surface where this fragment is, in
			// world-space.
			worldNormal,
			// The sky light strength, where 1 is light level 15 and 0 is no
			// light.
			skyLight,
			// The block light strength, where 1 is light level 15 and 0 is no
			// light.
			blockLight,
			// The held light strength, where 1 is light level 15 and 0 is no
			// light.
			HeldLightStrength(cameraRelativePos),
			// The block light color normalized to a luminance of 1.
			blockLightColor,
			// The held light color normalized to a luminance of 1.
			HELD_LIGHT_COLOR
		));
	#if defined(SKIP_ALPHA_TEST)
		}
	#endif

	#if defined(TRANSLUCENT)
		fragmentColor = TranslucentLighting(
			fragmentColor,
			worldNormal,
			cameraRelativePos,
			viewPos,
			reflectionStrength,
			skyLight,
			materialID
		);
	#endif

	#if defined(APPLY_FOG)
		// Determining the fragment distance for fog
		float fogDistance = max(
			abs(cameraRelativePos.y),
			length(cameraRelativePos.xz));

		// FogV2 does not immediately require the sky color, which enables an
		// optimization where we skip the atmospheric fog (requiring the sky
		// color) at low fog strengths.
		float skyFogStrength;
		vec4 fog = FogV2(skyFogStrength, fogDistance, fogDistance, skyLight);

		fragmentColor.rgb = mix(fragmentColor.rgb, fog.rgb, fog.a);

		// FogV2 instead just tells us the amount of sky color to add in to the
		// final fogged fragment color, so we can skip computing the sky color
		// when we do not need to add in any of the sky color.
		//
		// This can actually be quite impactful with the new Minishita sky model
		// and when looking at a lot of water, since we have to compute the sky
		// color twice (once for reflection, once for fog) otherwise and this
		// is basically as if the sky color calculation was twice as fast.
		skyFogStrength *= fog.a;

		if (skyFogStrength > 0.0) {
			vec3 sky = SkyDither(
				gl_FragCoord.xy, 
				SkyColor(normalize(cameraRelativePos)));
			fragmentColor.rgb += sky * skyFogStrength;
		} else {
			// Tints terrain receiving lit.fsh fog that did not require the sky
			// color
			// #define DEBUG_FOG_OPTIMIZATION
			#ifdef DEBUG_FOG_OPTIMIZATION
				fragmentColor.rb = vec2(0.0);
			#endif
		}

		// We also fade away the background (effectively, because we need to
		// blend it with the fog, too) based on the same factor used to fade
		// away the fragment color.
		fragmentColor.a = mix(fragmentColor.a, 1.0, fog.a);
	#endif

	gl_FragData[0] = fragmentColor;

	#if (WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED || defined(VOXY)) && \
		!defined(AFTER_DEFERRED)
		gl_FragData[1] = vec4(skyLight);
		/* DRAWBUFFERS:02 */
	#else
		/* DRAWBUFFERS:0 */
	#endif
}
