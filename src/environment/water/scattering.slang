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

// Water scattering approximates the effect of suspended dirt and other
// particles underwater. While water absorption reduces (absorbs) light,
// water scattering scatters light in the direction of the viewer, "adding"
// light.

#include "scattering_settings.slang"

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform float skyAmbientLuminance;
#endif

float WaterScatteringFalloff(float waterDepth) {
	return 1.0 - exp(WATER_SCATTER_BY_DEPTH * waterDepth);
}

float3 WaterScattering(float skyLight, float falloff) {
	// Fade out water scattering below 25% skylight
	float scatter = max(0.0, skyLight * 1.25 - 0.25) * skyAmbientLuminance;
	return waterScattering * (scatter * falloff);
}
