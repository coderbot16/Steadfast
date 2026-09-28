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

// Slightly tweaked version of noise waves
record Caustic(
	NoiseWave wave,
	double exponent
) {
	// Convenience constant to express degree measurements and units.
	private static final double DEGREES = Math.toRadians(1.0);

	public static final Caustic[] CAUSTICS = {
		new Caustic (
			new NoiseWave(
				// Tile Dimensions: 4.5 meters x 6.0 meters
				4.5, 6.0,
				// Shear Angle: 30° (Tilt by 60°)
				30.0 * DEGREES,
				// Speed: 2.0 m/s
				2.0,
				// Heading: 243° (-X/-Z quadrant)
				//
				// 63° is the exact middle between 54° and 72°, such these 3
				// waves all move together and form the primary shape.
				180.0 * DEGREES + 63.0 * DEGREES,
				0.25
			),
			6.0
		),
		new Caustic (
			new NoiseWave(
				// Tile Dimensions: 9.0 meters x 8.0 meters
				//
				// Double the tile size of the previous wave as these are very
				// low frequency waves.
				9.0, 12.0,
				// Shear Angle: -30° (Tilt by -60°)
				//
				// Opposite direction of the shear for the previous wave.
				-30.0 * DEGREES,
				// Speed: 8.0 m/s
				// 
				// This is fairly fast, but the waves are very low frequency so
				// are fairly subtle. These waves break up and hide some of the
				// tiling patterns in the main waves that are otherwise obvious.
				8.0,
				// Heading: 252° (-X/-Z quadrant)
				//
				// Same as the first ripple wave
				180.0 * DEGREES + 72.0 * DEGREES,
				0.15
			),
			6.0
		),
		new Caustic (
			new NoiseWave(
				// Tile Dimensions: 2.25 meters x 3.0 meters
				2.25, 3.0,
				// Shear Angle: 30° (Tilt by 60°)
				30.0 * DEGREES,
				// Speed: 1.0 m/s
				1.0,
				// Heading: 252° (-X/-Z quadrant)
				180.0 * DEGREES + 72.0 * DEGREES,
				0.15
			),
			5.0
		),
		new Caustic (
			new NoiseWave(
				// Tile Dimensions: 1.5 meters x 2.25 meters
				1.5, 2.25,
				// Shear Angle: -36° (Tilt by -54°)
				-36.0 * DEGREES,
				// Speed: 2 m/s
				2.0,
				// Heading: 234° (-X/-Z quadrant)
				180.0 * DEGREES + 54.0 * DEGREES,
				0.15
			),
			5.0
		),
		new Caustic (
			new NoiseWave(
				// Tile Dimensions: 45 cm x 60 cm
				0.45, 0.60,
				// Shear Angle: 45° (Tilt by 45°)
				45.0 * DEGREES,
				// Speed: 1.0 m/s
				1.0,
				// Heading: 243° (-X/-Z quadrant)
				180.0 * DEGREES + 63.0 * DEGREES,
				0.15
			),
			1.25
		),
		new Caustic (
			new NoiseWave(
				// Tile Dimensions: 22.5 cm x 30 cm
				0.225, 0.30,
				// Shear Angle: -45° (Tilt by -45°)
				-45.0 * DEGREES,
				// Speed: 0.33 m/s
				1.0 / 3.0,
				// Heading: 234° (-X/-Z quadrant)
				180.0 * DEGREES + 54.0 * DEGREES,
				0.15
			),
			1.25
		)
	};

	private static double calculateTotalWeight() {
		double total = 0.0;

		for (Caustic caustic : CAUSTICS) {
			total += caustic.wave().weight();
		}

		return total;
	}

	// Compute the magnitude of each wave layer at compile time by dividing each
	// weight by the total weight, so we do not need to do this at runtime.
	private static double totalWeight = calculateTotalWeight();

	public double logMagnitude() {
		return Math.log(wave().weight() / totalWeight);
	}
}