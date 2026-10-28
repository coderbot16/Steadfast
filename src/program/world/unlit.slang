struct UnlitVaryings {
	float4 tinting;
	float2 uv;
}

struct UnlitOutput {
	float4 fragmentColor;
}

extern static const float UNLIT_BRIGHTNESS;

#include "lib/srgb.slang"

import aperture;
import object_shader;

struct UnlitShader : Shader<UnlitVaryings, UnlitOutput> {
	static void emitVertex(
		Vertex v,
		ObjectTransforms transforms,
		out UnlitVaryings data,
		out float4 pos
	) {
		data.tinting = v.color();
		data.uv = v.uv();
		pos = mul(transforms.projection, mul(transforms.view, v.pos()));
	}

	static UnlitOutput shadeSurface(PixelData objectData, UnlitVaryings data) {
		float4 srgb = data.tinting;

		if (let sampler = objectData.albedo()) {
			srgb *= sampler.sampleTexture(data.uv);
		}

		float4 fragmentColor = ap.discardCutout(SrgbToLinear(srgb));
		fragmentColor.rgb *= UNLIT_BRIGHTNESS;

		return UnlitOutput(fragmentColor);
	}
}
