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

// Straightforward & fast but visually appealing displacement implementation.
// Utilizes custom uniforms defined in shaders.properties.
uniform float windStrengthHalf;
uniform float4 windTheta;

float3 WindDisplacement(float3 worldPos) {
	// Wind magnitude is given by a sine wave with a positional phase shift.
	// In other words, it cycles between 0 and the wind strength, and varies
	// with the block position, but in a continuous manner such that wind
	// appears to move in patches.
	float magnitude = sin(windTheta.w + worldPos.y + worldPos.z)
		* windStrengthHalf + windStrengthHalf;

	// Wind direction is given by a sine wave for each axis. Similarly, we shift
	// the phase based on position. In the vertical direction (y), we halve the
	// phase shift, as wind is horizontal, and making columns of leaves appear
	// to move as a more continuous unit makes the wind more convincing.
	float2 windPhaseShift = (worldPos.x + worldPos.z) * float2(1.5, 0.75);

	// Finally, compute the displacement vector as magnitude times direction.
	// The direction is given by 3 sine waves with a position-dependent phase
	// shift.
	//
	// To similarly make wind appear horizontal, the vertical magnitude is
	// halved.
	float3 direction = sin(windTheta.xyz + windPhaseShift.xyx);
	return float3(magnitude, magnitude * 0.5, magnitude) * direction;
}
