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

// This is an analog of JimenezDownsampleBlur that returns the minimum depth
// of any color sample considered by the downsampling filter at this UV.
float JimenezMinTappedDepth(sampler2D source, vec2 uv, vec2 pxToUv) {
	vec4 depth = vec4(1.0);

	// Top row
	depth = min(depth, textureGather(source, vec2(-2.0, -2.0) * pxToUv + uv));
	depth = min(depth, textureGather(source, vec2( 0.0, -2.0) * pxToUv + uv));
	depth = min(depth, textureGather(source, vec2( 2.0, -2.0) * pxToUv + uv));

	// Middle row
	depth = min(depth, textureGather(source, vec2(-2.0,  0.0) * pxToUv + uv));
	depth = min(depth, textureGather(source, vec2( 0.0,  0.0) * pxToUv + uv));
	depth = min(depth, textureGather(source, vec2( 2.0,  0.0) * pxToUv + uv));

	// Bottom row
	depth = min(depth, textureGather(source, vec2(-2.0,  2.0) * pxToUv + uv));
	depth = min(depth, textureGather(source, vec2( 0.0,  2.0) * pxToUv + uv));
	depth = min(depth, textureGather(source, vec2( 2.0,  2.0) * pxToUv + uv));

	return min(
		min(depth.x, depth.y),
		min(depth.z, depth.w)
	);
}
