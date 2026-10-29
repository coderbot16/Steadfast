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
#include "../../environment/fog.slang"
#include "../../lib/srgb.slang"

uniform float4x4 gbufferModelViewInverse;
uniform float4 cloudColor;

out float4 color;

void main() {
	// This is effectively as if we multiplied with the model matrix, because we
	// do not get the model matrix separate from the model view matrix.
	//
	// gbufferModelView is a misnomer, it is actually just the view matrix. Same
	// with gbufferModelViewInverse - it is the inverse view matrix.
	// 
	// So the inverse of the view matrix times the model view matrix is the
	// model matrix, which gives us camera-relative coordinates.
	float4 viewPos = mul(gl_ModelViewMatrix, gl_Vertex);

	float4 tinting = gl_Color;
	float4 cameraRelativePos = mul(gbufferModelViewInverse, viewPos);

	float fogFragDistance = max(
		abs(cameraRelativePos.y),
		length(cameraRelativePos.xz));

	// Note: Clouds are always exposed to the sky (hence the 1.0)
	// Note: Apply less border fog to clouds because it looks weird at low
	// render distances.
	// TODO: Not sure what to do about cloud border fog at high render
	// distances
	float skyFogStrength;
	tinting.a *= 1.0 - FogV2(
		skyFogStrength,
		0.66 * fogFragDistance,
		0.33 * fogFragDistance,
		1.0).a;

	color = cloudColor * SrgbToLinear(tinting);
	gl_Position = mul(gl_ProjectionMatrix, viewPos);
}
