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

in float2 texcoord;
in float waterHeight;

uniform sampler2D gtexture;
uniform float alphaTestRef;

void main() {
	float4 surfaceColor = texture(gtexture, texcoord);

	if (surfaceColor.a < alphaTestRef) { 
		discard;
		return;
	}

/* DRAWBUFFERS:0 */
	gl_FragData[0] = float4(waterHeight, 1.0, 1.0, 1.0);
}
