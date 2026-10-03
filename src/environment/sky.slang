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

#define MINISHITA 1
#define GRADIENT 2
// The atmosphere (sun) color contribution from the sun during the day.
#define ATMOSPHERE_MODEL MINISHITA // [MINISHITA GRADIENT]

#if ATMOSPHERE_MODEL == GRADIENT
	#include "sky/gradient.slang"
#else
	#include "sky/minishita.slang"
#endif

#include "../lib/bayer8.slang"

#define FANTASY 0
#define SEMI_NATURAL 1
#define RETRO 2

// The atmosphere (sun) color contribution from the sun during the day.
#define DAY_ATMOSPHERE SEMI_NATURAL // [FANTASY SEMI_NATURAL RETRO]

// The atmosphere (sun) color contribution from the moon at night.
#define NIGHT_ATMOSPHERE FANTASY // [FANTASY SEMI_NATURAL RETRO]

// Returns a darkening or brightening factor for the given fragment / pixel
// coordinate on the screen.
//
// Credit to MakeUp Ultra Fast for the idea of dithering the sky gradient -
// it really helped fix the otherwise obvious banding.
float3 SkyDither(float2 fragCoord, float3 skyColor) {
	// Intensity of sky dithering.
	#define SKY_DITHER 0.075 // [0.0 0.025 0.05 0.075 0.1 0.125 0.15]

	float ditherFactor = SKY_DITHER;
	
	#if NIGHT_ATMOSPHERE == RETRO && ATMOSPHERE_MODEL == GRADIENT
		// Workaround for near-black sky colors in combination with filmic
		// tonemaps. In these cases, the filmic tonemap will exaggerate the
		// contrast of the black colors, but our adaptive code below will not
		// dither sufficiently.
		//
		// This isn't perfect but seems to be an OK workaround for the only case
		// where this happens, the Retro profile at night, without impacting any
		// other situation.
		float skyColorLuminance = dot(skyColor, float3(0.2126, 0.7152, 0.0722));
		ditherFactor *=
			1.0 + 3.0 * (1.0 - smoothstep(0.0, 0.5, skyColorLuminance));
	#endif

	// Basically just darkening or brightening the color relative to its
	// existing brightness, to automatically adapt to colors of any brightness.
	float dither = 1.0 + ditherFactor * (Bayer8(fragCoord) * 2.0 - 1.0);
	return skyColor * dither;
}
