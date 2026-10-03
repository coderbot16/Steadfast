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

// Extended value noise functionality providing support for computing gradients
// of noise functions. This increases the minimum system requirements to any
// system supporting OpenGL 4.0 or alternatively GL_ARB_texture_gather.
//
// Note: using #if defined instead of #ifdef to prevent this from being picked
// up as a shader configuration option.
#if !defined(VALUE_NOISE_DERIVATIVES_INCLUDED)
#define VALUE_NOISE_DERIVATIVES_INCLUDED

// Derivative of the fade function from above, see details below.
float2 gradFade(float2 t) {
	// 30t^4 - 60t^3 + 30t^2
	return 30.0 * t * t * (t * (t - 2) + 1);
}

// Computes the gradient of the x-only variant of smoothNoise2D at the given
// coordinates. The gradient is the partial derivative with respect to X and the
// partial derivative with respect to Y paired together.
// 
// Henceforth, we will use the terminology gradN(x, y) as the gradient for a
// given N(x, y).
// 
// The caller is responsible for applying the chain rule as appropriate:
// https://en.wikipedia.org/wiki/Chain_rule
// 
// In other words, if you wish for the gradient for N(F(x), G(y)), then that
// will be given by gradN(F(x), G(y)) * float2(F'(x), G'(y)), NOT just a trivial
// gradN(F(x), G(y)). You need to make sure F and G are differentiable and know
// how to compute their derivative. Keep that in mind!
// 
// Conceptually, the smoothNoise2D function can be expressed as:
// 
// N(x, y) = Mix(
//   Mix(H(x, y    ), H(x + 1, y    ), Fade(fract(x))),
//   Mix(H(x, y + 1), H(x + 1, y + 1), Fade(fract(x))),
//   Fade(fract(y)))
//
// Where H is a hash function returning a random value at a given cell corner, N
// is the noise function, Fade is the fade function, and Mix is linear
// interpolation.
// 
// For the purposes of computing a local derivative, as the point lies within a
// single cell, we treat the H at each corner as constant, and fract(x) as a
// continuous function, even though that does not hold globally. That allows us
// to compute the derivative.
//
// First, we need dFade/dt. Fade(t) = 6t^5 - 15t^4 + 10t^3, so the derivative
// Fade'(t) is given by introductory calculus as:
//
// Fade'(t) = 6*5t^4 - 15*4t^3 + 10*3t^2
//
// Equivalently:
// Fade'(t) = 30t^4 - 60t^3 + 30t^2
//
// Also equivalently:
// Fade'(t) = 30.0 * t * t * (t * (t - 2) + 1)
//
// Note that lerp(C, D, f) is just C + (D-C) * f, dMix/dt is then just
// (D - C) * f', ie, D-C times the derivative of f. So, lerp(C, D, Fade(t)) is
// (D - C) * (30t^4 - 60t^3 + 30t^2).
//
// As for the whole function, we will first determine dN/dy. We will be able to
// use symmetry to give dN/dx from that afterwards. Since we are determining
// dN/dy with x held constant, the inner mix expressions are also constants,
// our C and D. Thus:
//
// dN/dy (x, y) = (
//                   Mix(H(x, y + 1), H(x + 1, y + 1), Fade(fract(x)))
//                 - Mix(H(x, y    ), H(x + 1, y    ), Fade(fract(x)))
//                ) * Fade'(fract(y)).
//
// In terms of determining dN/dx, it is no more complex than dN/dy. However,
// first we must observe an equiavelent form, swapping X and Y appropriately -
// this is valid because bilinear filtering is symmetrical across axes:
//
// N(x, y) = Mix(
//   Mix(H(x,     y), H(x,     y + 1), Fade(fract(y))),
//   Mix(H(x + 1, y), H(x + 1, y + 1), Fade(fract(y))),
//   Fade(fract(x)))
//
// With that alternate formulation, we can use the same method to determine
// dN/dx:
//
// dN/dx (x, y) = (
//                   Mix(H(x + 1, y), H(x + 1, y + 1), Fade(fract(y)))
//                 - Mix(H(x,     y), H(x,     y + 1), Fade(fract(y)))
//                ) * Fade'(fract(x)).
// 
// Combining these values gives us the gradient.
float2 gradSmoothNoise2D(float2 at) {
	static const float centerTexelOffset = 0.5 * noisePixel;

	// Determine the center of this grid cell in the texture
	float2 corner = floor(at);
	float2 center = corner * noisePixel + centerTexelOffset;
	float2 offset = at - corner;

	// Retrieve the corresponding 4 corners of this cell in the texture. In
	// terms of the analysis above, this is equivalent to returning the 4 values
	// of H.
	//
	// Using texture gather operations we are able to get these values in one
	// texture sample - this is just as fast as texture(), we are just skipping
	// the bilinear filtering part.
	//
	// textureGather(texture, P, 0) and textureGather(texture, P) return
	// the value:
	// 
	// float4(Sample_i0_j1(P, base).x,
	//      Sample_i1_j1(P, base).x,
	//      Sample_i1_j0(P, base).x,
	//      Sample_i0_j0(P, base).x);
	//
	// In our terms:
	//
	// float4(H(x,     y + 1),
	//      H(x + 1, y + 1),
	//      H(x + 1, y    ),
	//      H(x,     y    ))
	//
	//
	// NOTE: We are using textureGather from the ARB extension, which does
	// not support the optional "component" argument. Since we just need the
	// "x" component, this is OK since that is the default!
	//
	// References:
	// https://registry.khronos.org/OpenGL-Refpages/gl4/html/textureGather.xhtml
	// https://registry.khronos.org/OpenGL/extensions/ARB/ARB_texture_gather.txt
	float4 corners = textureGather(noisetex, center);

	// Compute the 4 interpolations we require for the partial derivatives:
	//
	// Used in dN/dy:
	//
	// X: Mix(H(x,     y + 1), H(x + 1, y + 1), Fade(fract(x)))
	// Y: Mix(H(x,     y    ), H(x + 1, y    ), Fade(fract(x)))
	//
	// Used in dN/dx:
	//
	// Z: Mix(H(x + 1, y    ), H(x + 1, y + 1), Fade(fract(y)))
	// W: Mix(H(x,     y    ), H(x,     y + 1), Fade(fract(y)))
	float4 mixes = lerp(corners.xwzw, corners.yzyx, fade(offset).xxyy);

	// Finally, use those interpolations to compute the partial derivative:
	// 
	// dN/dx (x, y) = (
	//                   Mix(H(x + 1, y), H(x + 1, y + 1), Fade(fract(y)))
	//                 - Mix(H(x,     y), H(x,     y + 1), Fade(fract(y)))
	//                ) * Fade'(fract(x)).
	// 
	// dN/dy (x, y) = (
	//                   Mix(H(x, y + 1), H(x + 1, y + 1), Fade(fract(x)))
	//                 - Mix(H(x, y    ), H(x + 1, y    ), Fade(fract(x)))
	//                ) * Fade'(fract(y)).
	return (mixes.zx - mixes.wy) * gradFade(offset);
}

#endif /* VALUE_NOISE_DERIVATIVES_INCLUDED */
