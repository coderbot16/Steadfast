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

// Fog
#include "/environment/fog.slang"

// Fog requires the sky color
#include "/environment/sky.slang"

uniform float4x4 gbufferModelView;
uniform float4x4 gbufferModelViewInverse;
uniform float4x4 gbufferProjection;

// The interpolated vertex color directly from the vertex buffer.
out float4 tinting;

// The interpolated texture coordinate directly from the vertex buffer.
out float2 texcoord;

out float4 fog;

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
	float4 cameraRelativePos = mul(gbufferModelViewInverse, viewPos);

	// Fairly standard vertex shader boilerplate here.
	tinting = gl_Color;

	// Transform from camera-relative position to view position to clip position
	gl_Position = mul(gl_ProjectionMatrix, viewPos);

	// Put this at the bottom to make sure nothing else inadvertently depends on
	// this.
	texcoord = mul(gl_TextureMatrix[0], gl_MultiTexCoord0).xy;

	// Compute fog based on the distance, the sky color, etc.
	// TODO: SkyDither?
	float3 skyGradient = SkyColor(normalize(cameraRelativePos.xyz));

	float fragDistance = max(
		abs(cameraRelativePos.y),
		length(cameraRelativePos.xz));
	
	// Note: Clouds are always exposed to the sky (hence the 1.0)
	// Note: Apply less border fog to clouds because it looks weird at low
	// render distances.
	// TODO: Not sure what to do about cloud border fog at high render distances
	fog = Fog(skyGradient, 0.66 * fragDistance, 0.33 * fragDistance, 1.0);
}
