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

// https://github.com/dmnsgn/glsl-tone-map/blob/main/uchimura.glsl
// Tweaks are in the form of comments
// This is the old Uchimura / "GT" filmic tonemap.

// Copyright (C) 2019 Damien Seguin
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

float3 uchimura(
	float3 x, float P, float a, float m, float l, float c, float b
) {
	float l0 = ((P - m) * l) / a;
	float L0 = m - m / a;
	float L1 = m + (1.0 - m) / a;
	float S0 = m + l0;
	float S1 = m + a * l0;
	float C2 = (a * P) / (P - S1);
	float CP = -C2 / P;

	float3 w0 = float3(1.0 - smoothstep(0.0, m, x));
	float3 w2 = float3(step(m + l0, x));
	float3 w1 = float3(1.0 - w0 - w2);

	float3 T = float3(m * pow(x / m, float3(c)) + b);
	float3 S = float3(P - (P - S1) * exp(CP * (x - S0)));
	float3 L = float3(m + a * (x - m));

	return T * w0 + L * w1 + S * w2;
}

float3 UchimuraTonemap(float3 x) {
	const float P = 1.0;	// max display brightness
	const float a = 1.0;	// contrast
	const float m = 0.22; // linear section start
	//const float l = 0.4;	// linear section length
	const float l = 0.5;	// linear section length
	//const float c = 1.33; // black
	const float c = 1.0; // black
	const float b = 0.0;	// pedestal

	return uchimura(x, P, a, m, l, c, b);
}
