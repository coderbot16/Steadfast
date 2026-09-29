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

public record WaterNoiseSurfaceUniforms(
	Vector4f waterScrollRippleAB,
	Vector4f waterScrollRippleCD,
	Vector4f waterScrollCrestAB,

	Vector3f waterStretchRippleA,
	Vector3f waterStretchRippleB,
	Vector3f waterStretchRippleC,
	Vector3f waterStretchRippleD,
	Vector3f waterStretchCrestA,
	Vector3f waterStretchCrestB,

	Vector4f waterMagnitudeRipple,
	Vector2f waterMagnitudeCrest
) {
	private static Vector4f scroll(
		float timeSeconds,
		NoiseWave.Scroll xy,
		NoiseWave.Scroll zw
	) {
		return new Vector4f(
			timeSeconds * xy.x(),
			timeSeconds * xy.y(),
			timeSeconds * zw.x(),
			timeSeconds * zw.y()
		);
	}

	private static Vector3f stretch(NoiseWave.Stretch s) {
		return new Vector3f(s.scaleX(), s.scaleY(), s.shear());
	}

	public static WaterNoiseSurfaceUniforms create(float timeSeconds) {
		return new WaterNoiseSurfaceUniforms(
			scroll(timeSeconds,
				NoiseWave.RIPPLES[0].scroll(), NoiseWave.RIPPLES[1].scroll()),
			scroll(timeSeconds,
				NoiseWave.RIPPLES[2].scroll(), NoiseWave.RIPPLES[3].scroll()),
			scroll(timeSeconds,
				NoiseWave.CRESTS[0].scroll(), NoiseWave.CRESTS[1].scroll()),
			stretch(NoiseWave.RIPPLES[0].stretch()),
			stretch(NoiseWave.RIPPLES[1].stretch()),
			stretch(NoiseWave.RIPPLES[2].stretch()),
			stretch(NoiseWave.RIPPLES[3].stretch()),
			stretch(NoiseWave.CRESTS[0].stretch()),
			stretch(NoiseWave.CRESTS[1].stretch()),
			new Vector4f(
				(float) NoiseWave.RIPPLES[0].magnitude(),
				(float) NoiseWave.RIPPLES[1].magnitude(),
				(float) NoiseWave.RIPPLES[2].magnitude(),
				(float) NoiseWave.RIPPLES[3].magnitude()
			),
			new Vector2f(
				(float) NoiseWave.CRESTS[0].magnitude(),
				(float) NoiseWave.CRESTS[1].magnitude()
			)
		);
	}
}
