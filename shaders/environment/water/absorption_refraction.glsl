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

// Apply a water absorption heuristic using the results of a refraction trace.
vec3 RefractionBasedWaterAbsorption(
	vec3 refractedScreenPos,
	vec3 viewPosRefracted,
	vec3 upVector,
	vec3 viewPos,
	bool verticalNormal,
	vec3 background,
	sampler2D skylightBuffer
) {
	float waterDepth;

	if (refractedScreenPos.z < 1.0) {
		// The incident vector only gives a reasonable indication of the water
		// depth when hitting water's top face. As a result, we use the sky
		// light value of the background when reflecting through water sides or
		// when underwater, since in those cases it is a more reliable
		// heuristic.
		if (verticalNormal) {
			// We take the vector between the refracted position (sea floor) and
			// the origin position (ocean surface), and then use the dot product
			// to measure the vertical distance between the two, as the upVector
			// in view space is equivalent to (0, 1, 0) in world space.
			//
			// This is equivalent to subtracting the Y components in world
			// space, but avoids some matrix transformations and similar.
			//
			// This only requires assuming that a straight line in world space
			// is also straight in view space, which we already assume in the
			// refraction trace & reflection tracing code.
			float depthInMeters = dot(viewPos - viewPosRefracted, upVector);

			// This is the reference equation for water depth, where the depth
			// starts at 1.0 at the surface, and goes to a maximum of 1.0 at 15
			// blocks below the water surface, which is intentionally within the
			// same range as sky light attenuation (see details below.
			waterDepth = clamp(
				depthInMeters + 1.0,
				0.0,
				16.0);
		} else {
			float skylight = RefractionSafeSample(
				skylightBuffer,
				refractedScreenPos.xy
			).r;

			// Skylight is attenuated by 1 per vertical meter below the water
			// surface, so we can use that to determine the depth up to 16
			// meters. Start off at 1 meter of depth so that water near the
			// surface is not excessively clear.
			waterDepth = (-15.0) * skylight + 16.0;
		}

		// TODO: Based on the render distance, fade away to the background to
		// have a smooth transition!
	} else {
		// In this case, we hit a sky fragment, and naturally there is no
		// skylight or reasonable world Y height available or reasonable world
		// Y height available.
		//
		// Instead, we just have to assume that most of the time this means that
		// we went through a lot of water, that is, we are at full water depth
		// (ie, full water depth). This works most of the time, but sometimes
		// (ie, looking at a waterfall), the water is not actually that thick,
		// so this looks off.
		//
		// To mitigate this, as a heuristic, if we are within 40 meters of this
		// water surface, then we start to assume that the water is not actually
		// that thick and do not apply as much water absorption.
		//
		// Note: This is also required to see the sun/moon through less thick
		// volumes of water.
		float fadeFactor = min(-viewPos.z / 24.0, 1.0);
		waterDepth = 4.0 + 12.0 * fadeFactor;
		background *= 1.0 - fadeFactor;
	}

	// Beer's law for attenuation to simulate water absorption
	return background * exp(WATER_ATTENUATION_COEFFICIENTS * waterDepth);
}
