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

#include "../../lib/bayer8.slang"

#if !defined(GODRAYS_SAMPLE_DEFINED)
	interface GodraysSampler {
		static float Sample(float2 uv);
	}

	float godraysSample(GodraysSampler sampler, float2 uv) {
		return sampler.Sample(uv);
	}
#endif

struct GodraysSettings {
	uint samples;
	float density;
	float baseDecay;
};

static const GodraysSettings NOISY_GODRAYS = GodraysSettings(8u, 0.83, 0.5);
static const GodraysSettings SMOOTH_GODRAYS = GodraysSettings(8u, 0.75, 0.0001);

// Godrays function based on GPU Gems 3:
//
// "Chapter 13. Volumetric Light Scattering as a Post-Process"
// https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows
//
// Tweaks:
// - Moved to sampling the depth map instead of the color map
// - By varying the starting position using noise, we can get away with a
//   much-reduced sample count
float Godrays(
	GodraysSampler sampler,
	GodraysSettings settings,
	float2 uv,
	float2 lightUV,
	float2 pixelCoord
) {
	float decay = pow(settings.baseDecay, 1.0 / float(settings.samples));

	// Calculate vector from pixel to light source in screen space.
	// Divide by number of samples and scale by control factor.
	float2 step = (uv - lightUV) * (settings.density / float(settings.samples));
	// NEW: Use noise to allow us to get away with a singificantly reduced
	// iteration count.
	uv += step * 1.5 * Bayer8(pixelCoord);
	// Store initial sample.
	float accumulated = godraysSample(sampler, uv);
	// Set up illumination decay factor.
	float illuminationDecay = 1.0;
	// Evaluate summation from Equation 3.
	for (uint i = uint(0); i < settings.samples; i++) {
		// Step sample location along ray.
		uv -= step;
		// Retrieve sample at new location.
		float depthSample = godraysSample(sampler, uv);
		// Apply sample attenuation scale/decay factors.
		depthSample *= illuminationDecay;
		// Accumulate depth samples.
		accumulated += depthSample;
		// Update exponential decay factor.
		illuminationDecay *= decay;
	}
	// Output final accumulated sample with a further scale control factor.
	return accumulated * (1.0 / float(settings.samples));
}
