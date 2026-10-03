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

// Implementation of a decently good looking procedural water surface using
// coherent (value) noise.
//
// These waves work by stretching and scrolling various layers of smooth value
// noise of varying frequency, and then adding them together into a heightmap.
// To add additional variation, some waves are designated as "crest waves" where
// we replace the uniform high and low areas with intermittent crests on an
// otherwise flat surface. We call the other waves "ripple waves".
//
// Adding a few layers of ripple and crest waves together gives a decent
// heightmap to work with.
//
// Then, we analytically compute the gradient (partial derivatives) of the
// heightmap, resulting in a function that gives the surface normal vector for
// any given position on the water surface. Since the derivative of the sum of
// two functions is the sum of each function's derivative, we can analytically
// compute the gradient of each wave layer individually and then add them
// together at the end. In this implementation, computing the gradient (and
// therefore, the normal vector) is nearly as fast as computing the height at a
// given location on the water.
//
// Finally, this heightmap-first formulation of the surface with accompanying
// gradient-based normal maps gives us a surface to apply a variation of
// parallax mapping to. Adding this parallax mapping gives the water surface
// meaningful depth, significantly boosting the quality of the waves, and the
// inherent smoothness in the surface allows us to only use a few iterations
// in the parallax mapping for a minimal performance hit.
//
// This implementation primarily supports smooth, calm, swell-like waves.
// It does not support water surfaces with stormy or high-wind conditions (foam
// / spray / etc), which would be present in more advanced models such as
// Tessendorf's FFT waves as used in Sea of Thieves and similar.
//
// References:
//
// - Value noise (Wikipedia): https://en.wikipedia.org/wiki/Value_noise
// - Value Noise and Procedural Patterns (Scratchapixel): 
//   https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds
//   /procedural-patterns-noise-part-1/introduction.html
// - Analytical derivatives of Perlin noise:
//   https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds
//   /perlin-noise-part-2/perlin-noise-computing-derivatives.html
//     - Note that we use value noise but the idea is essentially the same

// We use the smoothNoise2D variant of our value noise as that function results
// in a continuous, smooth gradient, available as gradSmoothNoise2D. For the
// water to look smooth, the noise must be smooth too - the bilinear
// interpolation in noise is not acceptable, which is why we use the
// smooth "fade" interpolation from Perlin noise instead.
#include "/lib/valueNoise.slang"

// Whether to compute the gradient based on the slower finite gradient method
// rather than using analytical derivatives.
//#define PREFER_FDM_GRADIENT
#ifndef PREFER_FDM_GRADIENT
	// If we are not using the finite-difference method, we will need the
	// analytical derivatives of value noise. This define signals that they
	// should be enabled.
	//
	// Currently, value noise derivatives require MC_GL_ARB_texture_gather
	// (core in GLSL 4.00).
	//
	// FDM is a fallback for when textureGather is not available.
	#ifdef MC_GL_ARB_texture_gather
		#include "/lib/valueNoiseDerivatives.slang"
	#else
		// textureGather is not available, we must fall back to FDM.
		#define USE_FDM_GRADIENT
	#endif
#else
	// A developer explicitly enabled FDM, useful for testing the slightly
	// tricker analytical derivative approach.
	#define USE_FDM_GRADIENT
#endif

// This function reshapes the original smooth transitions
// between different wave levels into more visible "crests"
// on the transitions between different wave levels, such that
// most of the area is flat and there are raised crests at regular grid
// transition points.
float crest(float h) {
	static const float PI = 3.14159265359;

	// 0.5 - 0.5 * cos written out to explicitly have it as
	// mul -> cos -> fma
	return (-0.5 * cos(h * (PI * 2.0))) + 0.5;
}

// Computes the derivative of the above crest function.
// 
// How to use this:
// 
// Assuming you have a function like this, and you want the gradient of H:
// H(x, y) = crest(N(x, y)) = crest(smoothNoise2D(x, y))
//
// First, let us differentiate over x, applying the chain rule:
// dH/dx = (dCrest/dN)(N(x, y)) * (dN/dx)(x, y)
//
// Given this, the gradient would be (given N = smoothNoise2D):
// gradH(x, y) = crestDerivative(smoothNoise2D(x, y)) * gradSmoothNoise2D(x, y)
float crestDerivative(float h) {
	static const float PI = 3.14159265359;

	// mul -> sin -> mul
	return PI * sin(h * (PI * 2.0));
}

// Weaken the gradient since otherwise the waves look way too intense
// otherwise.
//
// TODO: Find a mathematical interpretation of this... I chose this because
//       it looked good but it is probably not appropriate for all possible
//       waves.
static const float GRADIENT_STRENGTH = 0.15;

// Generated wave definitions passed in via custom uniforms.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform float4 waterScrollRippleAB;
	uniform float4 waterScrollRippleCD;
	uniform float4 waterScrollCrestAB;

	uniform float3 waterStretchRippleA;
	uniform float3 waterStretchRippleB;
	uniform float3 waterStretchRippleC;
	uniform float3 waterStretchRippleD;
	uniform float3 waterStretchCrestA;
	uniform float3 waterStretchCrestB;

	uniform float4 waterMagnitudeRipple;
	uniform float2 waterMagnitudeCrest;
#endif

// Avoiding excessive aliasing in our procedural water surface:
//
// From a quick survey of the waves in most existing shader packs, essentially
// everyone  anti-aliases water surface/reflections temporally (TAA), with FXAA,
// or applies both. But, both of these methods have meaningful tradeoffs to both
// performance and quality. FXAA and TAA are both ultimately really advanced
// screen-wide blurs, and even the best implementations have artifacts and can
// cause negative impact to clarity. At worst, TAA turns distant geometry into a
// mess of blurry jittering, and FXAA can be almost as bad, essentially blurring
// everything. 3kliksphilip made a great video that mentions the shortcomings of
// FXAA here: https://www.youtube.com/watch?v=nEbAJHd84ug&t=224s)
//
// With procedural water surfaces, there is some truly awful aliasing when no
// attempt is made to mitigate it. While it is tempting to jump immediately to
// TAA/FXAA, that is not the best way! While these methods or other ones like
// MSAA are the solution for removing aliasing on surface edges, aliasing within
// a surface indicates problems in how we are sampling the surface that we can
// and should fix. We want the surface to look decent without TAA/FXAA, such
// that TAA/FXAA are an enhancement rather than a requirement for a good image.
//
// Essentially, for each individual layer of noise, our goal is to determine if
// the ratio of pixels in the 64x64 noise texture to pixels visible on the
// screen in a given area of the scene is too high. Certainly, if we are at a
// 1:1 ratio or higher, such that a noise pixel only covers one pixel or part of
// a pixel on the screen, then we will have severe aliasing as in that case our
// coherent noise will degrade to white noise on the screen. But we will still
// get aliasing at lower ratios. As it turns out, we can base this on the
// https://en.wikipedia.org/wiki/Nyquist_rate.
//
// So, our goal here is to fade away noise layers to their average values when
// the ratio climbs too high. To implement that, we determine a metric for
// approximating this ratio of noise pixels to screen pixels (explained in the
// implementation), and then as use that to determine a fade-out factor for the
// layer.
//
// We fade out to the average value of noise, which is 0.5. This is a bit basic
// as we could do some fancy mipmapping or integrating (ie, averaging over the
// covered area) of the noise texture for a better result, but it is OK for now.
//
// References:
//
// - Section "One Last Very Important Thing to Know" of 
//   https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds
//   /procedural-patterns-noise-part-1/creating-simple-1D-noise.html
//
// Further work:
//
// - If we support cone-traced rough/glossy reflections in the future, we can
//   forward some sort of roughness value out of here instead of just fading
//   away to perfectly smooth mirror-like reflections.
float antialiasFactor(float2 ddxWorldPos, float2 ddyWorldPos, float3 stretch) {
	// Because the wave noise sampling position is just a uniform scroll plus
	// the stretched coordinate, its partial derivatives are the same as the
	// partial derivates of the stretched coordinate, therefore:
	//
	// * ddx(at) = ddx(stretched)
	// * ddy(at) = ddy(stretched)
	//
	// And, because we define stretched as:
	//
	//     stretched = float2(worldPos.x * stretch.x, dot(worldPos, stretch.zy))
	//
	// Its partial derivatives are just the same operations on the partial
	// derivatives of the world position, for example for dFdx (same for dFdy):
	//
	// ddx(stretched) = float2(
	//     ddx(worldPos).x * stretch.x,
	//     dot(ddx(worldPos), stretch.zy));
	//
	//
	// Per the following, each partial derivative operation is basically 3 ALUs:
	// https://fgiesen.wordpress.com/2011/07/10
	// /a-trip-through-the-graphics-pipeline-2011-part-8/#comment-1990
	//
	// So, the code this replaces was 12 ALUs for the 4 partial derivatives, and
	// our goal is to beat or match that. Since our replacement is 2 multiplies,
	// 2 dots (which are an fma + multiple each), we just replaced 12 ALUs with
	// 6 ALUs, so the analytical derivative way is actually faster!
	float2 ddxAt = float2(ddxWorldPos.x * stretch.x, dot(ddxWorldPos, stretch.zy));
	float2 ddyAt = float2(ddyWorldPos.x * stretch.x, dot(ddyWorldPos, stretch.zy));

	// How this actually works:
	//
	// We can think of the input noise coordinate as being given by a vector
	// function M(x, y) accounting for all of the calculation and interpolation
	// needed to produce that coordinate for each screen fragment. This function
	// takes in a screen pixel position, transforms that to a tangent-space
	// position (attribute interpolation / accounting for camera projection),
	// and finally transforms that to a noise texture position (our scaling
	// factors).
	//
	// We compute the Jacobian of this function (essentially a gradient, but for
	// vector functions) using implicit derivatives, then find the absolute
	// value of each element, and then find the maximum of those.
	//
	// We then use this as a metric to judge if our sampling rate of this
	// texture appears to be nearing or exceeding the Nyquist rate.
	//
	// In terms of units, the result is a ratio of noise pixels to screen pixels.
	//
	// This technique is inspired by the below paper, but the metric we retrieve
	// from the Jacobian is more of a good-looking approximation than an exact
	// formulaic approixmation of the sampling rate:
	//
	// "Detail Synthesis for Image-based Texturing" by Ismert/Bala/Greenberg
	// https://www.cs.cornell.edu/~kb/publications
	// /DetailSynthesis_I3D03_cameraready_WithHeader.pdf
	float2 maxes = max(abs(ddxAt), abs(ddyAt));
	float ratio = max(maxes.x, maxes.y);

	// We will allow users to choose their preferred tradeoff between aliasing &
	// preserving detail vs losing detail but lacking aliasing. For example, if
	// we have filter-based AA like TAA/FXAA, we can leave some more aliasing
	// here in anticipation for it being removed later, in a way that preserves
	// detail better. Alternatively, if we do not have filter-based AA, we can
	// focus on removing more aliasing to keep it to an acceptable level.
	#define OFF 0
	#define LOW 1
	#define BALANCED 2
	#define HIGH 3
	// Water antialiasing smooths out waves to avoid excessive aliasing,
	// but might cause distant water to look flat.
	#define WATER_AA BALANCED // [OFF LOW BALANCED HIGH]

	#if WATER_AA == LOW
		// Low: Not compliant with Nyquist rate. Preserves more detail at the
		// expense of elevated aliasing.
		return smoothstep(0.6, 0.8, ratio);
	#elif WATER_AA == BALANCED
		// Medium: Partially compliant with Nyquist rate. Preserves the majority
		// of detail while maintaining an acceptable amount of aliasing.
		return smoothstep(0.45, 0.55, ratio);
	#elif WATER_AA == HIGH
		// High: Mostly compliant with Nyquist rate. Sacrifices additional
		// detail to further reduce aliasing.
		return smoothstep(0.4, 0.5, ratio);
	#elif WATER_AA == OFF
		// Off: No attempt to comply with Nyquist rate. Not recommended, just
		// for debugging.
		return 0.0;
	#endif
}

// Simple helper function to apply antialiasing to a height returned by a noise
// function at a given position. This fades the height to 0.5 as needed to avoid
// aliasing.
float antialiasHeight(float aa, float height) {
	return lerp(height, 0.5, aa);
}

// Assuming antialiasFactor returns a factor f, from the perspective of
// derivative it is just as if we multiplied the height by (1.0 - f) and
// otherwise added a constant.
//
// We can assume that f remains constant in the small local area around the
// point we are sampling, and therefore, (1.0 - f) is a constant factor in the
// multitplication that we can peel out and multiply by the gradient.
float2 antialiasGradient(float aa, float2 gradient) {
	return gradient * (1.0 - aa);
}

float waterRippleHeight(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos,
	uint i,
	float3 stretch,
	float2 scroll
) {
	float2 stretched = float2(
		worldPos.x * stretch.x,
		dot(worldPos, stretch.zy));
	float2 at = scroll + stretched;
	float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

	return waterMagnitudeRipple[i] * antialiasHeight(aa, smoothNoise2D(at));
}

// Returns water height between 0.0 and 1.0, with 0.0 being the lowest and 1.0
// being the highest.
//
// This function is responsible for adding together each wave layer into the
// final heightmap.
//
// Inputs: horizontal world position in meters and partial derivatives
float WaterHeight(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos,
	bool approximate
) {
	float height = 0.0;

	// === A note on dot products and fused multiply add (FMA) ===
	//
	// Note for this function as well as the gradient function that 
	// dot(worldPos, stretch.zy) is just equivalent to:
	//
	//   worldPos.y * stretch.y + worldPos.x * stretch.z
	//
	// It's just that the way it is written compiles to 2 instructions: fma, mul
	//
	// Essentially every GPU offers FMA (A * B + C) as a single instruction
	// so you benefit from using dot and arranging your math in FMA form
	// (A * B + C). The compiler can't always find these patterns so it's best
	// to help it along!

	// Ripple waves - Scrolled and stretched smooth value noise
	height += waterRippleHeight(worldPos, ddxWorldPos, ddyWorldPos,
		0u, waterStretchRippleA, waterScrollRippleAB.xy);
	height += waterRippleHeight(worldPos, ddxWorldPos, ddyWorldPos,
		1u, waterStretchRippleB, waterScrollRippleAB.zw);

	// During parallax mapping, the last two ripples contribute minimally, and
	// it is possible to get a decent FPS boost from ignoring them.
	if (!approximate) {
		height += waterRippleHeight(worldPos, ddxWorldPos, ddyWorldPos,
			2u, waterStretchRippleC, waterScrollRippleCD.xy);
		height += waterRippleHeight(worldPos, ddxWorldPos, ddyWorldPos,
			3u, waterStretchRippleD, waterScrollRippleCD.zw);
	}

	for (uint i = uint(0); i < 2u; i++) {
		float3 stretch = i == 0u ? waterStretchCrestA : waterStretchCrestB;
		float2 scroll = i == 0u ? waterScrollCrestAB.xy : waterScrollCrestAB.zw;
		
		float2 stretched = float2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		float2 at = scroll + stretched;
		float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

		height += waterMagnitudeCrest[i] * crest(
			antialiasHeight(aa, smoothNoise2D(at)));
	}

	return height;
}

float WaterHeight(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos
) {
	return WaterHeight(worldPos, ddxWorldPos, ddyWorldPos, false);
}

float WaterHeightApproximate(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos
) {
	return WaterHeight(worldPos, ddxWorldPos, ddyWorldPos, true);
}

#if !defined(USE_FDM_GRADIENT)

float2 waterRippleGradient(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos,
	uint i,
	float3 stretch,
	float2 scroll
) {
	// Same notes here as in the WaterHeight function
	float2 stretched = float2(
		worldPos.x * stretch.x,
		dot(worldPos, stretch.zy));
	float2 at = scroll + stretched;
	float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

	float2 waveGradient = (GRADIENT_STRENGTH * waterMagnitudeRipple[i])
		* gradSmoothNoise2D(at);

	// This part is the main tricky part of the analytic gradient - we have
	// the scaled gradient of the value noise at this position, but due to
	// the coordinate stretching caused by adding worldPos.x into the Y
	// value of the noise, the partial derivative with respect to X is
	// actually a directional derivative.
	//
	// The Y part is simple enough - just multiplying the Y scale factor
	// with the corresponding part of the gradient as a part of applying the
	// chain rule. Adding in X as a part of stretching has no impact because
	// we are only interested in the partial derivative with respect to Y,
	// so that X term is a constant.
	//
	// For the X part, though in the original coordinate transform we allow
	// X to influence the Y value, this means that the impact is actually to
	// the X partial derivative. As we vary the value of X, we move
	// diagonally across the value noise, in other words, along a given
	// direction.
	//
	// Luckily, directional derivatives are simple - it is just the dot of
	// the direction and magnitude vector in that direction with the
	// gradient vector, which is exactly what we have here.
	//
	// Finally, as this is the negative gradient, we subtract when
	// accumulating.
	return antialiasGradient(aa,
		float2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y));
}

// Computes the negative gradient of the water surface using analytic
// derivatives.
//
// In other words, we found the derivative / gradient function ahead of time
// using calculus, simplifying the computations that need to be done each frame.
//
// This function returns -gradient (negative gradient) since the normal is
// perpendicular to the actual gradient, and we can bake the multiplication by
// -1 into one of the existing multiplies so that it is free.
float2 WaterNGradientAnalytic(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos
) {
	float2 gradient = float2(0.0);

	// Ripple waves - Scrolled and stretched smooth value noise
	gradient -= waterRippleGradient(worldPos, ddxWorldPos, ddyWorldPos,
		0u, waterStretchRippleA, waterScrollRippleAB.xy);
	gradient -= waterRippleGradient(worldPos, ddxWorldPos, ddyWorldPos,
		1u, waterStretchRippleB, waterScrollRippleAB.zw);
	gradient -= waterRippleGradient(worldPos, ddxWorldPos, ddyWorldPos,
		2u, waterStretchRippleC, waterScrollRippleCD.xy);
	gradient -= waterRippleGradient(worldPos, ddxWorldPos, ddyWorldPos,
		3u, waterStretchRippleD, waterScrollRippleCD.zw);

	// Crest waves - Like ripple waves, but we use crest around the result of
	// the smoothed value noise.
	for (uint i = uint(0); i < 2u; i++) {
		float3 stretch = i == 0u ? waterStretchCrestA : waterStretchCrestB;
		float2 scroll = i == 0u ? waterScrollCrestAB.xy : waterScrollCrestAB.zw;
		
		float2 stretched = float2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		float2 at = scroll + stretched;
		float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

		// Antialiasing is a bit more involved in the gradients of these crest
		// waves.
		//
		// We need to compute the antialiased height at this position for use in
		// the chain rule for the derivative of the crest function, but we also
		// need to apply antialiasing to the returned gradient. Since we use
		// antialiasFactor twice, we have inlined antialiasHeight and
		// antialiasGradient here.
		float heightAt = lerp(smoothNoise2D(at), 0.5, aa);

		// The main complexity here is that we need to apply the chain rule due
		// to the crest function.
		//
		// Other than that, this is fairly similar to above.
		float2 waveGradient = (GRADIENT_STRENGTH * waterMagnitudeCrest[i])
			* gradSmoothNoise2D(at) * crestDerivative(heightAt);

		// Same notes apply as above, note that we have inlined the
		// functionality of antialiasGradient here.
		gradient -= (1.0 - aa) * 
			float2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y);
	}

	return gradient;
}

#endif

// Computes the negative gradient of the water surface using the finite
// difference method (FDM):
// https://en.wikipedia.org/wiki/Finite_difference_method
//
// This function returns -gradient (negative gradient) since the normal is
// perpendicular to the actual gradient, and we can bake the multiplication by
// -1 into one of the existing multiplies so that it is free:
//
// https://en.wikipedia.org/wiki/Normal_(geometry)#Calculating_a_surface_normal
//
// This should be slower than the analytic method, but it is useful as a
// fallback to debug and diagnose issues since the complexity of FDM is a lot
// more manageable than the analytic method. In addition, FDM is useful when
// developing new wave shapes as it makes it possible to experiment
// without needing to do hours of error-prone calculus to get your results.
//
// But, for something widely-distributed in production, it makes sense to use
// the more efficient analytical method to get maximum performance.
float2 WaterNGradientFDM(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos
) {
	// This is about the lowest I could go without major artifacts. The lower
	// you can go the better, but at some point we run out of floating-point
	// precision or hit limitations of the underlying sampling going on in the
	// wave funciton. Play around with this as needed.
	static const float delta = 0.05;

	float2 ddxPos = ddxWorldPos;
	float2 ddyPos = ddyWorldPos;
	float h00 = WaterHeight(worldPos                   , ddxPos, ddyPos);
	float hX0 = WaterHeight(worldPos + float2(delta, 0.0), ddxPos, ddyPos);
	float h0Y = WaterHeight(worldPos + float2(0.0, delta), ddxPos, ddyPos);

	return (-GRADIENT_STRENGTH / delta) * (float2(hX0, h0Y) - float2(h00));
}

// Returns the normal map for the water surface computed from the gradient of
// the water surface heightmap.
//
// Inputs: horizontal world position in meters and partial derivatives
// Output: normal vector in tangent space (X/Y = in-plane, Z = up out of the
// plane)
float3 WaterNormal(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos,
	float time
) {
	#if defined(USE_FDM_GRADIENT)
		float2 minusGradient = WaterNGradientFDM(
			worldPos, ddxWorldPos, ddyWorldPos);
	#else
		float2 minusGradient = WaterNGradientAnalytic(
			worldPos, ddxWorldPos, ddyWorldPos);
	#endif

	return normalize(float3(minusGradient, 1.0));
}
