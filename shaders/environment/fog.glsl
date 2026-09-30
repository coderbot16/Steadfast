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

#if !defined (EXTERNALLY_DEFINED_UNIFORMS)
	uniform float3 caveFogColor;
	uniform float eyeSkylight;
	uniform int isEyeInWaterFog;

	uniform float3 underwaterFogColor;
	uniform float atmosphereFogCoefficient;
	uniform float blindness;
	uniform float borderFogDistance;
#endif

// Whether to enable fog that hides the render distance border.
#define BORDER_FOG
// The strength of fog at noon. 
#define ATMOSPHERE_FOG_STRENGTH_NOON 0.5 // [0.0 0.25 0.33 0.5 0.66 0.75 1.0]

float4 FogV2(
	out float skyFogStrength,
	float fragDistance,
	float borderFragDistance,
	float skyLightStrength
) {
	float borderFog;

	#ifdef BORDER_FOG
		borderFog = smoothstep(
			borderFogDistance - 8,
			borderFogDistance,
			borderFragDistance);
	#else
		borderFog = 0.0;
	#endif

	float atmosphereFog = pow(fragDistance, 3.0) * atmosphereFogCoefficient;

	// Transition the fog color in caves.
	float caveFogTransition = smoothstep(
		0.0,
		0.25,
		max(skyLightStrength, eyeSkylight));
	skyFogStrength = caveFogTransition;
	float3 fogColor = (1.0 - caveFogTransition) * caveFogColor;

	if (blindness > 0.0001) {
		// Blindness is essentially just a very strong fog.
		atmosphereFog = max(
			0.85, 
			1.0 - exp(-pow(fragDistance * blindness * 0.5, 2)));
		fogColor = float3(0.0);
		skyFogStrength = 0.0;
	} else if (isEyeInWaterFog == 1) {
		// Underwater fog is much more dense than atmospheric fog.
		// This is relatively similar to exp2 fog from the OpenGL
		// fixed function pipeline.
		atmosphereFog = 1.0 - exp(-pow(fragDistance * 0.02, 2));
		fogColor = underwaterFogColor;
		skyFogStrength = 0.0;
	} else if (isEyeInWaterFog == 2) {
		// Lava fog, also uses exponential fog but with a very high minimum
		// fog intensity as you aren't really supposed to be able to see much
		// when in lava (though in survival mode you won't be in the lava for
		// long!)
		atmosphereFog = max(0.85, 1.0 - exp(-pow(fragDistance * 0.5, 2)));
		fogColor = float3(1.0, 0.05, 0.0);
		skyFogStrength = 0.0;
	}

	float fogFactor = min(borderFog + atmosphereFog, 1.0);

	if (skyFogStrength > 0.0) {
		// Zero out low-strength fog to enable an optimization on most close
		// terrain. This does not work with very closer fog so this is a hack to
		// disable it (such as when underwater).
		fogFactor *= smoothstep(0.01, 0.015, fogFactor);
	}

	return float4(fogColor, fogFactor);
}

// Kept around while we move over to FogV2
// TODO: Move everything to FogV2 and just have one Fog function
float4 Fog(
	float3 skyGradient,
	float fragDistance,
	float borderFragDistance,
	float skyLightStrength
) {
	float skyFogStrength = 0.0;
	float4 fogv2 = FogV2(
		skyFogStrength,
		fragDistance,
		borderFragDistance,
		skyLightStrength);
	fogv2.rgb += skyGradient * skyFogStrength;
	return float4(fogv2.rgb * fogv2.a, 1.0 - fogv2.a);
}
