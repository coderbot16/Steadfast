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
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform vec3 causticsStretch0;
	uniform vec4 causticsScale0;
	uniform vec3 causticsStretch1;
	uniform vec4 causticsScale1;
	uniform vec3 causticsStretch2;
	uniform vec4 causticsScale2;
	uniform vec3 causticsStretch3;
	uniform vec4 causticsScale3;
	uniform vec3 causticsStretch4;
	uniform vec4 causticsScale4;
	uniform vec3 causticsStretch5;
	uniform vec4 causticsScale5;
#endif

// TODO: Copied from surface_noise.glsl
//
// This function reshapes the original smooth transitions
// between different wave levels into more visible "crests"
// on the transitions between different wave levels, such that
// most of the area is flat and there are raised crests at regular grid
// transition points.
float crestCaustics(float h) {
	const float PI = 3.14159265359;

	// 0.5 - 0.5 * cos written out to explicitly have it as
	// mul -> cos -> fma
	return (-0.5 * cos(h * (PI * 2.0))) + 0.5;
}

// We use the smoothNoise2D variant of our value noise.
#include "/lib/valueNoise.glsl"

// This is pretty similar to the noise waves code, but adjusted for caustics
float waterCaustic(vec2 worldPos, vec3 stretch, vec4 scale) {
	vec2 scroll = scale.xy;
	float exponent = scale.z;
	float logMagnitude = scale.w;

	vec2 stretched = vec2(
		worldPos.x * stretch.x,
		dot(worldPos, stretch.zy));
	vec2 at = scroll + stretched;

	// The "crest" function combined with raising to a power happens to work
	// nicely for these caustics.
	float noise = crestCaustics(smoothNoise2D(at));

	// This is equivalent to: C * x^P
	//
	// First, we apply the identity that the shader compiler would have used
	// to implement the pow(x, P) function:
	// C * x^P = C * e^(P * ln(x))
	//
	// Then, we apply additional identity to pull in the C:
	// C * e^(P * ln(x)) = e^(ln C) * e^(P * ln(x))
	// C * e^(P * ln(x)) = e^(P * ln(x) + ln C)
	//
	// This compiles down to 3 operations (log, fused multiply-add, exp)
	return exp(exponent * log(noise) + logMagnitude);
}

float WaterCaustics(vec3 worldPos, float time) {
	// Project the 2D caustics on to the 3D underwater surface.
	//
	// While potentially unintuitive, projecting this as we would with the
	// shadow map looks bad. Perhaps we can rotate this with the light position
	// but this simple approach seems to be completely fine.
	worldPos.xz += vec2(-2.0 / 3.0, 2.0 / 3.0) * worldPos.y;

	// Deform the coordinates with a sine wave to add some additional animation,
	// which is a rough analog to the changing refraction which causes the
	// caustics to vary. This helps avoid the it looking like we just scrolled
	// a texture over the terrain.
	worldPos.xz += 0.15 * sin(worldPos.zx * vec2(0.30, 0.25) + time);

	float caustics = 0.0;

	caustics += waterCaustic(worldPos.xz, causticsStretch0, causticsScale0);
	caustics += waterCaustic(worldPos.xz, causticsStretch1, causticsScale1);
	caustics += waterCaustic(worldPos.xz, causticsStretch2, causticsScale2);
	caustics += waterCaustic(worldPos.xz, causticsStretch3, causticsScale3);
	caustics += waterCaustic(worldPos.xz, causticsStretch4, causticsScale4);
	caustics += waterCaustic(worldPos.xz, causticsStretch5, causticsScale5);

	// Allow anywhere between 66% brightness to 250% brightness. Square it
	// so that caustics are more intermittent.
	return (caustics * caustics) * (1.5 + 0.33) - 0.33;
}
