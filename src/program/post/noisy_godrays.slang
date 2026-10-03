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

#include "cover_screen.slang"

namespace NoisyGodrays {
	#include <lib/iris_custom_uniforms.slang>
	#include "godrays.slang"

	import aperture;

	struct SkyGodraysSampler : GodraysSampler {
		static float Sample(float2 uv) {
			// Reverse Z means the sky has depth 0.0
			// This is one of the few places where == works reliably on floats
			return float(ap.depth.sampleNearest(uv) == 0.0);
		}
	}

	// This stops godrays from rendering when they would not be visible.
	//
	// Notably this prevents the buffer from getting filled with garbage.
	// Avoiding undefined behavior is good though it is not visible outside
	// of a debugging view.
	bool shouldRender() {
		return irisCustomUniforms.godraysExposure > 0.0;
	}

	float trace(float2 pixelCoord) {
		// To fully use the 8 bits of precision, do not scale the value here.
		return Godrays(
			SkyGodraysSampler(),
			NOISY_GODRAYS,
			pixelCoord * irisCustomUniforms.windowToScreenHalf,
			irisCustomUniforms.screenLightVector.xy,
			pixelCoord
		);
	}
}

[[shader("vertex")]]
float4 vertexMain(uint vertexID : SV_VertexID): SV_Position {
	if (!NoisyGodrays::shouldRender()) {
		return float4(-1.0);
	}

	return float4(coverScreen(vertexID), 0.0, 1.0);
}

[[shader("pixel")]]
float main(float4 position : SV_Position) {
	return NoisyGodrays::trace(position.xy);
}
