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

// Physically based values taken from the following paper, assuming wavelengths
// of 680 nm (red), 550 nm (green), and 440 nm (blue)
//
// https://omlc.org/spectra/water/data/pope97.txt
//
// Note that the values on that page have units 1/cm while these use 1/m
// hence why they appear to differ by two orders of magnitude.
const vec3 CLEAR = vec3(-0.465, -0.0565, -0.00635);

#define CUSTOM_WATER_ABSORPTION_R 0.50 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.60 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.70 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.80 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.90 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.00]
#define CUSTOM_WATER_ABSORPTION_G 0.50 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.60 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.70 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.80 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.90 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.00]
#define CUSTOM_WATER_ABSORPTION_B 0.00 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.60 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.70 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.80 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.90 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.00]
#define CUSTOM_WATER_ABSORPTION_R_MAGNITUDE 1.0 // [0.0001 0.001 0.01 0.1 1.0 10.0 100.0 1000.0]
#define CUSTOM_WATER_ABSORPTION_G_MAGNITUDE 0.1 // [0.0001 0.001 0.01 0.1 1.0 10.0 100.0 1000.0]
#define CUSTOM_WATER_ABSORPTION_B_MAGNITUDE 1.0 // [0.0001 0.001 0.01 0.1 1.0 10.0 100.0 1000.0]

const vec3 CUSTOM_WATER_ATTENUATION_COEFFICIENTS = vec3(
	-CUSTOM_WATER_ABSORPTION_R * CUSTOM_WATER_ABSORPTION_R_MAGNITUDE,
	-CUSTOM_WATER_ABSORPTION_G * CUSTOM_WATER_ABSORPTION_G_MAGNITUDE,
	-CUSTOM_WATER_ABSORPTION_B * CUSTOM_WATER_ABSORPTION_B_MAGNITUDE);

// These coefficients determine the shades of blue that underwater surfaces take
// as the depth increases.
//
// For usage in Beer's law:
// https://wikipedia.org/wiki/Attenuation_coefficient#Beer%E2%80%93Lambert_law
//
// Units: 1/m (reciprocal meters)
#define WATER_CHARACTER BALANCED // [CLEAR COLD BALANCED TROPICAL CUSTOM_WATER_ATTENUATION_COEFFICIENTS]
const vec3 WATER_ATTENUATION_COEFFICIENTS = WATER_CHARACTER;
