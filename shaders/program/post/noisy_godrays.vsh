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

#include "/common/post/cover_screen.slang"

// This stops godrays from rendering when they would not be visible.
//
// Notably this prevents the buffer from getting filled with garbage.
// Avoiding undefined behavior is good though it is not visible outside
// of a debugging view.
uniform float godraysExposure;

bool shouldRender() {
	return godraysExposure > 0.0;
}

void main() {
	if (!shouldRender()) {
		gl_Position = float4(-1.0);
		return;
	}

	gl_Position = float4(coverScreen(uint(gl_VertexID)), 1.0, 1.0);
}
