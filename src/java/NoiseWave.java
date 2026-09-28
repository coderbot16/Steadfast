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

// Define each wave as a set of intuitive measurements which the compiler can
// convert to more direct scaling and offset values, for easy tweaking.
record NoiseWave(
	// The size of each tile in the grid on the X axis and the Y axis in meters.
	//
	// The area covered by each tile is mapped to the area of a single pixel in
	// the value noise texture, and therefore this directly controls the visible
	// size of the visible trough and peak shapes of this wave.
	//
	// Due to the shear mapping below, each tile is actually a parallelogram.
	// However, shear mapping preserves the length along each axis that each
	// tile occupies in the grid, it just slants the tile.
	double tileSizeX,
	double tileSizeY,

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
	double shearAngle,

	// The speed that the wave travels torwards its heading direction in meters
	// (blocks) per second.
	double speed,

	// The heading of the wave, in radians. This follows the unit circle except
	// our Z coordinate is the Y on the unit circle.
	double heading,

	// The weight of this particular wave. The height of each wave is multiplied
	// by its weight and then the sum of all wave weights is divided by the
	// total weight, such that the actual magnitude of this wave is given by
	// weight divided by totalWeight.
	double weight
) {
	// Convenience constant to express degree measurements and units.
	private static final double DEGREES = Math.toRadians(1.0);

	// Actual wave measurements/definitions used by the Noise water surface
	// implementation.
	//
	// The parameters of these waves have been selected to give a similar
	// appearance to SEUS-11.0 and SEUS Renewed. In fact, the waves in SEUS PTGI
	// are actually just SEUS Renewed waves scaled by a factor of 4 so that they
	// appear to have a much higher frequency. However, this makes the tiling
	// artifacts way more obvious and IMO, they look worse, but this was likely
	// a necessary tradeoff so that the baked water caustics texture used by
	// SEUS PTGI (as opposed to the procedural caustics of Renewed) could be
	// kept to a smaller size.
	//
	// Since we use procedural caustics, that is not a worry for us.

	// Ripple waves:
	//
	// These are a more basic and uniform wave shape where the height is
	// essentially given by scrolled and stretched smooth value noise.
	public static final NoiseWave[] RIPPLES = {
		// Larger, low frequency ripples
		new NoiseWave (
			// Tile Dimensions: 1.5 meters x 4 meters
			1.5, 2.0,
			// Shear Angle: 30° (Tilt by 60°)
			30.0 * DEGREES,
			// Speed: 1.5 m/s
			1.5,
			// Heading: 252° (-X/-Z quadrant)
			180.0 * DEGREES + 72.0 * DEGREES,
			// Weight: 16
			16.0
		),
		new NoiseWave (
			// Tile Dimensions: 1 meter x 1.5 meters
			1.0, 1.5,
			// Shear Angle: -36° (Tilt by -54°)
			-36.0 * DEGREES,
			// Speed: 3 m/s
			3.0,
			// Heading: 234° (-X/-Z quadrant)
			180.0 * DEGREES + 54.0 * DEGREES,
			// Weight: 16
			16.0
		),
		// Tiny, high frequency ripples
		new NoiseWave (
			// Tile Dimensions: 30 cm x 40 cm
			0.30, 0.40,
			// Shear Angle: 45° (Tilt by 45°)
			45.0 * DEGREES,
			// Speed: 1.5 m/s
			1.5,
			// Heading: 288° (+X/-Z quadrant)
			270.0 * DEGREES + 18.0 * DEGREES,
			// Weight: 4
			4.0
		),
		new NoiseWave (
			// Tile Dimensions: 15 cm x 20 cm
			0.15, 0.20,
			// Shear Angle: -45° (Tilt by -45°)
			-45.0 * DEGREES,
			// Speed: 0.5 m/s
			0.5,
			// Heading: 216° (-X/-Z quadrant)
			180.0 * DEGREES + 36.0 * DEGREES,
			// Weight: 1
			1.0
		)
	};

	// Crest waves:
	//
	// These waves have a more distinctive and intermittent "crest" shape and
	// are otherwise flat. They are very slightly more computationally costly
	// than "ripple" waves, because computing the normal vectors requires both a
	// smoothNoise2D sample and a gradSmoothNoise2D sample, wheras ripple waves
	// only require a gradSmoothNoise2D sample.
	//
	// However, they do not add a significant increase in computational cost
	// for computing the wave height, which due to parallax mapping is still a
	// large portion of the computational intensity of waves.
	public static final NoiseWave[] CRESTS = {
		new NoiseWave (
			// Tile Dimensions: 3.0 meters x 4.0 meters
			3.0, 4.0,
			// Shear Angle: 30° (Tilt by 60°)
			30.0 * DEGREES,
			// Speed: 3.0 m/s
			3.0,
			// Heading: 243° (-X/-Z quadrant)
			//
			// This heading is the exact middle between the two large ripple
			// waves, such these 3 waves all move together and form the primary
			// wave shape.
			180.0 * DEGREES + 63.0 * DEGREES,
			// Weight: 32
			//
			// The most significant wave, as the majority of the water shape
			// is formed by this wave combined with the two large ripple waves.
			32.0
		),
		new NoiseWave (
			// Tile Dimensions: 6.0 meters x 8.0 meters
			//
			// Double the tile size of the previous wave as these are very
			// low frequency waves.
			6.0, 8.0,
			// Shear Angle: -30° (Tilt by -60°)
			//
			// Opposite direction of the shear for the previous wave.
			-30.0 * DEGREES,
			// Speed: 12.0 m/s
			//
			// This is fairly fast, but the waves are very low frequency so are
			// fairly subtle. These waves break up and hide some of the tiling
			// patterns in the main crest wave that are otherwise very obvious.
			12.0,
			// Heading: 252° (-X/-Z quadrant)
			//
			// Same as the first ripple wave
			180.0 * DEGREES + 72.0 * DEGREES,
			// Weight: 16
			//
			// Half the weight of the main crest so as to not be too prominent,
			// but still significant.
			16.0
		)
	};

	public record Stretch(
		float scaleX,
		float scaleY,
		float shear
	) {}

	public record Scroll(
		float x,
		float y
	) {}

	// We must take the inverse of the tile size (meters per noise pixel) to get
	// the scaling factor from world space (noise pixels per meter).
	//
	// With shearing, the diagonal of the scale matrix remains unmodified, but
	// we apply the shearing after scaling, so we multiply the X scale with the
	// computed shearing factor. The shearing factor (m) is given by
	// cot(shearAngle), equivalently, 1.0 / tan(shearAngle).
	//
	// Since we only support X/Z scaling in combination with a vertical shear,
	// while we can represent this as a 2D transformation matrix one of the
	// elements will always be zero, so we store it as a vector instead where
	// the first two components are the diagonal (X/Z scale) and the third
	// element is the first column, second row value - in other words, the
	// scaling factor applied to the X coordinate that gets added to the final
	// Y position.
	//
	// We could expand this to a mat2 like so:
	// mat2(stretch.x, stretch.z, 0.0, stretch.y)
	//
	// Mathematica / Mathics code useful for validating the shear math:
	//
	// VerticalShear[T_] := {{1.0, 0.0}, {T, 1.0}}
	// Simplify[Dot[VerticalShear[Shear], Dot[{{XScale, 0.0}, {0.0, YScale}},
	//     {X, Y}]] // MatrixForm]
	// Simplify[Dot[Dot[VerticalShear[Shear], {{XScale, 0.0}, {0.0, YScale}}],
	//     {X, Y}] // MatrixForm]
	// Simplify[Dot[VerticalShear[Shear], {{XScale, 0.0}, {0.0, YScale}
	//     ] // MatrixForm]
	public Stretch stretch() {
		return new Stretch(
			(float) (1.0 / tileSizeX()),
			(float) (1.0 / tileSizeY()),
			(float) ((1.0 / Math.tan(shearAngle())) / tileSizeX())
		);
	}

	// Convert the speed and heading into the horizontal offset vector to be
	// multiplied with the time - we call this the "scroll" vector as it is the
	// vector used to scroll the waves across the world as time passes.
	//
	// Essentially, we convert the speed and heading into a world space vector,
	// and then transform into the coordinate system of this particular wave.
	//
	// Finally, we multiply by negative 1. Why? Well, to make it look like the
	// wave at (0, 0) moved 1 unit towards positive X, we must subtract 1 unit
	// to make the wave that was at (0, 0) now appear at (1, 0) because
	// (1 - 1, 0) is (0, 0), the original position of the wave.
	public Scroll scroll() {
		Stretch s = stretch();

		double dx = Math.cos(heading());
		double dy = Math.sin(heading());

		double vx = -speed() * (s.scaleX() * dx);
		double vy = -speed() * (s.scaleY() * dy + s.shear() * dx);

		return new Scroll((float) vx, (float) vy);
	}

	private static double calculateTotalWeight() {
		double total = 0.0;

		for (NoiseWave wave : RIPPLES) {
			total += wave.weight();
		}

		for (NoiseWave wave : CRESTS) {
			total += wave.weight();
		}

		return total;
	}

	// Compute the magnitude of each wave layer at compile time by dividing each
	// weight by the total weight, so we do not need to do this at runtime.
	private static double totalWeight = calculateTotalWeight();

	public double magnitude() {
		return weight() / totalWeight;
	}
}
