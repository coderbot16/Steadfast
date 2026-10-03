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

// Whether to use a more saturated tonemapping option, from the original
// Uncharted 2 Tonemapping presentation by John Hable.
//#define SATURATED_TONEMAP

// Uncharted 2 Tonemap from https://64.github.io/tonemapping/#uncharted-2
float3 Uncharted2TonemapPartial(float3 x) {
	#ifdef SATURATED_TONEMAP
		// These are the tonemapping parameters from John Hable's original
		// presentation at GDC:
		//
		// https://www.gdcvault.com/play/1012351/Uncharted-2-HDR
		//
		// Comparing the curves, it is clear these original parameters result in
		// an even steeper start and an even shallower end - in other words, it
		// increases the overall brightness, saturation, and contrast.
		//
		// Comparison (green is blog parameters, red is GDC parameters):
		//
		// https://www.desmos.com/calculator/fxjrgjiepm
		const float A = 0.22;
		const float B = 0.30;
		const float C = 0.10;
		const float D = 0.20;
		const float E = 0.01;
		const float F = 0.30;
	#else
		// These are the tonemapping parameters from John Hable's blog post:
		// http://filmicworlds.com/blog/filmic-tonemapping-operators/
		const float A = 0.15;
		const float B = 0.50;
		const float C = 0.10;
		const float D = 0.20;
		const float E = 0.02;
		const float F = 0.30;
	#endif

	return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
}

float3 Uncharted2Tonemap(float3 v) {
	float exposure_bias = 2.0;
	float3 curr = Uncharted2TonemapPartial(v * exposure_bias);

	float3 W = float3(11.2);
	float3 white_scale = float3(1.0) / Uncharted2TonemapPartial(W);
	return curr * white_scale;
}
