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

// sRGB to Linear RGB
#include "/lib/srgb.glsl"

// The interpolated vertex color directly from the vertex buffer.
in vec4 tinting;

// The base material (block/entity/etc) texture
uniform sampler2D gtexture;

// The interpolated texture coordinate directly from the vertex buffer.
in vec2 texcoord;

in vec4 fog;

uniform vec3 cloudColor;

// Alpha test threshold - any pixels with an alpha less than this will be
// discarded.
uniform float alphaTestRef;

void main() {
	vec4 surfaceColor = tinting * texture(gtexture, texcoord);

	// Run the alpha test immediately to avoid shading fragments
	// that would fail the alpha test.
	// 
	// There's no penalty to running it early as we have to run it
	// either way, but if it lets us skip a whole block of pixels
	// (think player shoving their camera into a block of leaves),
	// then maybe we will get a little boost!
	// 
	// Ideally, this helps us save on memory bandwidth when
	// and sampling the shadowmap as well as overall TMU load.
	if (surfaceColor.a < alphaTestRef) { 
		discard;
		return;
	}

	// Apply sRGB to linear conversion
	//
	// We do this after multiplying texture color with vertex color
	// and after including entity color (if applicable) as to mimic
	// Minecraft, as it does the same multiplications (incorrectly)
	// in sRGB color space.
	surfaceColor.rgb = SrgbToLinear(surfaceColor.rgb);

	// Multiply in cloud color / fog and write out to the primary color
	// buffer.
/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(surfaceColor.rgb * cloudColor * fog.a + fog.rgb, 0.2);
}
