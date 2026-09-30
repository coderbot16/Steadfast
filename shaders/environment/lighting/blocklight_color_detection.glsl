#include "blocklight_color.glsl"

void EmissiveDetection(
	uint materialID,
	float3 sampledColor,
	inout float blockLight,
	inout float3 lightColor
) {
	if (materialID == EMITTER_MAGIC) {
		// This material applies to crying obsidian and the nether portal, this
		// is a way of isolating the "tears" out of crying obsidian without
		// impacting nether portals.
		bool magic = dot(sampledColor, float3(2.5, -10.0, 5.0)) > 1.0;
		bool glowstone = dot(sampledColor, float3(6.0, 6.0, -10.0)) > 1.0;

		if (magic || glowstone) {
			// The colors in vanilla crying obsidian tears and nether portals
			// are tuned to its yellowish block lighting, so we need to mimic
			// that to get reasonable colors.
			blockLight = 1.0;
			lightColor = BLACKBODY_4000K;
		}
	}
}
