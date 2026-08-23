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

// A planar clouds implementation that supports high-altitude cirrus-like cloud
// patterns. This implementation has been fairly aggressively optimized so that
// enabling these is almost free, since this is just a pile of texture sampling,
// fused multiply-add, and a few other miscellaneous arithmetic operations.

#define PLANAR_CLOUD_LAYERS 1 // Number of layers of planar clouds [0 1 2 3 4]

// Only enable clouds if we need to draw cloud layers
#if PLANAR_CLOUD_LAYERS > 0
#define CLOUDS_ENABLED

// 2D value noise based on texture sampling. Since texture sampling has special
// optimizations by the hardware, it's actually faster to sample a texture than
// to recreate value noise in shader code as the hardware will handle the linear
// interpolation for us, and memory reads from cache are incredibly cheap.
//
// The texture definitely fits in cache since it's so small!
#include "/lib/valueNoise.glsl"

uniform float cloudDensityScale;
uniform float cloudDensityThreshold;

#define PLANAR_CLOUD_COVERAGE 2.0 // [1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

float cirrusCloudPlane(float seconds, vec3 channel, vec2 at) {
	// Distort the sampling position with time and noise so that we don't have
	// completely straight lines of cloud noise. This approximates all the sorts
	// of wind effects that normally induce this sort of chaos.
	vec2 distorted = at;

	// at is only used to compute distorted from this point on. This makes the
	// clouds sway side-to-side as they move as this causes the distortion
	// directions to constantly change.
	at.x -= seconds * 0.04;

	// noise returns 0.0 to 1.0 but we want -1.0 to 1.0 so we offset in all
	// directions. This one distorts in all directions to prevent clouds from
	// being straight lines.
	distorted += 0.1 * (noise(channel, at * (1.5 * noisePixel)) * 2.0 - 1.0);

	// Then offset forward/back along the primary direction of the clouds to add
	// some chaos in the diagonal parts
	distorted.x += 1.6 * (noise(channel, at * (0.1 * noisePixel)) * 2.0 - 1.0);

	// The primary density sample for our our clouds which defines their larger
	// scale shape. It is stretched along the X axis to form a characterisic
	// long, windswept cloud shape.
	//
	// It is unique because not only is is the primary (56%) contribution to the
	// overall density, it is also used to offset all the other sampling
	// positions accordingly to fight value noise artifacts and add some
	// critical chaos to the sampling.
	float primary = noise(channel, distorted * (noisePixel * vec2(0.2, 1.0)));

	// In addition to the higher-frequency noise used to define the clouds,
	// use some much lower-frequency noise to decide what parts of the sky will
	// have clouds at all. This breaks up the uniformly random clouds, which
	// otherwise look unnatural and repetitive.
	float coverage = PLANAR_CLOUD_COVERAGE;
	float coverageNoise = noise(channel, at * (vec2(0.05, 0.2) * noisePixel));
	primary *= min(1.0, pow(coverage * coverageNoise, 4.0));

	// The three midrange noise contributions. They all come of the same form:
	//
	// - Add in an offset derived from the time, to distort the value noise grid
	//   in varying ways over time.
	// - Add in an offset derived from the primary noise sample, so that the
	//   contribution is nonuniform across a given cloud, further adding chaos.
	// - Finally, the most important part, the actual samping position is
	//   stretched in various forms to achieve various effects.
	//
	// For the second most significant contribution (28%), we just stretch the
	// position in the same way as the primary one, to further emphasize the
	// stretched look.
	//
	// In all these cases, all of the offsets and distortions, in addition to
	// adding to the chaotic look, are also necessary to conceal the blocky and
	// star-shaped artifacts of value noise, which would otherwise produce very
	// unconvincing clouds.
	//
	// For the other 2 midrange contributions, we stretch the sampling position
	// diagonally, producing a distinctive "feathered" appearance. These
	// contributions account for 12% of the final density value.
	float density = 0.56 * primary;

	density += 0.28 * noise(channel,
		distorted * (noisePixel * vec2(0.4,   2.0))
		+ seconds * (noisePixel * vec2(0.008, 0.0))
		+ primary * (noisePixel * vec2(0.5,   1.5))
	);
	
	density += 0.08 * noise(channel,
		distorted * (noisePixel * 3.3               )
		+ seconds * (noisePixel * vec2(0.064, 0.002))
		+ primary * (noisePixel * vec2(6.0,   3.0  ))
	);

	density += 0.04 * noise(channel,
		distorted * (noisePixel * 10.0             )
		+ seconds * (noisePixel * vec2( 0.32, 0.02))
		+ primary * (noisePixel * vec2(18.0,  9.0 ))
	);

	// Add in some final high-frequency details. Their contributions are subtle,
	// but they provide some much-needed noise on top of the paintbrush-like
	// appearance of the clouds produced by the previous contributions.
	//
	// We shift the coordinate around by the primary density contribution so
	// that the pattern is not entirely uniform across the clouds - we are
	// trying very hard to conceal the obvious artifacts of the very cheap value
	// noise function we are using.
	//
	// We also scroll the coordinate slowly with time - not too fast such that
	// the value noise is visible against a background of painting-like clouds,
	// but not too slow such that the painting-like clouds are visible against
	// a background of value noise.
	vec2 offset = seconds * (noisePixel * vec2(0.64, 0.04))
	            + primary * (noisePixel * vec2(64.0, 32.0));

	density += 0.02 * noise(channel, distorted * (noisePixel *  32.0) + offset);
	density += 0.01 * noise(channel, distorted * (noisePixel * 128.0) + offset);

	// The smoothstep function allows dynamically adjustment of the coverage
	// thresholds and clamping the result to a range all at once, and is a good
	// basis for our own formula.
	//
	// The first two parameters define the edges of the range of inputs that
	// will have a smooth transition. All inputs less than the lower bound will
	// be 0, all inputs greater than the upper bound will be 1, and all in
	// between will have a gradual and smooth transition from 0 to 1.
	//
	// The basis smoothstep formula here would be:
	//
	//   float t = clamp((density - edge0) / (edge1 - edge0), 0.0, 1.0);
	//   float alpha = t * t * (3.0 - 2.0 * t);
	//
	// Two adjustments are made:
	//
	// 1. We multiply density by 0.7 since we don't really ever want 1.0 alpha
	//    for clouds.
	// 2. Because of that, we never hit the right edge of the smoothstep, so we
	//    can skip it and use a slightly different curve. We need to adjust the
	//    clamp accordingly.
	//
	// This results in:
	//
	//  float t = clamp((density * 0.7 - edge0) / (edge1 - edge0),
	//                  0.0, 1.0 / sqrt(2.5));
	//  float alpha = 2.5 * (t * t);
	//
	// With this clamping range, alpha is guaranteed to be 0.0 to 1.0. However,
	// we want to peel everything we can out into uniforms or constants, ending
	// in the following - note that cloudDensityScale and cloudDensityThreshold
	// here hoist the edge0/edge1 calculations to custom uniforms, leaving a
	// fused multiply-add operation:
	const float a = 2.5;
	const float aInvSqrt = 1.0 / sqrt(a);

	float scaledDensity = density * cloudDensityScale;
	float t = clamp(scaledDensity + cloudDensityThreshold, 0.0, aInvSqrt);
	return a * (t * t);
}

// For a given 2D position in the noise texture, we have 3 random values. This
// means we can construct our own pseudorandom values by computing the dot
// product with a given "noise channel".
const vec3[4] noiseChannels = vec3[4](
	vec3(1, 0, 0),
	vec3(0, 1, 0),
	vec3(0, 0, 1),
	vec3(0.33, 0.33, 0.34)
);

// This can appear in any order. Normally, translucent blending requires strict
// ordering, but because the color of clouds is constant we don't need to retain
// that.
const float[4] scales = float[4](-5, -2, -7.5, -1);

// A few control parameters for mixing in the final cloud color
uniform vec3 cloudColor;
uniform float cloudFade;

vec3 blendCirrusClouds(vec3 skyColor, vec2 intersectPos) {
	// Fade clouds out with distance
	float fade = cloudFade * max(0.0, 1.0 - length(intersectPos) / 4.0);

	// No point in sampling the cloud planes if we're going to
	// fully fade out the result anyways.
	if (fade <= 0.0) {
		return skyColor;
	}

	// Whether to freeze animations (useful for testing).
	//#define FREEZE_ANIMATION_TIMER
	#ifdef FREEZE_ANIMATION_TIMER
		// Non-zero, as otherwise the time term gets cancelled out and we might
		// miss a significant change.
		float timeSeconds = 500.0;
	#else
		float timeSeconds = frameTimeCounter;
	#endif

	// Each iteration, we do translucent blending of a cloud plane into the sky.
	// However, because we are using the same cloud color each time, we can 
	// simplify like so:
	//
	// 1. mix(mix(skyColor, cloudColor, A), cloudColor, B)
	// 2. (1.0 - B) * (mix(skyColor, cloudColor, A)) + cloudColor * B
	// 3. (1.0 - B) * ((1.0 - A) * skyColor +  cloudColor * A) + cloudColor * B
	// 4. (1.0 - B) * (1.0 - A) * skyColor + cloudColor * (1.0 - B) * A
	//    + cloudColor * B
	// 5. (1.0 - B) * (1.0 - A) * skyColor + cloudColor * (A - AB + B)
	//
	// An important note is that since the cloud alpha should not be too high
	// (as that looks ugly, IMO), the product AB ends up being quote small.
	//
	// A decent approximation is just assuming that AB is zero, which seems to
	// work & I did not see any sort of noticeable difference. This helps
	// simplify the blending to something that does not require explicit
	// translucent blending order, and also saves some math operations:
	//
	// (1.0 - B) * (1.0 - A) * skyColor + cloudColor * (A + B)
	//
	// This is the blending equation implemented below.

	float cloudColorWeight = 0.0;
	float skyColorWeight = 1.0;

	for (int q = 0; q < PLANAR_CLOUD_LAYERS; q++) {
		float alpha = fade * cirrusCloudPlane(
			timeSeconds,
			noiseChannels[q], 
			scales[q] * intersectPos
		);

		cloudColorWeight += alpha;
		skyColorWeight *= 1.0 - alpha;
	}

	return skyColor * skyColorWeight + cloudColor * cloudColorWeight;
}

// Given the background sky color and a world-space ray for this position in the
// sky, return a blended cloud color.
vec3 BlendClouds(vec3 skyColor, vec3 worldSpaceRay) {
	// Ray-plane intersection based on this linear algebra StackExchange post:
	// https://math.stackexchange.com/a/4402157
	//
	// Ray origin is not needed but is used here just to be faithful to the
	// algorithm in the post for clarity.
	//
	// The original algorithm is:
	//
	//   intersectionDistance =
	//       dot(planeNormal, planePoint - rayOrigin)
	//     / dot(planeNormal, rayDirection)
	//
	// Where planeNormal and planePoint define a plane in point-normal form, and
	// rayOrigin/rayDirection define the ray. If the intersection distance is
	// negative, then there is no intersection.
	//
	// We can make a few simplifications. rayOrigin is always (0, 0, 0), and
	// since we are in world-space, the normal for the flat plane of the clouds
	// is just (0, 1, 0). In addition, we will use a plane point (0, H, 0),
	// where H is the cloud height.
	//
	//   intersectionDistance =
	//       dot(vec3(0, 1, 0), vec3(0, H, 0))
	//     / dot(vec3(0, 1, 0), rayDirection)
	//
	// This simplifies to:
	//
	//   intersectionDistance = H / rayDirection.y
	//
	// We can assume that intersectPos given an origin of (0, 0, 0) is:
	//
	//   intersectPos = rayDirection * intersectionDistance
	//
	// Plugging in the previous values, we get:
	//
	//   intersectPos = rayDirection * (H / rayDirection.y)
	//
	// Which we can simplify to:
	//
	//   intersectPos = H * (rayDirection.xyz / rayDirection.y)
	//
	// Since we don't care about the Y component (given it is H), this further
	// simplifies to:
	//
	//   intersectPos2D = H * (rayDirection.xz / rayDirection.y)
	//
	// Given that we can pull out H as a coefficient, we can set it to 1.0 for
	// the purposes of intersection and multiply it in later, giving:
	//
	//   intersectPos2DUnscaled = rayDirection.xz / rayDirection.y
	if (worldSpaceRay.y <= 0.0) {
		return skyColor;
	}

	// Convert to 2D and then dispatch to the planar clouds logic
	return blendCirrusClouds(skyColor, worldSpaceRay.xz / worldSpaceRay.y);
}

#endif
