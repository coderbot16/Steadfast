#include "lib/iris_custom_uniforms.slang"
#include "environment/fog.slang"
#include "lib/srgb.slang"

struct CloudOutput {
	float4 fragmentColor;
}

import aperture;
import object_shader;

struct CloudShader : Shader<float4, CloudOutput> {
	static void emitVertex(
		Vertex v,
		ObjectTransforms transforms,
		out float4 color,
		out float4 pos
	) {
		float4 tinting = v.color();
		float3 cameraRelativePos = v.pos().xyz;

		float fogFragDistance = max(
			abs(cameraRelativePos.y),
			length(cameraRelativePos.xz));

		// Note: Clouds are always exposed to the sky (hence the 1.0)
		// Note: Apply less border fog to clouds because it looks weird at low
		// render distances.
		// TODO: Not sure what to do about cloud border fog at high render
		// distances
		float skyFogStrength;
		tinting.a *= 1.0 - FogV2(
			skyFogStrength,
			0.66 * fogFragDistance,
			0.33 * fogFragDistance,
			1.0).a;

		color = irisCustomUniforms.cloudColor * SrgbToLinear(tinting);
		pos = mul(transforms.projection, mul(transforms.view, v.pos()));
	}

	static CloudOutput shadeSurface(PixelData objectData, float4 color) {
		if (color.a <= 0.0) {
			discard;
		}

		return CloudOutput(color);
	}
}
