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

#include "/lib/bayer8.glsl"
#include "/environment/sky.glsl"

// Clouds are animated over time
uniform float frameTimeCounter;

#include "/environment/clouds/cirrus.glsl"

// #define VANILLA_CLOUDS
#ifdef VANILLA_CLOUDS
	// Actual effect in shaders.properties
#endif

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform vec2 windowToNdc;
uniform float blindness;

flat in float isstars;

// Moves the sky dither pattern across the screen rapidly to reveal excessive
// dithering
// #define SKY_DITHER_DEBUG
#ifdef SKY_DITHER_DEBUG
	uniform float frameTimeCounter;
#endif

void main() {
	// Project back to view space from the fragment coordinates. For this case,
	// it is easier to start off with a position on the far plane and then
	// normalize to a vector than to try to get a vector out of the screen
	// position directly.
	vec2 ndcPos = gl_FragCoord.xy * vec2(windowToNdc) - 1.0;
	vec4 viewVecH = gbufferProjectionInverse * vec4(ndcPos, 1.0, 1.0);
	vec3 viewVec = normalize(viewVecH.xyz / viewVecH.w);

	// Note: w must be 0.0 in homogenous coordinates, as 1.0 means a point in
	// space rather than a vector.
	vec3 worldSpaceVector = (gbufferModelViewInverse * vec4(viewVec, 0.0)).xyz;

	// Dithering 
	vec2 ditherCoord = gl_FragCoord.xy;

	#ifdef SKY_DITHER_DEBUG
		ditherCoord += 500.0 * cos(frameTimeCounter);
	#endif

	vec3 sky;

	if (isstars > 0.5) {
		// TODO: Fade in stars gradually instead of instantly going to full
		// brightness.
		sky = vec3(1.0);
	} else {
		sky = SkyDither(ditherCoord, SkyColor(worldSpaceVector));
	}

	// If clouds are enabled, blend them into the sky gradient.
	#if defined(CLOUDS_ENABLED)
		sky = BlendClouds(sky, worldSpaceVector);
	#endif

/* DRAWBUFFERS:0 */

	// Fade away the sky during blindness
	gl_FragData[0] = vec4(sky * max(0.0, 1.0 - 10.0 * blindness), 1.0);
}
