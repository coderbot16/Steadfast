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

// Water absorption configuration, has wide-reaching impacts across the
// codebase.
#include "../../environment/water/absorption_settings.slang"
#include "../../environment/water/scattering.slang"

// float4 Fog(...)
#include "../../environment/fog.slang"

// float3 SkyColor(float3 ray, float dither)
#include "../../environment/sky.slang"

uniform float4x4 gbufferModelViewInverse;
uniform float4x4 gbufferProjectionInverse;
uniform float2 windowToNdc;

uniform int isEyeInWater;

#ifdef DISTANT_HORIZONS
	uniform float4x4 dhProjectionInverse;
	uniform sampler2D dhDepthTex0;
#endif

float3 ApplyFog(
	float2 fragCoord,
	float3 fragmentColor,
	float depth,
	float skyLight
) {
	bool hit = depth < 1.0;
	float4x4 inverseProjection = gbufferProjectionInverse;

	if (!hit) {
		#ifdef DISTANT_HORIZONS
			depth = texelFetch(dhDepthTex0, int2(fragCoord), 0).r;
			inverseProjection = dhProjectionInverse;
			hit = depth < 1.0;
		#endif
	}

	if (!hit) {
		if (isEyeInWater == 1) {
			#ifdef UNDERWATER_SCATTERING
				return WaterScattering(eyeSkylight, 1.0);
			#else
				return underwaterFogColor;
			#endif
		}

		return fragmentColor;
	}

	// Project back to view space from the fragment coordinates
	//
	// Note: w must be 1.0 in these  homogenous coordinates, as 1.0 means a
	// point in space rather than a vector.
	float3 ndcPos = float3(fragCoord * windowToNdc, depth * 2.0) - 1.0;
	float4 viewPosH = mul(inverseProjection, float4(ndcPos, 1.0));
	float3 viewPos = viewPosH.xyz / viewPosH.w;
	float3 cameraRelativePos =
		mul(gbufferModelViewInverse, float4(viewPos, 1.0)).xyz;

	float fragDistance = length(cameraRelativePos);

	if (isEyeInWater == 1) {
		float waterDepth = (-15.0) * skyLight + 15.0;

		#define VIEW_DEPENDENT_WATER_DEPTH
		#ifdef VIEW_DEPENDENT_WATER_DEPTH
			waterDepth += fragDistance;
		#else
			waterDepth += 1.0;
		#endif

		fragmentColor *= exp(WATER_ATTENUATION_COEFFICIENTS * waterDepth);

		#ifdef UNDERWATER_SCATTERING
			float scatteringFalloff = WaterScatteringFalloff(fragDistance);
			fragmentColor += WaterScattering(eyeSkylight, scatteringFalloff);
			return fragmentColor;
		#endif
	}

	// Compute the fog against the sky background
	float fogFragDistance = max(
		abs(cameraRelativePos.y),
		length(cameraRelativePos.xz)
	);

	float skyFogStrength = 0.0;

	float4 fog = FogV2(
		skyFogStrength,
		fogFragDistance,
		fogFragDistance,
		skyLight);

	float3 worldSpaceVector = cameraRelativePos / fragDistance;
	float3 sky = SkyDither(fragCoord.xy, SkyColor(worldSpaceVector));
	fog.rgb += sky * skyFogStrength;

	return lerp(fragmentColor.rgb, fog.rgb, fog.a);
}

uniform sampler2D colortex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex2;

void main() {
	// texelFetch & gl_FragCoord used like this are a perfect way to copy a
	// texture.
	//
	// int2 cast functionality per the GLSL specification:
	//
	// > When constructors are used to convert a floating-point type to an
	// > integer type, the fractional part of the floating-point value is
	// > dropped.
	//
	// gl_FragCoord per the GLSL reference:
	// https://registry.khronos.org/OpenGL-Refpages/gl4/html/gl_FragCoord.xhtml
	//
	// > By default, gl_FragCoord assumes a lower-left origin for window
	// > coordinates and assumes pixel centers are located at half-pixel
	// > centers. For example, the (x, y) location (0.5, 0.5) is returned
	// > for the lower-left-most pixel in a window.
	float3 background = texelFetch(colortex0, int2(gl_FragCoord), 0).rgb;
	float depth = texelFetch(depthtex1, int2(gl_FragCoord), 0).r;
	float skylight = texelFetch(colortex2, int2(gl_FragCoord), 0).r;

	float3 withFog = ApplyFog(gl_FragCoord.xy, background, depth, skylight);

	// colortex0 from here on out will now be a complete image of the scene with
	// fog applied, so that translucents can blend fog.
	gl_FragData[0] = float4(withFog, 1.0);

#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
	// colortex4 is a copy of the image for reflection and refraction, and does
	// not apply fog.
	gl_FragData[1] = float4(background, 1.0);

	// colortex5 is an immutable copy of colortex2.
	// They both store skylight.
	gl_FragData[2] = float4(float3(skylight), 1.0);

	/* DRAWBUFFERS:045 */
#else
	/* DRAWBUFFERS:0 */
#endif
}
