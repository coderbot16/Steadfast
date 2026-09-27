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
#include "/lib/valueNoise.glsl"

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
		#include "/lib/valueNoiseDerivatives.glsl"
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
	const float PI = 3.14159265359;

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
	const float PI = 3.14159265359;

	// mul -> sin -> mul
	return PI * sin(h * (PI * 2.0));
}

// Weaken the gradient since otherwise the waves look way too intense
// otherwise.
//
// TODO: Find a mathematical interpretation of this... I chose this because
//       it looked good but it is probably not appropriate for all possible
//       waves.
const float GRADIENT_STRENGTH = 0.15;

// Define each wave as a set of intuitive measurements which the compiler can
// convert to more direct scaling and offset values, for easy tweaking.
struct NoiseWave {
	// The size of each tile in the grid on the X axis and the Y axis in meters.
	//
	// The area covered by each tile is mapped to the area of a single pixel in
	// the value noise texture, and therefore this directly controls the visible
	// size of the visible trough and peak shapes of this wave.
	//
	// Due to the shear mapping below, each tile is actually a parallelogram.
	// However, shear mapping preserves the length along each axis that each
	// tile occupies in the grid, it just slants the tile.
	vec2 tileSize;

	// Shear angle for the vertical shear mapping of the tile grid:
	// https://en.wikipedia.org/wiki/Shear_mapping
	// 
	// This is the angle in radians between the former horizontals and the
	// vertical (Z) axis. 90 degrees = no shear, 0 degrees = maximum shear
	// (not defined as tan(0) = 0)
	//
	// The shear angle may be negative, in which case the shear is in the
	// opposite direction as a  positive shear. Therefore, the acceptable range
	// of values is from -Pi/2 to Pi/2 (-90 degrees to 90 degrees), not
	// inclusive of either -90 degrees or 90 degrees.
	//
	// Diagrams for intuition:
	// 
	// Z
	// |
	// |+--H--+
	// ||     |
	// ||     |
	// |+--H--+
	// | Angle between Z and current horizontal: 90 degrees (shear angle)
	// | The shape is tilted by 0 degrees
	// +--------------X
	//
	// Z
	// |   /|
	// |  / |
	// | FH |
	// |/   /
	// ||  /
	// || FH (Former horizontal)
	// ||/
	// | Angle between Z and FH: 30 degrees (shear angle)
	// | The shape is tilted by 60 degrees
	// +--------------
	//
	float shearAngle;

	// The speed that the wave travels torwards its heading direction in meters
	// (blocks) per second.
	float speed;

	// The heading of the wave, in radians. This follows the unit circle except
	// our Z coordinate is the Y on the unit circle.
	float heading;

	// The weight of this particular wave. The height of each wave is multiplied
	// by its weight and then the sum of all wave weights is divided by the
	// total weight, such that the actual magnitude of this wave is given by
	// weight divided by totalWeight.
	float weight;
};

// Actual wave definitions - these values are converted in the boilerplate code
// below into the actual scales and offsets used at runtime.
#include "/environment/water/surface_noise_waves.glsl"

// We must take the inverse of the tile size (meters per noise pixel) to get the
// scaling factor from world space (noise pixels per meter).
//
// With shearing, the diagonal of the scale matrix remains unmodified, but we
// apply the shearing after scaling, so we multiply the X scale with the
// computed shearing factor. The shearing factor (m) is given by
// cot(shearAngle), equivalently, as GLSL lacks cotangent, 1.0 / tan(shearAngle)
//
// Since we only support X/Z scaling in combination with a vertical shear, while
// we can represent this as a 2D transformation matrix one of the elements will
// always be zero, so we store it as a vector instead where the first two
// components are the diagonal (X/Z scale) and the third element is the first
// column, second row value - in other words, the scaling factor applied to the
// X coordinate that gets added to the final Y position.
// 
// We could expand this to a mat2 like so: 
// mat2(stretch.x, stretch.z, 0.0, stretch.y)
//
// Mathematica / Mathics code useful for validating the shear multiplication:
//
// VerticalShearMatrix[T_] := {{1.0, 0.0}, {T, 1.0}}
// Simplify[Dot[VerticalShearMatrix[Shear], Dot[{{XScale, 0.0}, {0.0, YScale}},
//     {X, Y}]] // MatrixForm]
// Simplify[Dot[Dot[VerticalShearMatrix[Shear], {{XScale, 0.0}, {0.0, YScale}}],
//     {X, Y}] // MatrixForm]
// Simplify[Dot[VerticalShearMatrix[Shear], {{XScale, 0.0}, {0.0, YScale}
//     ] // MatrixForm]
const vec3 rippleStretch[4] = vec3[](
	vec3(1.0 / RIPPLES[0].tileSize.x, 1.0 / RIPPLES[0].tileSize.y,
		(1.0 / tan(RIPPLES[0].shearAngle)) / RIPPLES[0].tileSize.x),
	vec3(1.0 / RIPPLES[1].tileSize.x, 1.0 / RIPPLES[1].tileSize.y,
		(1.0 / tan(RIPPLES[1].shearAngle)) / RIPPLES[1].tileSize.x),
	vec3(1.0 / RIPPLES[2].tileSize.x, 1.0 / RIPPLES[2].tileSize.y,
		(1.0 / tan(RIPPLES[2].shearAngle)) / RIPPLES[2].tileSize.x),
	vec3(1.0 / RIPPLES[3].tileSize.x, 1.0 / RIPPLES[3].tileSize.y,
		(1.0 / tan(RIPPLES[3].shearAngle)) / RIPPLES[3].tileSize.x));

const vec3 crestStretch[2] = vec3[](
	vec3(1.0 / CRESTS[0].tileSize.x, 1.0 / CRESTS[0].tileSize.y,
		(1.0 / tan(CRESTS[0].shearAngle)) / CRESTS[0].tileSize.x),
	vec3(1.0 / CRESTS[1].tileSize.x, 1.0 / CRESTS[1].tileSize.y,
		(1.0 / tan(CRESTS[1].shearAngle)) / CRESTS[1].tileSize.x));

// Convert the speed and heading into the horizontal offset vector to multiply
// by time - we call this the "scroll" vector as it is the vector used to scroll
// the waves across the world as time passes.
//
// Essentially, we convert the speed and heading into a vector in world space,
// and then transform into the coordinate system of this particular wave.
//
// Finally, we multiply by negative 1. Why? Well, to make it look like the wave
// at (0, 0) moved 1 unit towards positive X, we must subtract 1 unit to make
// the wave that was at (0, 0) now appear at (1, 0) because (1 - 1, 0) is
// (0, 0), the original position of the wave.
const vec2 rippleScroll[4] = vec2[](
	-mat2(
		rippleStretch[0].x, 
		rippleStretch[0].x / tan(RIPPLES[0].shearAngle),
		0.0,
		rippleStretch[0].y)
	 * RIPPLES[0].speed
	 * vec2(cos(RIPPLES[0].heading), sin(RIPPLES[0].heading)),
	-mat2(
		rippleStretch[1].x, 
		rippleStretch[1].x / tan(RIPPLES[1].shearAngle),
		0.0,
		rippleStretch[1].y)
	 * RIPPLES[1].speed
	 * vec2(cos(RIPPLES[1].heading), sin(RIPPLES[1].heading)),
	-mat2(
		rippleStretch[2].x,
		rippleStretch[2].x / tan(RIPPLES[2].shearAngle),
		0.0,
		rippleStretch[2].y)
	 * RIPPLES[2].speed
	 * vec2(cos(RIPPLES[2].heading), sin(RIPPLES[2].heading)),
	-mat2(
		rippleStretch[3].x,
		rippleStretch[3].x / tan(RIPPLES[3].shearAngle),
		0.0,
		rippleStretch[3].y)
	 * RIPPLES[3].speed
	 * vec2(cos(RIPPLES[3].heading), sin(RIPPLES[3].heading)));

const vec2 crestScroll[2] = vec2[](
	-mat2(
		crestStretch[0].x,
		crestStretch[0].x / tan(CRESTS[0].shearAngle),
		0.0,
		crestStretch[0].y)
	 * CRESTS[0].speed
	 * vec2(cos(CRESTS[0].heading), sin(CRESTS[0].heading)),
	-mat2(
		crestStretch[1].x,
		crestStretch[1].x / tan(CRESTS[1].shearAngle),
		0.0,
		crestStretch[1].y)
	 * CRESTS[1].speed
	 * vec2(cos(CRESTS[1].heading), sin(CRESTS[1].heading)));

// Compute the magnitude of each wave layer at compile time by dividing each
// weight by the total weight, so we do not need to do this at runtime.
const float totalWeight = 0.0
		+ RIPPLES[0].weight
		+ RIPPLES[1].weight
		+ RIPPLES[2].weight
		+ RIPPLES[3].weight
		+ CRESTS[0].weight
		+ CRESTS[1].weight;

const float timeSecondsFixed = 500.0;

uniform vec4 waterScrollRippleAB = timeSecondsFixed * vec4(rippleScroll[0], rippleScroll[1]);
uniform vec4 waterScrollRippleCD = timeSecondsFixed * vec4(rippleScroll[2], rippleScroll[3]);

uniform vec3 waterStretchRippleA = rippleStretch[0];
uniform vec3 waterStretchRippleB = rippleStretch[1];
uniform vec3 waterStretchRippleC = rippleStretch[2];
uniform vec3 waterStretchRippleD = rippleStretch[3];

uniform vec4 waterMagnitudeRipple = vec4(
	RIPPLES[0].weight / totalWeight,
	RIPPLES[1].weight / totalWeight,
	RIPPLES[2].weight / totalWeight,
	RIPPLES[3].weight / totalWeight);

uniform vec4 waterScrollCrestAB = timeSecondsFixed * vec4(crestScroll[0], crestScroll[1]);

uniform vec3 waterStretchCrestA = crestStretch[0];
uniform vec3 waterStretchCrestB = crestStretch[1];

uniform vec2 waterMagnitudeCrest = vec2(
	CRESTS[0].weight / totalWeight,
	CRESTS[1].weight / totalWeight);

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
float antialiasFactor(vec2 ddxWorldPos, vec2 ddyWorldPos, vec3 stretch) {
	// Because the wave noise sampling position is just a uniform scroll plus
	// the stretched coordinate, its partial derivatives are the same as the
	// partial derivates of the stretched coordinate, therefore:
	//
	// * dFdx(at) = dFdx(stretched)
	// * dFdy(at) = dFdy(stretched)
	//
	// And, because we define stretched as:
	//
	//     stretched = vec2(worldPos.x * stretch.x, dot(worldPos, stretch.zy))
	//
	// Its partial derivatives are just the same operations on the partial
	// derivatives of the world position, for example for dFdx (same for dFdy):
	//
	// dFdx(stretched) = vec2(
	//     dFdx(worldPos).x * stretch.x,
	//     dot(dFdx(worldPos), stretch.zy));
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
	vec2 ddxAt = vec2(ddxWorldPos.x * stretch.x, dot(ddxWorldPos, stretch.zy));
	vec2 ddyAt = vec2(ddyWorldPos.x * stretch.x, dot(ddyWorldPos, stretch.zy));

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
	vec2 maxes = max(abs(ddxAt), abs(ddyAt));
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
	return mix(height, 0.5, aa);
}

// Assuming antialiasFactor returns a factor f, from the perspective of
// derivative it is just as if we multiplied the height by (1.0 - f) and
// otherwise added a constant.
//
// We can assume that f remains constant in the small local area around the
// point we are sampling, and therefore, (1.0 - f) is a constant factor in the
// multitplication that we can peel out and multiply by the gradient.
vec2 antialiasGradient(float aa, vec2 gradient) {
	return gradient * (1.0 - aa);
}

float waterRippleHeight(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	uint i,
	vec3 stretch,
	vec2 scroll
) {
	vec2 stretched = vec2(
		worldPos.x * stretch.x,
		dot(worldPos, stretch.zy));
	vec2 at = scroll + stretched;
	float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

	return waterMagnitudeRipple[i] * antialiasHeight(aa, smoothNoise2D(at));
}

// Returns water height between 0.0 and 1.0, with 0.0 being the lowest and 1.0
// being the highest.
//
// This function is responsible for adding together each wave layer into the
// final heightmap.
//
// Inputs: horizontal world position in meters, time in seconds
float WaterHeight(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
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
		vec3 stretch = i == 0u ? waterStretchCrestA : waterStretchCrestB;
		vec2 scroll = i == 0u ? waterScrollCrestAB.xy : waterScrollCrestAB.zw;
		
		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		vec2 at = scroll + stretched;
		float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

		height += waterMagnitudeCrest[i] * crest(
			antialiasHeight(aa, smoothNoise2D(at)));
	}

	return height;
}

float WaterHeight(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos
) {
	return WaterHeight(worldPos, ddxWorldPos, ddyWorldPos, false);
}

float WaterHeightApproximate(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos
) {
	return WaterHeight(worldPos, ddxWorldPos, ddyWorldPos, true);
}

#if !defined(USE_FDM_GRADIENT)

vec2 waterRippleGradient(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	uint i,
	vec3 stretch,
	vec2 scroll
) {
	// Same notes here as in the WaterHeight function
	vec2 stretched = vec2(
		worldPos.x * stretch.x,
		dot(worldPos, stretch.zy));
	vec2 at = scroll + stretched;
	float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

	vec2 waveGradient = (GRADIENT_STRENGTH * waterMagnitudeRipple[i])
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
		vec2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y));
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
vec2 WaterNGradientAnalytic(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos
) {
	vec2 gradient = vec2(0.0);

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
		vec3 stretch = i == 0u ? waterStretchCrestA : waterStretchCrestB;
		vec2 scroll = i == 0u ? waterScrollCrestAB.xy : waterScrollCrestAB.zw;
		
		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		vec2 at = scroll + stretched;
		float aa = antialiasFactor(ddxWorldPos, ddyWorldPos, stretch);

		// Antialiasing is a bit more involved in the gradients of these crest
		// waves.
		//
		// We need to compute the antialiased height at this position for use in
		// the chain rule for the derivative of the crest function, but we also
		// need to apply antialiasing to the returned gradient. Since we use
		// antialiasFactor twice, we have inlined antialiasHeight and
		// antialiasGradient here.
		float heightAt = mix(smoothNoise2D(at), 0.5, aa);

		// The main complexity here is that we need to apply the chain rule due
		// to the crest function.
		//
		// Other than that, this is fairly similar to above.
		vec2 waveGradient = (GRADIENT_STRENGTH * waterMagnitudeCrest[i])
			* gradSmoothNoise2D(at) * crestDerivative(heightAt);

		// Same notes apply as above, note that we have inlined the
		// functionality of antialiasGradient here.
		gradient -= (1.0 - aa) * 
			vec2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y);
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
vec2 WaterNGradientFDM(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos
) {
	// This is about the lowest I could go without major artifacts. The lower
	// you can go the better, but at some point we run out of floating-point
	// precision or hit limitations of the underlying sampling going on in the
	// wave funciton. Play around with this as needed.
	const float delta = 0.05;

	vec2 ddxPos = ddxWorldPos;
	vec2 ddyPos = ddyWorldPos;
	float h00 = WaterHeight(worldPos                   , ddxPos, ddyPos);
	float hX0 = WaterHeight(worldPos + vec2(delta, 0.0), ddxPos, ddyPos);
	float h0Y = WaterHeight(worldPos + vec2(0.0, delta), ddxPos, ddyPos);

	return (-GRADIENT_STRENGTH / delta) * (vec2(hX0, h0Y) - vec2(h00));
}

// Returns the normal map for the water surface computed from the gradient of
// the water surface heightmap.
//
// Inputs: horizontal world position in meters, time in seconds
// Output: normal vector in tangent space (X/Y = in-plane, Z = up out of the
// plane)
vec3 WaterNormal(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time
) {
	#if defined(USE_FDM_GRADIENT)
		vec2 minusGradient = WaterNGradientFDM(
			worldPos, ddxWorldPos, ddyWorldPos);
	#else
		vec2 minusGradient = WaterNGradientAnalytic(
			worldPos, ddxWorldPos, ddyWorldPos);
	#endif

	return normalize(vec3(minusGradient, 1.0));
}
