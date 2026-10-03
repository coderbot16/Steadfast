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

float pow4(float x) {
	x *= x;
	x *= x;

	return x;
}

#define FANTASY 0
#define SEMI_NATURAL 1
#define RETRO 2

// The atmosphere (sun) color contribution from the sun during the day.
#define DAY_ATMOSPHERE SEMI_NATURAL // [FANTASY SEMI_NATURAL RETRO]

// The atmosphere (sun) color contribution from the moon at night.
#define NIGHT_ATMOSPHERE FANTASY // [FANTASY SEMI_NATURAL RETRO]

// Whether the sky gradient should have a less soft horizon during the day
#define HARDER_HORIZON_DAY 

// Whether the sky gradient should have a less soft horizon during the night
//#define HARDER_HORIZON_NIGHT

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform float3 worldSunVector;

	uniform float sunrise;
	uniform float3 skyZenithDay;
	uniform float3 skyHorizonDay;
	uniform float3 skyLightDay;

	uniform float moonrise;
	uniform float3 skyZenithNight;
	uniform float3 skyHorizonNight;
	uniform float3 skyLightNight;
#endif

// Returns an HDR sky color at the given world-space vector
float3 SkyColor(float3 worldDir) {
	// Cosine/dot product with horizon. Gradually transitions to 0 above the 
	// horizon, always 1 below the horizon.
	#if defined(HARDER_HORIZON_DAY) || defined(HARDER_HORIZON_NIGHT)
		float dotHorizonHard = clamp(pow(1.0 - worldDir.y, 2.0), 0.0, 1.0);
		float horizonScatterHard = pow4(dotHorizonHard);
	#endif

	#if !defined(HARDER_HORIZON_DAY) || !defined(HARDER_HORIZON_NIGHT)
		float dotHorizonSoft = 1.0 - clamp(worldDir.y, 0.0, 1.0);
		float horizonScatterSoft = pow4(dotHorizonSoft);
	#endif

	#ifdef HARDER_HORIZON_DAY
		float dotHorizonDay = dotHorizonHard;
		float horizonScatterDay = horizonScatterHard;
	#else
		float dotHorizonDay = dotHorizonSoft;
		float horizonScatterDay = horizonScatterSoft;
	#endif

	#ifdef HARDER_HORIZON_NIGHT
		float dotHorizonNight = dotHorizonHard;
		float horizonScatterNight = horizonScatterHard;
	#else
		float dotHorizonNight = dotHorizonSoft;
		float horizonScatterNight = horizonScatterSoft;
	#endif

	// Cosine/dot product with the sun or moon. 0.0 to 1.0 for the day/night
	// variants, no need for negatives in the actual sky equations.
	float dotSun = dot(worldDir, worldSunVector);
	float dotLightDay = max(dotSun, 0.0);
	float dotLightNight = max(-dotSun, 0.0);

	// Scatter the horizon color around the sun / moon
	float lightScatterBase = 0.2 * pow4(dotSun);
	float lightScatterDay = dotLightDay * lightScatterBase;
	float lightScatterNight = dotLightNight * lightScatterBase;

	// Baseline overall light scattering - includes the horizon and the area
	// around the sun/moon
	float scatterDay = horizonScatterDay + lightScatterDay;
	float scatterNight = horizonScatterNight + lightScatterNight;
	float baseScatterDay = clamp(scatterDay, 0.0, 1.0);
	float baseScatterNight = clamp(scatterNight, 0.0, 1.0);

	// Extra scattering during the sunrise / moonrise
	float sunriseScatter  = sunrise  * dotHorizonDay   * pow4(dotLightDay);
	float moonriseScatter = moonrise * dotHorizonNight * pow4(dotLightNight);

	// Base sky gradient transitioning from horizon color to zenith color
	float3 daySkyBase   = lerp(skyZenithDay,   skyHorizonDay,   baseScatterDay);
	float3 nightSkyBase = lerp(skyZenithNight, skyHorizonNight, baseScatterNight);

	// Sunlight scattered into the sky gradient
	float3 daySky =   lerp(daySkyBase,   skyLightDay,    sunriseScatter);
	float3 nightSky = lerp(nightSkyBase, skyLightNight, moonriseScatter);

	return daySky + nightSky;
}
