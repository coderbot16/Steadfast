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

#include "../../lib/distort.slang"

in float4 mc_Entity;
in float3 at_midBlock;

out float2 texcoord;
out float waterHeight;

uniform float4x4 shadowModelViewInverse;

#include "../../environment/materialIDs.slang"

void main() {
	float4 viewPos = mul(gl_ModelViewMatrix, gl_Vertex);
	float4 cameraRelativePos = mul(shadowModelViewInverse, viewPos);
	uint materialID = DecodeMaterialID(mc_Entity.x);

	// TODO: Deduplicate this, copied from lit.fsh
	if (materialID == WATER &&
		// Only water faces that are facing directly up or down are eligible
		// for standard water effects. Otherwise, we will fall back to vanilla
		// flowing water tecture.
		abs(gl_Normal.y) > 0.9999 &&
		// If flat, this face must also be high enough that it is not just
		// the flat center of flowing water as well.
		//
		// at_midBlock is the distance to the center of the block multiplied
		// by 64. Because the top face of still water is above the center,
		// this is negative as the center of the block is below. So, this
		// actually means: is this vertex more than 23/64th of a block above
		// its center?
		//
		// If you look at still water in vanilla, the surface lies 2 pixels
		// below the top of a nearby solid block. 2/16 is 0.875, which would
		// be 24 / 64 (0.375) + half (0.5). So, 23/64 just allows for some
		// imprecision, but without allowing a still center of flowing water,
		// which is below this threshold (3 pixels below, a 20/64 offset).
		at_midBlock.y < -23.0
	) {
		float y = cameraRelativePos.y;
		waterHeight = 0.5 - 0.5 * clamp(y / 1024.0, -1.0, 1.0);
	} else {
		waterHeight = 1.0;
	}

	texcoord = gl_MultiTexCoord0.xy;
	gl_Position = mul(gl_ProjectionMatrix, viewPos);
	gl_Position.xyz = distort(gl_Position.xyz);

	// Prevent some blocks from casting shadows for aesthetic reasons.
	// See the definition in block.properties for more details.
	if (materialID == GLASS) {
		gl_Position = float4(-1.0);
	}
}
