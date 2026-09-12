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

// Final fragment shader that implements tonemapping, debugging visualization,
// and all other postprocessing shader effects. As this shader pack follows a
// forward-rendering architecture with most effects implemented directly
// rather in a deferred pass, this program is very minimal.

// This is a very compact floating-point color format using 32 bits just as
// RGBA8 does, while permitting HDR colors.
//
// Note that even though this format lacks an alpha channel, translucency is
// still supported, as translucent alpha blending does not actually require
// writing to the alpha channel as in all cases we are drawing against an opaque
// background.
const int R11F_G11F_B10F = 0;
const int colortex0Format = R11F_G11F_B10F;

#include "/lib/tonemap_uncharted2.glsl"
#include "/lib/tonemap_uchimura.glsl"
#include "/lib/srgb.glsl"

// GODRAYS BEGIN
#include "/lib/bayer8.glsl"

#define GODRAYS // Efficient screen-space light shafts.

uniform sampler2D colortex1;
uniform vec4 screenLightVector;
uniform float godraysExposure;

// Godrays function based on GPU Gems 3:
//
// "Chapter 13. Volumetric Light Scattering as a Post-Process"
// https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows
//
// Tweaks:
// - Moved to sampling the depth map instead of the color map
//   (DepthCompareSample)
// - By varying the starting position using noise, we can get away with a
//   much-reduced sample count
float SmoothGodrays(vec2 texCoord, vec2 ScreenLightPos) {
	// Constants for the godrays
	const float NUM_SAMPLES = 8.0;
	const float DENSITY = 0.75;
	const float DECAY = pow(0.0001, 1.0 / NUM_SAMPLES);

	// Calculate vector from pixel to light source in screen space.
	vec2 deltaTexCoord = (texCoord - ScreenLightPos);
	// Divide by number of samples and scale by control factor.
	deltaTexCoord *= 1.0f / NUM_SAMPLES * DENSITY;
	// NEW: Use noise to allow us to get away with a singificantly reduced
	// iteration count.
	texCoord += deltaTexCoord * 1.5 * Bayer8(-gl_FragCoord.xy);
	// Store initial sample.
	float accumulated = texture(colortex1, texCoord).r;
	// Set up illumination decay factor.
	float illuminationDecay = 1.0f;
	// Evaluate summation from Equation 3 NUM_SAMPLES iterations.
	for (uint i = uint(0); i < uint(NUM_SAMPLES); i++) {
		// Step sample location along ray.
		texCoord -= deltaTexCoord;
		// Retrieve sample at new location.
		float depthSample = texture(colortex1, texCoord).r;
		// Apply sample attenuation scale/decay factors.
		depthSample *= illuminationDecay;
		// Accumulate depth samples.
		accumulated += depthSample;
		// Update exponential decay factor.
		illuminationDecay *= DECAY;
	}
	// Output final accumulated sample with a further scale control factor.
	float exposure = pow(1.0 - 4.0 * length(deltaTexCoord)
		* (1.0 - 0.3 * Bayer8(-gl_FragCoord.xy)), 8.0);
	return exposure * accumulated / NUM_SAMPLES;
} 
// GODRAYS END

// Note: if we do not define all values used in GLSL expressions, we get the
// following error:
//
// > error: Bad token in expression: ==
//
// Code reference:
//
// https://github.com/IrisShaders/glsl-preprocessor
// Commit: 595a0b379256f68408f68d83285683243cab3187
// /src/main/java/io/github/douira/glsl_preprocessor/Preprocessor.java#L1454
#define DEBUG_NONE 0
#define DEBUG_GODRAYS_NOISY 1
#define DEBUG_GODRAYS_SMOOTH 2
#define DEBUG_SKYLIGHT 3
#define DEBUG_ROUGH_REFRACTION 4
#define DEBUG DEBUG_NONE // Debugging [DEBUG_NONE DEBUG_GODRAYS_NOISY DEBUG_GODRAYS_SMOOTH DEBUG_SKYLIGHT DEBUG_ROUGH_REFRACTION]

#if DEBUG == DEBUG_GODRAYS_NOISY || DEBUG == DEBUG_GODRAYS_SMOOTH
	//uniform sampler2D colortex1;
#elif DEBUG == DEBUG_SKYLIGHT
	uniform sampler2D colortex5;
#elif DEBUG == DEBUG_ROUGH_REFRACTION
	uniform sampler2D colortex6;
#else
	uniform sampler2D colortex0;
#endif

#include "/environment/tonemap_settings.glsl"

uniform vec2 windowToScreen;

layout(location = 0) out vec3 finalColor;

uniform vec3 godraysColor;

vec3 tonemap(vec3 color) {
	#if TONEMAP == TONEMAP_UNCHARTED2
		return Uncharted2Tonemap(color);
	#else
		return UchimuraTonemap(color);
	#endif
}

void main() {
	// Determine the position of this fragment on the screen in screen
	// coordinates (0.0 to 1.0).
	vec2 screenCoord = gl_FragCoord.xy * windowToScreen;

	#if DEBUG == DEBUG_GODRAYS_NOISY
		finalColor = vec3(texture(colortex1, screenCoord).r);
	#elif DEBUG == DEBUG_GODRAYS_SMOOTH
		if (godraysExposure > 0.0) {
			float godrays = SmoothGodrays(screenCoord, screenLightVector.xy);
			finalColor = godraysColor * godrays;
		} else {
			finalColor = vec3(0.0);
		}
	#elif DEBUG == DEBUG_SKYLIGHT
		finalColor = vec3(texture(colortex5, screenCoord).r);
	#elif DEBUG == DEBUG_ROUGH_REFRACTION
		finalColor = LinearToSrgb(tonemap(texture(colortex6, screenCoord).rgb));
	#else
		vec3 color = texture(colortex0, screenCoord).rgb;

		#ifdef GODRAYS
		if (godraysExposure > 0.0) {
			float godrays = SmoothGodrays(screenCoord, screenLightVector.xy);
			
			// Note: godraysExposure is premultiplied into godraysColor
			color += godraysColor * godrays;
		}
		#endif

		finalColor = LinearToSrgb(tonemap(color));
	#endif
}
