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

#include "/lib/srgb.glsl"

uniform sampler2D gtexture;

in vec4 tinting;
in vec2 texcoord;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform vec2 windowToNdc;

uniform vec3 worldSunVector;

#ifdef MC_RENDER_STAGE_SUN
	uniform int renderStage;
#endif

void main() {
	// Project back to view space from the fragment coordinates. For this case,
	// it is easier to start off with a position on the far plane and then
	// normalize to a vector than to try to get a vector out of the screen
	// position directly.
	vec2 ndcPos = gl_FragCoord.xy * vec2(windowToNdc) - 1.0;
	vec4 viewVecH = gbufferProjectionInverse * vec4(ndcPos, 1.0, 1.0);
	vec3 viewVec = normalize(viewVecH.xyz / viewVecH.w);

	// Note: w must be 0.0 in homogenous coordinates, as 1.0 means a point in
	// space rather than a vector.
	vec3 worldSpaceVector = (gbufferModelViewInverse * vec4(viewVec, 0.0)).xyz;

	vec4 srgb = tinting * texture(gtexture, texcoord);
	vec4 fragmentColor = SrgbToLinear(srgb);
	fragmentColor.rgb *= UNLIT_BRIGHTNESS;

	#ifdef MC_RENDER_STAGE_SUN
		bool sun = renderStage == MC_RENDER_STAGE_SUN;
	#else
		bool sun = dot(worldSpaceVector, worldSunVector) > 0.0;
	#endif

	// Whether the sun fades away as it passes below the horizon
	#define HORIZON_OCCLUDES_SUN
	#ifdef HORIZON_OCCLUDES_SUN
		if (sun) {
			float fadeInSun = clamp(5.0 * worldSunVector.y, 0.0, 1.0);
			float horizonOcclusion = clamp(20.0 * worldSpaceVector.y, 0.0, 1.0);

			fragmentColor.rgb *= (fadeInSun * horizonOcclusion);
		}
	#endif

/* DRAWBUFFERS:0 */
	gl_FragData[0] = fragmentColor;
}
