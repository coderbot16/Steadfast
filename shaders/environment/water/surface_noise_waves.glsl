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

// Convenience constant to express degree measurements, used in the wave
// definitions file.
#define Degrees radians(1.0)

// Actual wave measurements/definitions used by the Noise water surface
// implementation.
//
// The parameters of these waves have been selected to give a similar appearance
// to SEUS-11.0 and SEUS Renewed. In fact, the waves in SEUS PTGI are actually
// just SEUS Renewed waves scaled by a factor of 4 so that they appear to have a
// much higher frequency. However, this makes the tiling artifacts way more
// obvious and IMO, they look worse, but this was likely a necessary tradeoff so
// that the baked water caustics texture used by SEUS PTGI (as opposed to the
// procedural caustics of Renewed) could be kept to a smaller size.
//
//Since we use procedural caustics, that is not a worry for us.

// Ripple waves:
//
// These are a more basic and uniform wave shape where the height is essentially
// given by scrolled and stretched smooth value noise.
const NoiseWave RIPPLES[4] = NoiseWave[](
	// Larger, low frequency ripples
	NoiseWave (
		// Tile Dimensions: 1.5 meters x 4 meters
		vec2(1.5, 2.0),
		// Shear Angle: 30° (Tilt by 60°)
		30.0 * Degrees,
		// Speed: 1.5 m/s
		1.5,
		// Heading: 252° (-X/-Z quadrant)
		180.0 * Degrees + 72.0 * Degrees,
		// Weight: 16
		16.0
	),
	NoiseWave (
		// Tile Dimensions: 1 meter x 1.5 meters
		vec2(1.0, 1.5),
		// Shear Angle: -36° (Tilt by -54°)
		-36.0 * Degrees,
		// Speed: 3 m/s
		3.0,
		// Heading: 234° (-X/-Z quadrant)
		180.0 * Degrees + 54.0 * Degrees,
		// Weight: 16
		16.0
	),
	// Tiny, high frequency ripples
	NoiseWave (
		// Tile Dimensions: 30 cm x 40 cm
		vec2(0.30, 0.40),
		// Shear Angle: 45° (Tilt by 45°)
		45.0 * Degrees,
		// Speed: 1.5 m/s
		1.5,
		// Heading: 288° (+X/-Z quadrant)
		270.0 * Degrees + 18.0 * Degrees,
		// Weight: 4
		4.0
	),
	NoiseWave (
		// Tile Dimensions: 15 cm x 20 cm
		vec2(0.15, 0.20),
		// Shear Angle: -45° (Tilt by -45°)
		-45.0 * Degrees,
		// Speed: 0.5 m/s
		0.5,
		// Heading: 216° (-X/-Z quadrant)
		180.0 * Degrees + 36.0 * Degrees,
		// Weight: 1
		1.0
	)
);

// Crest waves:
//
// These waves have a more distinctive and intermittent "crest" shape
// and are otherwise flat. They are very slightly more computationally costly
// than "ripple" waves, because computing the normal vectors requires both a
// smoothNoise2D sample and a gradSmoothNoise2D sample, wheras ripple waves
// only require a gradSmoothNoise2D sample.
//
// However, they do not add a significant increase in computational cost
// for computing the wave height, which due to parallax mapping is still a
// large portion of the computational intensity of waves.
const NoiseWave CRESTS[2] = NoiseWave[](
	NoiseWave (
		// Tile Dimensions: 3.0 meters x 4.0 meters
		vec2(3.0, 4.0),
		// Shear Angle: 30° (Tilt by 60°)
		30.0 * Degrees,
		// Speed: 3.0 m/s
		3.0,
		// Heading: 243° (-X/-Z quadrant)
		//
		// This heading is the exact middle between the two large ripple waves,
		// such these 3 waves all move together and form the primary wave shape.
		180.0 * Degrees + 63.0 * Degrees,
		// Weight: 32
		//
		// The most significant wave, as the majority of the actual water shape
		// is formed by this wave combined with the two large ripple waves.
		32.0
	),
	NoiseWave (
		// Tile Dimensions: 6.0 meters x 8.0 meters
		//
		// Double the tile size of the previous wave as these are very
		// low frequency waves.
		vec2(6.0, 8.0),
		// Shear Angle: -30° (Tilt by -60°)
		//
		// Opposite direction of the shear for the previous wave.
		-30.0 * Degrees,
		// Speed: 12.0 m/s
		// 
		// This is fairly fast, but the waves are very low frequency so are 
		// fairly subtle. These waves break up and hide some of the tiling
		// patterns in the main crest wave that are otherwise very obvious.
		12.0,
		// Heading: 252° (-X/-Z quadrant)
		//
		// Same as the first ripple wave
		180.0 * Degrees + 72.0 * Degrees,
		// Weight: 16
		//
		// Half the weight of the main crest so as to not be too prominent, but
		// still significant.
		16.0
	)
);
