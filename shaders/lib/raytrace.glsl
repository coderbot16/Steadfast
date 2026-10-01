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

// This is an improved ray marching implementation inspired by a few ideas from
// Chocapic13's shaders:
//
// - Rapidly accelerate the ray through the scene to quickly find an initial hit
//   and then upon a hit step more slowly through the previous ray interval.
//   This enables aggressive undersampling to avoid spending steps on empty
//   space, which is very common in open-water scenes.
// - Yet, starting off slow permits good local reflections as well
//
// It also has a few of my own improvements on top of those:
//
// - Modify the thickness in a similar fashion to the ray velocity, so that
//   nearby reflections have a slow thickness in meters and far ones have a high
//   thickness. This avoids ugly local results while not making faraway ones too
//   noisy.
// - If we run out of steps while refining, return the last valid hit to avoid
//   returning MISS when we actually have a fairly good hit saved.
//
// Combined, this gives decent-quality reflections using simple, intuitive ray
// marching and a small number of steps, independent of screen resolution.

// The maximum permitted thickness (meters) of a reflection hit.
//
// Thickness allows for inherent imprecision and means that even if we do not
// have an exact perfect match, we can accept a fragment for the reflection.
//
// If this is too low, you will have holes and noise, and if this is too high,
// you will have ugly stretchy reflections.
const float MAX_THICKNESS = 8.0;

// More steps give extra opportunities for refinements and similar, but also
// come at a potential performance cost for rays that travel very far without
// making a hit or escaping the frustum.
//
// Even if we make a hit, we'll still take a lot of steps to refine
const uint RAYMARCH_STEPS = 24u;

// How much to accelerate each step - this allows us to cover long distances
// with simple raymarching without excessive steps or excessive oversampling,
// in fact, it allows fairly aggressive undersampling, and if we overshoot
// (see below) we can retrace at a slower velocity.
const float ACCELERATION_FACTOR = 2.0;

// How many rounds of recursive refinement to attempt. Each refinement round
// results in us retracing the last traced interval at a slower speed, and may
// take multiple individual steps (see TAPS_PER_REFINEMENT).
//
// With 4 rounds of 4 taps, we're spending up to 20 steps on refinement: 1 step
// each refinement round on hitting and rolling back, and 4 steps on checking
// within that interval.
const uint MAX_REFINEMENT_ROUNDS = 4u;

// During each refinement round, we elect to dedicate a certain number of steps
// (TAPS_PER_REFINEMENT) to that individual round, and cover a certain
// percentage of the original step distance (REFINEMENT_DISTANCE) that lead us
// to the intersection. We deliberately do not cover the whole distance, as we
// save the last hit that was at the end of the distance and can use that in the
// worst case.
//
// Given a certain TAPS_PER_REFINEMENT, we can calculate the factor to reduce
// the velocity by using pow(1 / ACCELERATION_FACTOR, TAPS_PER_REFINEMENT),
// which ensures that we will take TAPS_PER_REFINEMENT steps given the
// acceleration factor.
//
// Then, we add one, because we always multiply by ACCELERATION_FACTOR every
// step, including the one directly after initiating this refinement.
//
// Finally, we multiply in the REFINEMENT_DISTANCE at the very end - a value of
// 0.75 means that we cover 75% of the original distance in this refinement
// round.
const float TAPS_PER_REFINEMENT = 4.0;
const float REFINEMENT_DISTANCE = 0.75;
const float refinementDecelerationFactor = (REFINEMENT_DISTANCE
	* pow(1 / ACCELERATION_FACTOR, TAPS_PER_REFINEMENT + 1));

// thicknessControl impacts the base thickness and increase in thickness over
// distance during raytracing, effectively the tolerance of determinining
// whether we are going to accept a hit or not.
//
// X: initial thickness in meters
// Y: additional increase in meters per raytracing step not directly related to
//    distance
bool Raytrace(
	sampler2D depthBuffer,
	float4x4 gbufferProjection,
	float4x4 gbufferProjectionInverse,
	float3 viewPos,
	float3 reflectDirection,
	float2 thicknessControl,
	out float2 hitPos,
	out float3 hitViewPos
) {
	// State variables for refinement
	uint refinementRounds = 0u;
	bool hasHitPos = false;

	// Initial velocity and thickness
	//
	// Stored together in case the shader compiler likes a single float4
	// better than a float3 + float.
	float4 velocityAndThickness = float4(reflectDirection, thicknessControl.x);

	// If the reflection is towards the viewer, immediately reject it since no
	// good reflection is really feasible here.
	if (dot(viewPos, reflectDirection) < 0.0) {
		return false;
	}

	for (uint i = 0u; i < RAYMARCH_STEPS; i++){
		// Each step, accelerate by a certain factor to avoid oversampling
		// near the end of the ray march.
		//
		// We also expand the thickness accordingly, as using a constant
		// thickness means that no thickness is actually ideal.
		//
		// But varying it means that we can use a very restrictive thickness
		// when doing small steps and then widen it when doing large strides.
		//
		// Starting small and then increasing prevents tree fragments above you
		// from being reflected in water in front of you.
		velocityAndThickness *= float4(
			float3(ACCELERATION_FACTOR),
			ACCELERATION_FACTOR * thicknessControl.y);

		// Prevent thickness from getting too large as that will mean far
		// distances have undesirable stretching.
		float thicknessM = min(
			velocityAndThickness.w,
			MAX_THICKNESS / refinementRounds);

		// The range of Z values we will permit lies between where we started
		// and where we are advancing to.
		//
		// Note that these view-space Z values are negative, so the thickness
		// +/- is widening the range, not narrowing it. See below for a more
		// detailed explanation on how this works.
		float minZ = viewPos.z + thicknessM;
		viewPos += velocityAndThickness.xyz;
		float maxZ = viewPos.z - thicknessM;

		// Convert view position to NDC (-1.0 to 1.0) coordinates.
		float4 clipPos = gbufferProjection * float4(viewPos, 1.0);
		float3 ndcPos = clipPos.xyz / clipPos.w;

		// Check if the NDC coordinates still lie within the screen.
		// If any coordinate goes below -1 or above 1, it's definitely
		// outside of the screen.
		float3 absNdcPos = abs(ndcPos);
		float maxNdc = max(max(absNdcPos.x, absNdcPos.y), absNdcPos.z);
		if (maxNdc > 1.0) {
			// We escaped the screen, reject the raytracing.
			return false;
		}

		// Use the depth buffer and matrices to get the view Z coordinate for
		// this 2D screen position. We need the screen position to sample the
		// depth buffer, but otherwise we can remain in NDC space as much as
		// possible as we need the NDC position to get the view position.
		float2 screenPos2D = ndcPos.xy * 0.5 + 0.5;
		ndcPos.z = texture(depthBuffer, screenPos2D).x * 2.0 - 1.0;
		float4 homogenousPos = gbufferProjectionInverse * float4(ndcPos, 1.0);
		float sampledViewZ = homogenousPos.z / homogenousPos.w;

		// Intersections are odd because the Z values are all negative. What we
		// want is:
		// abs(minZ) - thickness < abs(sampledViewZ) < abs(maxZ) + thickness
		//
		// But what that really means is:
		// -minZ - thickness < -sampledViewZ < -maxZ + thickness
		//
		// This can be expanded as:
		// -(minZ + thickness) < -sampledViewZ
		// AND -sampledViewZ < -(maxZ - thickness)
		//
		// Using the rules of inequalities, we can rewrite this as:
		// minZ + thickness > sampledViewZ AND sampledViewZ > maxZ - thickness
		//
		// And we can pull the thickness calculations to above.
		if (minZ > sampledViewZ && sampledViewZ > maxZ) {
			// This was a successful hit. Save it so that we will at least
			// return this hit if we don't find a better one.
			hasHitPos = true;
			hitPos = screenPos2D;
			hitViewPos =
				float3(homogenousPos.xy / homogenousPos.w, sampledViewZ);

			// Undo the last raymarch and decelerate so we can try to trace a
			// more precise hit.
			viewPos -= velocityAndThickness.xyz;
			velocityAndThickness *= refinementDecelerationFactor;

			// Refine for a certain number of steps at the end before declaring
			// a successful hit, to improve the accuracy of reflections.
			refinementRounds += uint(1);

			// If we've already refined sufficiently, return this result as-is.
			if (refinementRounds >= MAX_REFINEMENT_ROUNDS) {
				return true;
			}
		}
	}

	// No hit on this iteration, return the valid hit if we had one.
	return hasHitPos;
}
