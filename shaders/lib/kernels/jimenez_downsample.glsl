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

// This is a high-performance, high-quality, and temporarlly-stable downsampling
// filter originally intended for bloom, but also useful for any sort of blur.
//
// See "Next Generation Post Processing in Call of Duty: Advanced Warfare" on
// https://www.iryoku.com/publications. This implementation is a translation
// of the diagram on Slide 152 ("DOWNSAMPLING - OUR SOLUTION") in the attached
// PowerPoint presentation.
//
// This implementation consists exclusively of texture sampling and fused
// multiply-add instructions.
vec3 JimenezDownsampleBlur(sampler2D source, vec2 uv, vec2 pxToUv) {
	vec3 avg = vec3(0.0);

	// Top row: weight 4
	avg += (1.0 / 32.0) * texture(source, vec2(-2.0, -2.0) * pxToUv + uv).rgb;
	avg += (2.0 / 32.0) * texture(source, vec2( 0.0, -2.0) * pxToUv + uv).rgb;
	avg += (1.0 / 32.0) * texture(source, vec2( 2.0, -2.0) * pxToUv + uv).rgb;

	// Central upper (red dots in diagram): weight 8
	avg += (4.0 / 32.0) * texture(source, vec2(-1.0, -1.0) * pxToUv + uv).rgb;
	avg += (4.0 / 32.0) * texture(source, vec2( 1.0, -1.0) * pxToUv + uv).rgb;

	// Middle row: weight 8
	avg += (2.0 / 32.0) * texture(source, vec2(-2.0,  0.0) * pxToUv + uv).rgb;
	avg += (4.0 / 32.0) * texture(source, vec2( 0.0,  0.0) * pxToUv + uv).rgb;
	avg += (2.0 / 32.0) * texture(source, vec2( 2.0,  0.0) * pxToUv + uv).rgb;

	// Central lower (red dots in diagram): weight 8
	avg += (4.0 / 32.0) * texture(source, vec2(-1.0,  1.0) * pxToUv + uv).rgb;
	avg += (4.0 / 32.0) * texture(source, vec2( 1.0,  1.0) * pxToUv + uv).rgb;

	// Bottom row: weight 4
	avg += (1.0 / 32.0) * texture(source, vec2(-2.0,  2.0) * pxToUv + uv).rgb;
	avg += (2.0 / 32.0) * texture(source, vec2( 0.0,  2.0) * pxToUv + uv).rgb;
	avg += (1.0 / 32.0) * texture(source, vec2( 2.0,  2.0) * pxToUv + uv).rgb;

	return avg;
}
