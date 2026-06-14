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

// Generic material without special effects
const uint GENERIC = 0u;

// Connected Waving + Subsurface Scattering (Leaves)
const uint LEAVES = 1u;

// Disconnected Waving + Subsurface Scattering (Ground Foliage)
const uint GROUND_FOLIAGE = 2u;

// Subsurface Scattering Only No Waving
const uint SUBSURFACE_SCATTERING = 3u;

// Water
const uint WATER = 4u;

// Ice
const uint ICE = 5u;

// Blocks that do not cast shadows (Glass and translucents)
const uint GLASS = 6u;

const uint EMITTER_MAGIC = 8u;

// Geometry selector: Diagonally horizontal geometry
// Add 16 to any material ID to apply this geometry selector
const uint GEOMETRY_HORIZONTAL_DIAGONAL_ONLY = 1u;

// Standard Iris / OptiFine: IDs in block.properties via mc_Entity.x
uint DecodeMaterialID(float mc_EntityX) {
	return uint(max(0.0, mc_EntityX - 10000.0));
}

// Voxy: IDs in block.properties via VoxyFragmentParameters.customId
uint DecodeMaterialID(uint customId) {
	return customId > 10000u ? customId - 10000u : 0u;
}
