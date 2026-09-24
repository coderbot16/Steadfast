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

// NOTE: /lib/spaces.glsl must already be included here.

#ifdef MC_GL_ARB_texture_gather
	// If textureGather is available, use that to pass/fail refracted fragments
	// while maintaining bilinear filtering when sampling the color texture.
	#define REFRACTION_REJECT_MODE_GATHER
#else
	// Otherwise, we have to fall back to nearest neighbor filtering, which
	// gives a more aliased result.
	//
	// We could sample depth 4 times, but that would be an excessive hit for a
	// barely-noticeable gain.
	uniform float viewWidth;
	uniform float viewHeight;
#endif

// Returns a vec2 containing the minimum depth (x) and maximum depth (y) at the
// given position in the depth buffer.
vec2 depthRange(sampler2D depthBuffer, vec2 at) {
	#if defined(REFRACTION_REJECT_MODE_GATHER)
		// We need to be careful with exactly HOW we determine if the hit is
		// closer - this is because the position is not necessarily centered on
		// a single texel in the texture we are sampling.
		//
		// If we naively sample the depth texture with texture(depthBuffer, at),
		// on boundaries between pass/fail areas there will be a small "fringe"
		// effect where bilinear filtering of the depth texture will linearly
		// interpolate vastly different depth values, giving garbage results.
		//
		// NOTE: We are using textureGather from the ARB extension, which does
		// not support the optional "component" argument. Since we just need the
		// "x" component, this is OK since that is the default!
		vec4 refractDepthX4 = textureGather(depthBuffer, at);

		// We got 4 depth values, so pick the minimum one as the comparison
		// below is a greater-than check. Since depth is nonlinear, we cannot do
		// any sort of weighting or linear interpolation without significant
		// complexity. This looks good enough as-is.
		float minDepth = min(
			min(refractDepthX4.x, refractDepthX4.y),
			min(refractDepthX4.z, refractDepthX4.w)
		);

		float maxDepth = max(
			max(refractDepthX4.x, refractDepthX4.y),
			max(refractDepthX4.z, refractDepthX4.w)
		);

		return vec2(minDepth, maxDepth);
	#else
		// Fallback approach - if we cannot use textureGather, force nearest
		// filtering by using texelFetch. Maybe we could just set nearest 
		// filtering on depthBuffer globally, but I am not sure if that matters
		// for performance?
		return vec2(texelFetch(
			depthBuffer,
			ivec2(at * vec2(viewWidth, viewHeight)),
			0
		).x);
	#endif
}

float min_depth(vec2 range) {
	return range.x;
}

float max_depth(vec2 range) {
	return range.y;
}

// Actually tracing or marching a ray would be way too expensive for refraction,
// and in fact looks bad because in refraction we do not really want to reject
// hits if we can avoid it.
//
// Instead, we need a faster way to determine the hit position or an
// approximation of it. This is actually fairly feasible given our refract
// direction calculation - as we deliberately have made sure that the refract
// direction isn't offset too significantly from the incident vector, we can
// avoid tracing along the ray and skip to the end.
//
// That is, we take the direction of the ray, and since the refracted position
// is close to the background position, we determine the depth of the
// background, assume it is similar to the depth of the refracted position, and
// jump to that depth along the ray. While the actual distance along the ray
// will be greater or less, since the refracted position and background
// position are usually close enough, this looks acceptable most of the time.
vec3 RefractTrace(
	sampler2D depthBuffer,
	mat4 gbufferProjection,
	mat4 gbufferProjectionInverse,
	vec3 viewPos,
	vec3 refractDirection,
	float maxRefractDistance
) {
	// First part: Determine the depth of the background at this point
	// (copied from reflection code)
	// TODO: Don't repeat yourself
	// TODO: Start off with gl_FragCoord instead?
	vec4 clipPos = gbufferProjection * vec4(viewPos, 1.0);
	vec3 ndcPos = clipPos.xyz / clipPos.w;
	vec2 backgroundPos2D = ndcPos.xy * 0.5 + 0.5;
	float backgroundDepth = max_depth(depthRange(depthBuffer, backgroundPos2D));
	ndcPos.z = backgroundDepth * 2.0 - 1.0;
	vec4 homogenousPos = gbufferProjectionInverse * vec4(ndcPos, 1.0);
	float backgroundViewPosZ = homogenousPos.z / homogenousPos.w;

	// Second part: Advance by that distance along the refracted ray, to get the
	// position in view space that is close to where the refracted ray is
	// expected to hit. It is sufficient to only consider the Z component here,
	// as in view space the camera rotation has been applied and Z is the depth.
	float refractDistance = min(
		abs(viewPos.z - backgroundViewPosZ),
		maxRefractDistance);
	vec3 viewPosRefracted = viewPos + refractDirection * refractDistance;

	// Given that refracted position in view space, we want to then sample to
	// get a fragment visible on-screen. While that is already almost certainly
	// the case due to our deliberate work to make refracted positions
	// relatively close to the original background position, it is still
	// important to have a fallback.
	//
	// As a result, when the refracted position is in the bottom, top, left, or
	// right 10% of the screen, we gradually transition the refracted position
	// to lie at the original background location.
	//
	// Combined with the tuned refraction direction calculation, this makes the
	// limitations of the screen-space method here nearly invisible.
	vec4 refractedClipPos = gbufferProjection * vec4(viewPosRefracted, 1.0);
	vec2 refractedPosNdc = refractedClipPos.xy / refractedClipPos.w;
	vec2 hitPosAbs = abs(refractedPosNdc);
	float hitPosMax = max(hitPosAbs.x, hitPosAbs.y);
	float visibility = min(1.0, (1.0 - hitPosMax) / 0.10);

	vec2 refractedPos2D = refractedPosNdc * 0.5 + 0.5;
	refractedPos2D = mix(backgroundPos2D, refractedPos2D, visibility);

	// Rare case - if our refract hit is closer to us than where we are
	// refracting from, it's definitely not a valid hit. This happens near the
	// edge of water sometimes. If that is the case, reject the hit and just use
	// the original background position (as if we did not refract at all)
	//
	// Note: Use if defined(...) to avoid this getting picked up as a
	// configurable option.
	vec2 refractDepthRange = depthRange(depthBuffer, refractedPos2D);
	float refractDepth = max_depth(refractDepthRange);

	if (gl_FragCoord.z > min_depth(refractDepthRange)) {
		refractedPos2D = backgroundPos2D;
		refractDepth = backgroundDepth;
	}

	return vec3(refractedPos2D, refractDepth);
}

// Samples the given texture at a given position, with the right sampling mode
// to avoid bleeding from texels that are not behind the refractive surface.
vec4 RefractionSafeSample(sampler2D colorBuffer, vec2 at) {
	#if defined(REFRACTION_REJECT_MODE_GATHER)
		// Bilinear interpolation is safe because we previously confirmed that
		// all 4 texels pass our depth check.
		return texture(colorBuffer, at);
	#else
		// Fall back to nearest filtering when textureGather is unavailable.
		return texelFetch(colorBuffer,
			ivec2(at * vec2(viewWidth, viewHeight)), 0);
	#endif
}
