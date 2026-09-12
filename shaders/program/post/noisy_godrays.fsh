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

// Noisy godrays implementation

#include "/lib/bayer8.glsl"

// The sky should have a depth value of 1.0. This is one of the few places
// where == works reliably.
const float SKY_DEPTH = 1.0;

// Sample a depth texture with depth comparison. This is a hack because we
// cannot use sampler objects to sample the depth texture with comparison mode
// enabled.
//
// This is effectively allowing us to use the sampler like a shadow sampler,
// without having that enabled:
// https://www.khronos.org/opengl/wiki/Sampler_(GLSL)#Shadow_samplers
//
// TODO(engine): Add PCF sampling for the main depth texture in Iris
uniform sampler2D depthtex0;

float DepthCompareSample(vec3 texCoord) {
	// Equivalent GL_TEXTURE_COMPARE_FUNC: GL_LEQUAL
	return float(texCoord.z <= texture(depthtex0, texCoord.xy).r);
}

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
float NoisyGodrays(vec2 texCoord, vec2 ScreenLightPos) {
	// Constants for the godrays
	const float NUM_SAMPLES = 8.0;
	const float DENSITY = 0.83;
	const float DECAY = pow(0.5, 1.0 / NUM_SAMPLES);

	// Calculate vector from pixel to light source in screen space.
	vec2 deltaTexCoord = (texCoord - ScreenLightPos);
	// Divide by number of samples and scale by control factor.
	deltaTexCoord *= 1.0f / NUM_SAMPLES * DENSITY;
	// NEW: Use noise to allow us to get away with a singificantly reduced
	// iteration count.
	texCoord += deltaTexCoord * 1.5 * Bayer8(gl_FragCoord.xy);
	// Store initial sample.
	float accumulated = DepthCompareSample(vec3(texCoord, SKY_DEPTH));
	// Set up illumination decay factor.
	float illuminationDecay = 1.0f;
	// Evaluate summation from Equation 3 NUM_SAMPLES iterations.
	for (uint i = uint(0); i < uint(NUM_SAMPLES); i++) {
		// Step sample location along ray.
		texCoord -= deltaTexCoord;
		// Retrieve sample at new location.
		float depthSample = DepthCompareSample(vec3(texCoord, SKY_DEPTH));
		// Apply sample attenuation scale/decay factors.
		depthSample *= illuminationDecay;
		// Accumulate depth samples.
		accumulated += depthSample;
		// Update exponential decay factor.
		illuminationDecay *= DECAY;
	}
	// Output final accumulated sample with a further scale control factor.
	return accumulated / NUM_SAMPLES;
} 

uniform vec2 windowToScreenHalf;
uniform vec4 screenLightVector;
uniform float godraysExposure;

// Output format is just a single color channel, 8 bits is enough.
//
// Originally I used 16 bits, but it turns out that if we do not scale the
// result, since we are smoothing the result anyways and the noise acts as a
// dither, there is actually zero noticeable difference between 8 bits and 16
// bits. So switching to 8 bit halves the required memory bandwidth on both ends
// basically for free, compared to using 16 bits.
const int R8 = 0;
const int colortex1Format = R8;

/* DRAWBUFFERS:1 */
out float godrays;

void main() {
	if (godraysExposure <= 0.0) {
		// Prevent the buffer from getting filled with garbage
		// unitialized garbage - not visible without debug view,
		// but avoiding undefined behavior is good.
		godrays = 0.0;
		return;
	}

	// Determine the position of this fragment on the screen in screen
	// coordinates (0.0 to 1.0).
	vec2 screenCoord = gl_FragCoord.xy * windowToScreenHalf;

	// While we check whether godrays are exposed above to avoid
	// additional computation cost, to fully use the 8 bits of
	// precision do not scale the value here.
	godrays = NoisyGodrays(screenCoord, screenLightVector.xy);
}
