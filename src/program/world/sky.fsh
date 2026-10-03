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

// Trivial program that draws the sky color on to the full screen.

#include "../../lib/bayer8.slang"
#include "../../environment/sky.slang"

// Clouds are animated over time
uniform float frameTimeCounter;

#include "../../environment/clouds/cirrus.slang"

// #define VANILLA_CLOUDS
#ifdef VANILLA_CLOUDS
	// Actual effect in shaders.properties
#endif

uniform float4x4 gbufferModelViewInverse;
uniform float4x4 gbufferProjectionInverse;
uniform float2 windowToNdc;
uniform float blindness;

flat in float isstars;
in float starAlpha;

void main() {
	// Project back to view space from the fragment coordinates. For this case,
	// it is easier to start off with a position on the far plane and then
	// normalize to a vector than to try to get a vector out of the screen
	// position directly.
	float2 ndcPos = gl_FragCoord.xy * float2(windowToNdc) - 1.0;
	float4 viewVecH = mul(gbufferProjectionInverse, float4(ndcPos, 1.0, 1.0));
	float3 viewVec = normalize(viewVecH.xyz / viewVecH.w);

	// Note: w must be 0.0 in homogenous coordinates, as 1.0 means a point in
	// space rather than a vector.
	float3 worldSpaceVector =
		mul(gbufferModelViewInverse, float4(viewVec, 0.0)).xyz;

	// Dithering 
	float2 ditherCoord = gl_FragCoord.xy;

	// Moves the sky dither pattern across the screen rapidly to reveal
	// excessive dithering
	// #define SKY_DITHER_DEBUG
	#ifdef SKY_DITHER_DEBUG
		ditherCoord += 500.0 * cos(frameTimeCounter);
	#endif

	float3 sky;
	float alpha = 1.0;

	if (isstars > 0.5) {
		sky = float3(1.0);
		alpha = starAlpha;
	} else {
		sky = SkyDither(ditherCoord, SkyColor(worldSpaceVector));
	}

	// If clouds are enabled, blend them into the sky gradient.
	#if defined(CLOUDS_ENABLED)
		// Make clouds "avoid" the sun and other bright parts of the sky.
		// This is needed because clouds otherwise blend oddly with the sun,
		// and this is much simpler than simulating clouds blocking the sun,
		// which I don't want to do anyways for style reasons.
		float skyLuminance = dot(sky, float3(0.2126, 0.7152, 0.0722));

		if (skyLuminance < 0.75) {
			float3 originalSky = sky;
			sky = BlendClouds(sky, worldSpaceVector);
		}
	#endif

/* DRAWBUFFERS:0 */

	// Fade away the sky during blindness
	gl_FragData[0] = float4(sky * max(0.0, 1.0 - 10.0 * blindness), alpha);
}
