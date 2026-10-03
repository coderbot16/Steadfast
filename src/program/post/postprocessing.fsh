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

// By default, Iris clears colortex0 specifically to the fog color. We do not
// need this behavior, so clear to zero. On some drivers this is supposedly
// faster, though I noticed no difference.
const float4 colortex0ClearColor = float4(0.0, 0.0, 0.0, 0.0);
const int colortex0Format = R11F_G11F_B10F;

// Godrays format is just a single color channel, 8 bits is enough.
//
// Originally I used 16 bits, but it turns out that if we do not scale the
// result, since we are smoothing the result anyways and the noise acts as a
// dither, there is actually zero noticeable difference between 8 bits and 16
// bits. So switching to 8 bit halves the required memory bandwidth on both ends
// basically for free, compared to using 16 bits.
const int R8 = 0;
const int colortex1Format = R8;

// For consistency, also clear colortex1 to zero. This in particular has no
// performance difference but it is unusual compared to all other textures
const float4 colortex1ClearColor = float4(0.0, 0.0, 0.0, 0.0);

#include "/lib/tonemap_uncharted2.slang"
#include "/lib/tonemap_uchimura.slang"
#include "/lib/srgb.slang"

// GODRAYS BEGIN
#include "/common/lib/bayer8.slang"

#define GODRAYS_SAMPLE_DEFINED
#define GodraysSampler sampler2D

float godraysSample(GodraysSampler sampler, float2 uv) {
	return texture(sampler, uv).r;
}

#include "/common/post/godrays.slang"

#define GODRAYS // Efficient screen-space light shafts.

uniform GodraysSampler colortex1;
uniform float4 screenLightVector;
uniform float godraysExposure;

uniform float2 windowToScreen;
uniform float3 godraysColor;

float3 smoothGodrays() {
	if (godraysExposure <= 0.0) {
		return float3(0.0);
	}

	float2 uv = gl_FragCoord.xy * windowToScreen;

	float exposure = pow(1.0 - 0.5 * length(uv - screenLightVector.xy)
		* SMOOTH_GODRAYS.density
		* (1.0 - 0.3 * Bayer8(-gl_FragCoord.xy)), 8.0);

	// Note: godraysExposure is premultiplied into godraysColor
	return godraysColor * (exposure * Godrays(
		colortex1,
		SMOOTH_GODRAYS,
		uv,
		screenLightVector.xy,
		gl_FragCoord.xy
	));
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

#include "/environment/tonemap_settings.slang"

layout(location = 0) out float3 finalColor;

float3 tonemap(float3 color) {
	#if TONEMAP == TONEMAP_UNCHARTED2
		return Uncharted2Tonemap(color);
	#else
		return UchimuraTonemap(color);
	#endif
}

void main() {
	// Determine the position of this fragment on the screen in screen
	// coordinates (0.0 to 1.0).
	float2 screenCoord = gl_FragCoord.xy * windowToScreen;

	#if DEBUG == DEBUG_GODRAYS_NOISY
		finalColor = float3(texture(colortex1, screenCoord).r);
	#elif DEBUG == DEBUG_SKYLIGHT
		finalColor = float3(texture(colortex5, screenCoord).r);
	#elif DEBUG == DEBUG_ROUGH_REFRACTION
		finalColor = LinearToSrgb(tonemap(texture(colortex6, screenCoord).rgb));
	#else
		float3 color = float3(0.0);

		#if DEBUG != DEBUG_GODRAYS_SMOOTH
			color = texture(colortex0, screenCoord).rgb;
		#endif

		#ifdef GODRAYS
			color += smoothGodrays();
		#endif

		finalColor = LinearToSrgb(tonemap(color));
	#endif
}
