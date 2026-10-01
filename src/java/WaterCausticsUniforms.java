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

import org.joml.*;

public record WaterCausticsUniforms(
	Vector3f causticsStretch0,
	Vector4f causticsScale0,
	Vector3f causticsStretch1,
	Vector4f causticsScale1,
	Vector3f causticsStretch2,
	Vector4f causticsScale2,
	Vector3f causticsStretch3,
	Vector4f causticsScale3,
	Vector3f causticsStretch4,
	Vector4f causticsScale4,
	Vector3f causticsStretch5,
	Vector4f causticsScale5
) {
	private static Vector4f scale(
		float timeSeconds,
		Caustic caustic
	) {
		return new Vector4f(
			timeSeconds * caustic.wave().scroll().x(),
			timeSeconds * caustic.wave().scroll().y(),
			(float) caustic.exponent(),
			(float) caustic.logMagnitude()
		);
	}

	private static Vector3f stretch(NoiseWave.Stretch s) {
		return new Vector3f(s.scaleX(), s.scaleY(), s.shear());
	}

	public static WaterCausticsUniforms create(float timeSeconds) {
		return new WaterCausticsUniforms(
			stretch(Caustic.CAUSTICS[0].wave().stretch()),
			scale(timeSeconds, Caustic.CAUSTICS[0]),
			stretch(Caustic.CAUSTICS[1].wave().stretch()),
			scale(timeSeconds, Caustic.CAUSTICS[1]),
			stretch(Caustic.CAUSTICS[2].wave().stretch()),
			scale(timeSeconds, Caustic.CAUSTICS[2]),
			stretch(Caustic.CAUSTICS[3].wave().stretch()),
			scale(timeSeconds, Caustic.CAUSTICS[3]),
			stretch(Caustic.CAUSTICS[4].wave().stretch()),
			scale(timeSeconds, Caustic.CAUSTICS[4]),
			stretch(Caustic.CAUSTICS[5].wave().stretch()),
			scale(timeSeconds, Caustic.CAUSTICS[5])
		);
	}
}
