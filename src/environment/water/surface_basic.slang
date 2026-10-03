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

// There's a lot going on in this small function. By being clever, we can
// compress the calculation of the gradient (partial derivative with respect to
// X and partial derivative with respect to Y) of a given 3-wave pair in a given
// direction to: a dot, fma, cos, dot, and a final multiply, which on most GPUs
// should be a bunch of fma instructions plus a cos.
//
// === Why this is valid ===
//
// Given a wave function:
//
// W(x, y, dirX, dirY, time) =        sin(       x*dirX + y*dirY  + time)
//                           +  0.5 * sin(2.0 * (x*dirX + y*dirY) + time)
//                           + 0.25 * sin(4.0 * (x*dirX + y*dirY) + time)
//
// The derivative with respect to X would be:
//
// dW/dx = dirX * cos(       x*dirX + y*dirY  + time)
//       + dirX * cos(2.0 * (x*dirX + y*dirY) + time)
//       + dirX * cos(4.0 * (x*dirX + y*dirY) + time)
//
// We can peel out the x*dirX + y*dirY as the variable angle, leaving:
//
// dW/dx = dirX * cos(1.0 * angle + time)
//       + dirX * cos(2.0 * angle + time)
//       + dirX * cos(4.0 * angle + time)
//
// At this point the symmetry is starting to be obvious. We can write this
// as:
//
// dWdXeach = float3(
//   dirX * cos(1.0 * angle + time),
//   dirX * cos(2.0 * angle + time),
//   dirX * cos(4.0 * angle + time)
// )
//
// dW/dx = dWdXeach.x + dWdXeach.y + dWdXeach.z
//
// Which is equivalent to:
//
// dWdXeach = float3(
//   cos(1.0 * angle + time),
//   cos(2.0 * angle + time),
//   cos(4.0 * angle + time)
// )
//
// dW/dx = dirX * dWdXeach.x + dirX * dWdXeach.y + dirX * dWdXeach.z
//
// By definition, this is equivalent to:
//
// dWdXeach = cos(float3(1.0, 2.0, 4.0) * float3(angle) + float3(time))
// dW/dx = dot(float3(dirX), dWdXeach)
//
// Finally, we can note that the only function between dW/dx and dW/dy
// is multiplying by dirX or dirY, so we can share the common operations
// and only multiply in the direction at the end for a further win.
float2 gradWaterWave(float2 worldPos, float2 dir, float time) {
	float angle = dot(worldPos, dir);
	float dWdA = dot(
		cos(float4(angle) * float4(0.5, 1.0, 2.0, 4.0) + float4(time)),
		float4(1.0)
	);

	return float2(dWdA) * dir;
}

// This function uses a short sequence of pure ALU operations to generate some
// fairly nice-looking waves very efficiently.
//
// Inputs: horizontal world position, time in seconds
// Output: normal vector in tangent space (X/Y = in-plane, Z = up out of the
// plane)
float3 WaterNormal(
	float2 worldPos,
	float2 ddxWorldPos,
	float2 ddyWorldPos,
	float time
) {
	// Deform the wavefront using a sine wave as in real life, water does not
	// simply advance forward and straight diagonal wavefronts are entirely
	// unconvincing.
	worldPos += 0.125 * (sin(time * 2.0 + worldPos.yx * float2(2.0, 1.0)));

	// The phase varies over time to move the waves, and we also add in
	// random numbers to keep the waves out-of-phase of each other. 
	float4 phase = float4(time * 4.0) + float4(1.3657, 1.1345, 1.2290, 3.0297);

	// Since the derivative of two functions summed together is the sum of the
	// respective derivatives, we can calculate the gradients of each individual
	// directional wave quartet separately and just add them all together.
	float2 gradient;
	gradient  = 0.008 * gradWaterWave(worldPos, float2(1.0, 1.0),  phase.x);
	gradient += 0.004 * gradWaterWave(worldPos, float2(1.0, 0.66), phase.y);
	gradient += 0.008 * gradWaterWave(worldPos, float2(0.5, 0.75), phase.z);
	gradient += 0.004 * gradWaterWave(worldPos, float2(1.0, 0.33), phase.w);

	// Note that we are in tangent space, so in terms of directions, Z is the
	// direction going up out of the face, and the X/Y are side-to-side within
	// the face.
	return normalize(float3(gradient, 1.0));
}
