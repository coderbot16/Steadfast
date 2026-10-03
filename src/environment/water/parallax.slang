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

// Applies parallax mapping to a smooth water surface. Given a position in 2D
// world space, a time in seconds, and the vector of the intersection with the
// surface in this presumed world space (negative Z), it returns a shifted
// version of worldPos that gives depth to the water surface.
//
// The only oddity is viewVector - we treat it here as if it is in world space,
// but you probably want to actually pass it in tangent space. They happen to be
// the same when looking at water from the top which is the most common, but
// when looking at it from the bottom, the tangent space vector keeps Z negative
// while in world space, Z is actually positive - which breaks this function.
// From the side, you probably do not want to apply parallax mapping as water
// surfaces are strictly horizontal in the current code structure.
//
// This function relies solely on a previously-defined WaterHeight function of
// the form:
//
// float WaterHeight(float2 worldPos, float time);
//
// The height returned from that function MUST be in the range 0.0 to 1.0.
float2 WaterSurfaceParallaxMapping(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos,
	float3 viewVector
) {
	// We are tracing through a surface that is 1 meter thick. One factor that
	// is slightly modified from traditional parallax mapping is that we work
	// with a height function rather than a depth function. As a result, our
	// entry into the surface is a height of 1.0 and we continually lower our
	// height as we trace into the surface.
	//
	// For a traditional depth approach, we would have started at a depth of 0.0
	// and have went "deeper" into the surface by increasing the current depth
	// value.
	float currentHeight = 1.0;

	// We use a much lower number of iterations than most parallax methods which
	// use 16-32 iterations and scarcely go below 8 iterations. This is possible
	// because we are working with a smooth surface and can apply a strong
	// approximation - details within the loop.
	static const float ITERATIONS = 4;

	// Scale the view vector such that the Z component is -1.0. Once we do this,
	// we can drop the Z component, because it is always -1.0.
	//
	// Why -1.0? With our convention of decreasing height rather than increasing
	// depth, certainly Z cannot be positive as otherwise we are not actually
	// tracing into the surface! And since this fragment is on-screen and from
	// a face that faces the camera, we certainly must be tracing into the
	// surface.
	float2 posStep = viewVector.xy / abs(viewVector.z);

	for (uint i = uint(0); i < uint(ITERATIONS); i++) {
		// Determine the height of the surface at the current position.
		float sampleHeight = WaterHeightApproximate(
			worldPos,
			ddxWorldPos,
			ddyWorldPos);

		// We have scaled the view vector such that adding it to the current
		// position would take us from the top of the surface to the bottom of
		// the surface if we added XY to the texture coordinate and Z to the
		// height.
		// 
		// Since we are doing multiple iterations, scale the step length such
		// that we trace from surface top to surface bottom over the course of
		// all iterations.
		float stepLength = 1.0 / ITERATIONS;

		// The critical improvement over standard parallax techniques is that at
		// every iteration, we scale the step length by our distance above the
		// surface.
		//
		// Essentially, as we approach the surface, we slow down. If we are only
		// 0.1 meters above the surface at the very start, this means that we
		// will use our 4 iterations to step through that 0.1 meter distance,
		// rather than blowing right past it.
		// 
		// Since the surface is smooth at the nearby distances we are applying
		// parallax mapping, this approximation appears to work very well.
		//
		// Note that if currentHeight <= sampleHeight, we do not want to step
		// backwards, so in that case set the step length to 0.0.
		stepLength *= max(currentHeight - sampleHeight, 0.0);

		// Finally, advance along the ray. This is written out like a fused
		// multiply-add but is equivalent to:
		//
		// worldPos += posStep * stepLength
		worldPos = (posStep * stepLength) + worldPos;

		// Since we already scaled the view vector by Z such that Z is -1.0, we
		// can just subtract the step length from the height.
		currentHeight -= stepLength;

		// As in Steep Parallax Mapping, if we are now intersecting the surface,
		// we immediately return that new position.
		if (currentHeight <= sampleHeight) {
			break;
		}
	}

	return worldPos;
}
