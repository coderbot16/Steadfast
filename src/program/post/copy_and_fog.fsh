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

// We must make a copy of colortex0 for forward-rendered reflections and
// refraction, as we cannot sample a texture we are rendering into.
const int R11F_G11F_B10F = 0;
const int R8 = 0;

// We must write to colortex4, as per OptiFine/Iris specifications, that is the
// first colortex buffer number that gbuffers shaders can sample. colortex0-3
// are not bound in gbuffers shaders.
const int colortex4Format = R11F_G11F_B10F;
const int colortex2Format = R8;
const int colortex5Format = R8;

// Water absorption configuration, has wide-reaching impacts across the
// codebase.
#include "/environment/water/absorption_settings.slang"

// float4 Fog(...)
#include "/environment/fog.slang"

// float3 SkyColor(float3 ray, float dither)
#include "/environment/sky.slang"

uniform float4x4 gbufferModelViewInverse;
uniform float4x4 gbufferProjectionInverse;
uniform float2 windowToNdc;

uniform sampler2D colortex2;
uniform sampler2D colortex0;
uniform sampler2D depthtex1;

#ifdef DISTANT_HORIZONS
	uniform float4x4 dhProjectionInverse;
	uniform sampler2D dhDepthTex0;
#endif

float3 ApplyFog(
	float4x4 inverseProjection,
	float3 fragCoord,
	float3 background,
	float skyLight
) {
	// Project back to view space from the fragment coordinates
	//
	// Note: w must be 1.0 in these  homogenous coordinates, as 1.0 means a
	// point in space rather than a vector.
	float3 ndcPos = float3(fragCoord.xy * windowToNdc, fragCoord.z * 2.0) - 1.0;
	float4 viewPosH = mul(inverseProjection, float4(ndcPos, 1.0));
	float3 viewPos = viewPosH.xyz / viewPosH.w;
	float3 cameraRelativePos =
		mul(gbufferModelViewInverse, float4(viewPos, 1.0)).xyz;

	float3 worldSpaceVector = normalize(cameraRelativePos);
	float3 sky = SkyDither(fragCoord.xy, SkyColor(worldSpaceVector));

	// Compute the fog against the sky background
	float fragDistance = max(
		abs(cameraRelativePos.y),
		length(cameraRelativePos.xz)
	);
	float4 fog = Fog(sky, fragDistance, fragDistance, skyLight);

	return background * fog.a + fog.rgb;
}

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

	float skylight = texelFetch(colortex2, int2(gl_FragCoord), 0).r;
	float depth = texelFetch(depthtex1, int2(gl_FragCoord), 0).r;

	float3 backgroundWithFog = background;

	if (depth < 1.0) {
		backgroundWithFog = ApplyFog(
			gbufferProjectionInverse,
			float3(gl_FragCoord.xy, depth),
			background,
			skylight
		);
	} else {
		#ifdef DISTANT_HORIZONS
			depth = texelFetch(dhDepthTex0, int2(gl_FragCoord), 0).r;
			if (depth < 1.0) {
				backgroundWithFog = ApplyFog(
					dhProjectionInverse,
					float3(gl_FragCoord.xy, depth),
					background,
					skylight
				);
			}
		#endif
	}

	// colortex0 from here on out will now be a complete image of the scene with
	// fog applied, so that translucents can blend fog.
	gl_FragData[0] = float4(backgroundWithFog, 1.0);

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
