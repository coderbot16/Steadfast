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

// Include guard to permit every file that requires this function to include it,
// independent of other files.
#if !defined(VALUE_NOISE_INCLUDED)
#define VALUE_NOISE_INCLUDED

// Simple 2D value noise

// We sample a 64x64 texture; the size is defined in the pipeline definition.
static const float noisePixel = 1.0 / 64.0;

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform sampler2D noisetex;
#endif

float noise(float3 noiseChannel, in float2 pos) {
	return dot(texture(noisetex, pos).xyz, noiseChannel);
}

// Helper function for the below smoothed noise function, this is taken from
// Perlin noise.
float2 fade(float2 t) {
	// 6t^5 - 15t^4 + 10t^3
	return t * t * t * (t * (t * 6 - 15) + 10);
}

// Very efficient value noise function taking full advantage of texture sampling
// hardware.
//
// Despite the memory bandwith cost associated with texture sampling, the
// relatively small size of the texture we are sampling (64x64, 16384 bytes) as
// well as the inherent nature of coherent noise (meaning that we usually are
// sampling similar broad areas of the texture) allows it to stay in cache.
// 
// Furthermore, bilinear filtering hardware in the GPU means that the normal
// process of sampling value noise - that is, hashing the 4 cell corners and
// then interpolating between them - is entirely hardware-accelerated.
//
// These two combined factors mean that a texture-free version, even when using
// a very fast hash function and optimized coordinate interpolation, ends up
// being many more shader instructions, and when an L1 cache read can happen as
// fast as a multiply, it also ends up being a fair bit slower!
//
// In practice, noise using texture lookups is noticably faster - 80 FPS -> 90
// FPS in a water-heavy scene.
//
// Input: Coordinates scaled to the cell size - adding 1.0 to any coordinate
//        moves by the size of exactly 1 cell. The lower-left cell in the +X/+Y
//        quadrant covers the input coordinates (0.0, 0.0) to (1.0, 1.0).
//
// Output: 3 coherent noise values in the range [0.0, 1.0]
float3 smoothNoise2Dx3(float2 at) {
	// Determine the corner of the grid cell this coordinate lies in.
	float2 corner = floor(at);

	// Per OpenGL reference pages, fract(x) is calculated by x - floor(x).
	// Since we have floor(x) anyways, we can skip the call to fract(x).
	float2 offset = at - corner;

	// The critical component of value noise that makes it smooth (other than
	// the interpolation) is the smoothstep / fade function that we apply to the
	// cell-relative coordinates.
	//
	// In our case, as we will be computing the derivative of this noise
	// function, we MUST use fade() as it has a smooth derivative, whereas
	// smoothstep does not. If we used smoothstep, we would have
	// discontinuities.
	//
	// Note that the last operation in fade is a multiply. So this will compile
	// to a fused multiply-add.
	at = fade(offset) + corner;

	// Finally, we have our interpolation coordinates. However, we must change
	// coordinate systems into texel space before sampling. First, we must
	// obviously divide by the resolution of the value noise texture, as texture
	// coordinates are 0.0 to 1.0.
	//
	// However, less intuitively, we must also offset by half of a texel. Why?
	// Because in cell space, (0.5, 0.5) is the center of the lower-right cell.
	// However, in texture space (assuming a 64-pixel texture), (1/64, 1/64) is
	// the center of 4 texels (pixels) - in cell terms, the center of a cell,
	// and (0.5/64, 0.5/64) is actually dead-center on a single texel - in cell
	// terms, the lower-left corner of a cell.
	//
	// But, when we offset a cell coordinate we have scaled by 1/64 by half of a
	// texel, we then sync up these two spaces, such that a cell coordinate in
	// the center of a cell maps to a coordinate directly in the center of 4
	// texels, and such that a cell coordinate in the corner of a cell maps to a
	// coordinate in the dead center of a single texel.
	// 
	// We write out the coordinate system change like this to make it another
	// single-instruction fused multiply-add.
	at = at * noisePixel + (0.5 * noisePixel);

	// Finally, sample the texture and choose our desired component.
	return texture(noisetex, at).xyz;
}

// Same as the function above, but only returns a single value noise result.
float smoothNoise2D(float2 at) {
	// TODO: This could be even faster if we used a 1-component texture instead
	// of sampling an RGB/RGBA texture and throwing away the other components.
	return smoothNoise2Dx3(at).x;
}

// Same as the function above, but instead of returning the x component, it
// allows you to create your own noise channels dynamically - the noiseChannel
// parameter contains the weights of each noise channel.
float smoothNoise2D(float3 noiseChannel, float2 at) {
	return dot(smoothNoise2Dx3(at), noiseChannel);
}

#endif /* VALUE_NOISE_INCLUDED */
