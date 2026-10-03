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

// Whether to use the new direct lighting model with atmospheric scattering.
#define MINISHITA_LIGHTING
#ifdef MINISHITA_LIGHTING
	// Actual effect is in shaders.properties
#endif

#define STEADFAST BY_CODERBOT // Authorship attribution. [BY_CODERBOT]

#define FANTASY 0
#define SEMI_NATURAL 1
#define RETRO 2

// The style of direct and ambient sky lighting to use during the day.
#define DAY_SKY_LIGHTING SEMI_NATURAL // [FANTASY SEMI_NATURAL RETRO]

// The style of direct and ambient sky lighting to use at night.
#define NIGHT_SKY_LIGHTING FANTASY // [FANTASY SEMI_NATURAL RETRO]

// Whether real-time shadows using shadow mapping are enabled for entities.
#define REAL_TIME_ENTITY_SHADOWS
#ifdef REAL_TIME_ENTITY_SHADOWS
	// Actual effect is in shaders.properties
#endif

// Whether real-time shadows using shadow mapping are enabled for block entities
// (chests, beds, etc).
// #define REAL_TIME_BLOCK_ENTITY_SHADOWS
#ifdef REAL_TIME_BLOCK_ENTITY_SHADOWS
	// Actual effect is in shaders.properties
#endif

// #define VANILLA_CLOUDS
#ifdef VANILLA_CLOUDS
	// Actual effect in shaders.properties
#endif

// The strength of Minecraft's baked ambient occlusion. Lower values can look
// more realistic in some cases but come at the expense of flat lighting.
//
// If you're going for the exact SEUS Renewed look, you'll want to lower this
// down to 0.1 (10%).
const float ambientOcclusionLevel = 1.0; // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// Tilt the path of the sun sideways. This is a standard shader effect that
// makes shadows look much better.
const float	sunPathRotation	= -40.0f;

// Enable PCF (shadowHardwareFiltering) on both shadowmaps
const bool shadowHardwareFiltering0 = true;
const bool shadowHardwareFiltering1 = true;

// Higher shadow map resolutions give sharper shadows at the expense of
// perfomance.
const int shadowMapResolution = 1536; // [1024 1536 2048 3072 4096]

// Render distance of the shadow map, in blocks. No objects outside of this
// distance cast or receive real-time shadows.
const float shadowDistance = 160; // [32 48 64 80 96 112 128 144 160 192 256]
const float shadowDistanceRenderMul = 1.0;
const float entityShadowDistanceMul = 0.25;

// We only need 64x64 at most and could probably get away with 32x32 or 48x48 if
// needed. The smaller the better as that helps maximize memory cache hit rate.
const int noiseTextureResolution = 64;

// This is a very compact floating-point color format using 32 bits just as
// RGBA8 does, while permitting HDR colors.
//
// Note that even though this format lacks an alpha channel, translucency is
// still supported, as translucent alpha blending does not actually require
// writing to the alpha channel as in all cases we are drawing against an opaque
// background.
const int R11F_G11F_B10F = 0;
const int R8 = 0;

// Main scene texture (Full resolution)
const int colortex0Format = R11F_G11F_B10F;

// Godrays (Half resolution)
//
// Godrays format is just a single color channel, 8 bits is enough.
//
// Originally I used 16 bits, but it turns out that if we do not scale the
// result, since we are smoothing the result anyways and the noise acts as a
// dither, there is actually zero noticeable difference between 8 bits and 16
// bits. So switching to 8 bit halves the required memory bandwidth on both ends
// basically for free, compared to using 16 bits.
const int colortex1Format = R8;

// Skylight (Full resolution)
const int colortex2Format = R8;

// Opaque scene for reflections / refraction (Full resolution)
//
// We must write to colortex4, as per OptiFine/Iris specifications, that is the
// first colortex buffer number that gbuffers shaders can sample. colortex0-3
// are not bound in gbuffers shaders.
//
// We must make a copy of colortex0 for forward-rendered reflections and
// refraction, as we cannot sample a texture we are rendering into.
const int colortex4Format = R11F_G11F_B10F;

// Opaque skylight
const int colortex5Format = R8;

// Blurred opaque scene (Half resolution)
const int colortex6Format = R11F_G11F_B10F;

// By default, Iris clears colortex0 specifically to the fog color. We do not
// need this behavior, so clear to zero. On some drivers this is supposedly
// faster, though I noticed no difference.
const float4 colortex0ClearColor = float4(0.0, 0.0, 0.0, 0.0);

// For consistency, also clear colortex1 to zero. This in particular has no
// performance difference but it is unusual compared to all other textures
const float4 colortex1ClearColor = float4(0.0, 0.0, 0.0, 0.0);

// Encoded water height
//
// We would prefer to use R16 but R16 is not in OpenGL 3. R16_SNORM is, though.
// TODO: Evaluate if there is a more appropriate format we can use
const int R16_SNORM = 0;
const int shadowcolor0Format = R16_SNORM;
