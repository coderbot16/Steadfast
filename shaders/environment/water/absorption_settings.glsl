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

#define NO_ABSORPTION 0
#define REFRACTION_ASSISTED 1

// TODO: Remove this
#define WATER_ABSORPTION_METHOD REFRACTION_ASSISTED // [NO_ABSORPTION REFRACTION_ASSISTED]

const vec3 COLD = (-vec3(1.0, 5 / 16.0, 1 / 16.0));
const vec3 BALANCED = (-vec3(1.0, 3 / 16.0, 1 / 16.0));
const vec3 TROPICAL = (-vec3(2.0, 2 / 16.0, 0.5 / 16.0));

// These coefficients determine the shades of blue that underwater surfaces take
// as the depth increases.
//
// For usage in Beer's law:
// https://wikipedia.org/wiki/Attenuation_coefficient#Beer%E2%80%93Lambert_law
//
// Units: 1/m (reciprocal meters)
#define WATER_CHARACTER BALANCED // [COLD BALANCED TROPICAL]
const vec3 WATER_ATTENUATION_COEFFICIENTS = WATER_CHARACTER;
