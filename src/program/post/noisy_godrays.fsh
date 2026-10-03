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

#define GODRAYS_SAMPLE_DEFINED
#define GodraysSampler sampler2D

float godraysSample(GodraysSampler sampler, float2 uv) {
	// The sky should have a depth value of 1.0. This is one of the few places
	// where == works reliably.
	return float(texture(sampler, uv).r == 1.0);
}

#include "godrays.slang"

uniform float2 windowToScreenHalf;
uniform float4 screenLightVector;
uniform GodraysSampler depthtex0;

/* DRAWBUFFERS:1 */
out float godrays;

void main() {
	// While we check whether godrays are exposed above to avoid
	// additional computation cost, to fully use the 8 bits of
	// precision do not scale the value here.
	godrays = Godrays(
		depthtex0,
		NOISY_GODRAYS,
		gl_FragCoord.xy * windowToScreenHalf,
		screenLightVector.xy,
		gl_FragCoord.xy
	);
}
