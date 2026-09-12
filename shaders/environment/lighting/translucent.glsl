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

// Water surface
#define BASIC 0
#define NOISE 1
// The water surface model. Each option has varying quality and performance.
#define WATER_SURFACE NOISE // [BASIC NOISE]
#if WATER_SURFACE == NOISE
	#include "/environment/water/surface_noise.glsl"
	#define WATER_PARALLAX
#else /* WATER_SURFACE == BASIC */
	#include "/environment/water/surface_basic.glsl"
	// TODO: Support water parallax on the basic water surface
#endif

#ifdef WATER_PARALLAX
	#include "/environment/water/parallax.glsl"

	// Distance in meters to apply parallax mapping to the water surface.
	#define WATER_PARALLAX_DISTANCE 48.0 // [8.0 16.0 24.0 32.0 48.0 64.0]
#endif

// Screenspace terrain reflections
#include "/lib/raytrace.glsl"

// Screenspace terrain refraction for water
#include "/environment/water/refraction.glsl"

#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
	// Integration between water absorption and refraction
	#include "/environment/water/absorption_refraction.glsl"

	// Sky light buffer for aiding refractive-based water absorption
	// TODO: This will prevent water absorption from working perfectly with
	//       Voxy. This is not an immediate issue at the moment since it is
	//       rarely visible, but it should be fixed...
	uniform sampler2D colortex5;
#endif

// Enables rough screenspace refraction, which adds blur to screenspace
// refraction on water. This is more appropriate for our moving water
// surface which is not actually perfectly smooth.
// #define ROUGH_REFRACTION

// Strength of screenspace rough refractions (refraction blur), when enabled
#define ROUGH_REFRACTION_STRENGTH 0.45 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	// Color buffer to trace SSR in
	uniform sampler2D colortex4;

	#ifdef ROUGH_REFRACTION
		// Downsampled refraction/reflection buffer
		uniform sampler2D colortex6;
	#endif

	// We need to use the view matrix to convert between world-space and
	// view-space.
	uniform mat4 gbufferModelView;
#endif

#if !defined(DH_TERRAIN)
	// A fast and visually appealing approximation of refractions.
	#define SCREENSPACE_REFRACTION

	#if defined(SCREENSPACE_REFRACTION)
		#define WATER_REFRACTION_SAMPLE
	#endif
#endif

#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
	#define WATER_REFRACTION_SAMPLE
#endif

vec3 parallaxWaterNormal(
	vec3 incident,
	vec3 cameraRelativePos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	bool verticalNormal,
	vec3 worldNormal,
	vec3 worldTangent,
	vec3 worldBinormal
) {
	mat3 worldTBN = mat3(worldTangent, worldBinormal, worldNormal);
	vec2 waterWorldPos = cameraRelativePos.xz + cameraPosition.xz;

	// If the normal vector is facing down instead of up, we need to flip the
	// results of our non-TBN calculations.
	float facing = worldNormal.y >= 0.0 ? 1.0 : -1.0;

	// TODO: Limit WATER_PARALLAX_DISTANCE by vanilla terrain render distance
	//       to ensure smooth transition to DH water.
	#if defined(WATER_PARALLAX) && !defined(DH_TERRAIN)
		// Fade out parallax mapping on faraway surfaces to avoid wasting
		// performance applying parallax mapping where the effect is not visible
		//
		// Also prevent parallax effects from taking place on sideways water,
		// because that does not really make sense with our 2D-only formulation
		// of water height.
		float parallaxStrength = clamp(
			(WATER_PARALLAX_DISTANCE - length(cameraRelativePos))
				/ (WATER_PARALLAX_DISTANCE * (1.5 - 1.0)),
			0.0,
			float(verticalNormal));

		if (parallaxStrength > 0.0001) {
			// Note: this is safe instead of using (worldTBN * incident) because
			// we already checked that the normal vector wasn't horizontal.
			vec3 viewDirTangent = facing * incident.xzy;
			vec2 offsetPos = WaterSurfaceParallaxMapping(
				waterWorldPos,
				ddxWorldPos,
				ddyWorldPos,
				timeSeconds,
				viewDirTangent);
			waterWorldPos = mix(waterWorldPos, offsetPos, parallaxStrength);
		}
	#endif

	vec3 waterNormal = WaterNormal(
		waterWorldPos,
		ddxWorldPos,
		ddyWorldPos,
		timeSeconds);


	return worldTBN * waterNormal;
}

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	// These are the view-space vectors that represent a one-pixel offset along
	// the X and Y axis in screen-space, respectively.
	uniform vec3 viewOffsetPixelX;
	uniform vec3 viewOffsetPixelY;
#endif

// This function is a method of computing the partial derivative of the world
// space position with respect to the screen space position (screen space
// partial derivative) using triangle intersections and the finite-difference
// method, but without requiring the calculations of a neighboring fragment.
//
// This technique is strongly inspired by the following paper:
//
//   Christopher A. Burns and Warren A. Hunt, The Visibility Buffer:
//   A Cache-Friendly Approach to Deferred Shading, Journal of Computer Graphics
//   Techniques (JCGT), vol. 2, no. 2, 55-69, 2013
//   Available online http://jcgt.org/published/0002/02/04/
//
// However, this implementation is a simpler variant that excludes the logic
// required for vertex attribute interpolation and fetching vertex positions,
// in favor of constructing a "hypothetical triangle" for the purpose of the
// intersection test that simplifies the resulting derivative calculations.
void dWorldPosdxdy(
	// View position of the fragment
	vec3 viewPos,
	vec3 worldTangent,
	vec3 worldBinormal,
	// dFdx(worldPos), computed with the finite distance method
	out vec3 ddxWorldPos,
	// dFdy(worldPos), computed with the finite distance method
	out vec3 ddyWorldPos
) {
	// Form a triangle in view-space with edge lengths of 1 with a plane that is
	// parallel to and overlapping the triangle plane that this fragment came
	// from. This "hypothetical triangle" is just to make our calculations more
	// straightforward but does not change their results.
	vec3 edge1 = mat3(gbufferModelView) * worldTangent;
	vec3 edge2 = mat3(gbufferModelView) * worldBinormal;

	// This is the Möller–Trumbore intersection algorithm:
	// https://en.wikipedia.org/wiki/Möller–Trumbore_intersection_algorithm
	//
	// I am summarizing the relevant part of the paper here.
	//
	// Given a triangle with vertices v0, v1, v2, we can define the following:
	//
	// edge1 = v1 - v0
	// edge2 = v2 - v0
	//
	// Then, for a ray with origin O and direction D, the ray distance (t) and
	// barycentric coordinates u and v are given by the following system of
	// equations, with T defined as O - v0:
	//
	//                        [ t ]
	// [ -D, edge1, edge2 ] * [ u ] = T
	//                        [ v ]
	//
	// Per Cramer's Rule, the solution is given by:
	//
	// [ t ]             1              [ det( T, edge1, edge2) ]
	// [ u ] =  --------------------- * [ det(-D,     T, edge2) ]
	// [ v ]    det(-D, edge1, edge2)   [ det(-D, edge1,     T) ]
	//
	// We do not care about the value of t here, and can simplify to:
	//
	//                   1
	// [ u ] =  --------------------- * [ det(-D,     T, edge2) ]
	// [ v ]    det(-D, edge1, edge2)   [ det(-D, edge1,     T) ]
	//
	// We trace from an origin of (0, 0, 0), so the vector from viewPos to the
	// origin is just -viewPos. Because the negatives cancel out below, we can
	// just treat the vector from the center vertex (v0, viewPos) to the origin
	// as viewPos. Therefore, we can set T as viewPos.
	//
	// From linear algebra:
	// det(A, B, C)
	// = dot(cross(A, B), C)
	// = -dot(cross(A, C), B)
	// = -dot(cross(C, B), A)
	//
	// Expanding these determinants as cross products:
	//
	//                   1
	// [ u ] =  --------------------------- * [ dot(cross(D, edge2), viewPos) ]
	// [ v ]    dot(cross(D, edge2), edge1)   [ dot(cross(viewPos, edge1), D) ]
	//
	// To avoid repetition, we introduce two variables:
	//
	// q = cross(viewPos, edge1)
	// p = cross(D, edge2)
	vec3 q = cross(viewPos, edge1);

	// These directions set up the intersection calculation we are using to find
	// the screen-space partial derivatives. We trace towards the triangle in
	// the direction of the current fragment, but then add one pixel up and one
	// pixel to the side for each trace.
	vec3 incident = normalize(viewPos);
	vec3 offsetX = incident + viewOffsetPixelX;
	vec3 offsetY = incident + viewOffsetPixelY;

	// Intersection for the trace along the screen in the X direction, in
	// barycentric coordinates.
	vec3 pdx = cross(offsetX, edge2);
	float invdetdx = 1.0f / dot(pdx, edge1);
	float dudx = invdetdx * dot(pdx, viewPos);
	float dvdx = invdetdx * dot(offsetX, q);

	// Intersection for the trace along the screen in the Y direction, in
	// barycentric coordinates.
	vec3 pdy = cross(offsetY, edge2);
	float invdetdy = 1.0f / dot(pdy, edge1);
	float dudy = invdetdy * dot(pdy, viewPos);
	float dvdy = invdetdy * dot(offsetY, q);

	// Transform the screen-space derivative from barycentric coordinates back
	// to world-space. The first barycentric coordinate is the movement toward
	// the first vertex, and the second is the movement towards the second
	// vertex.
	ddxWorldPos = worldTangent * dudx + worldBinormal * dvdx;
	ddyWorldPos = worldTangent * dudy + worldBinormal * dvdy;
}

vec4 TranslucentLighting(
	vec4 fragmentColor,
	vec3 worldNormal,
	mat3 worldTBN,
	vec3 cameraRelativePos,
	vec3 viewPos,
	float reflectionStrength,
	float skyLight,
	uint materialID
) {
	bool verticalNormal = worldNormal.y > 0.9999;

	// Adjust output for the remultiplied alpha blending mode:
	// glBlendFunc(sfactor=GL_ONE, dfactor=GL_ONE_MINUS_SRC_ALPHA)
	// 
	// Used for added flexibility with reflection calculations instead of:
	// glBlendFunc(sfactor=GL_SRC_ALPHA, dfactor=GL_ONE_MINUS_SRC_ALPHA)
	float srcAlpha = 1.0 - fragmentColor.a;
	fragmentColor.rgb *= fragmentColor.a;
	vec3 normal = worldNormal;

	// We can get the view-space incident vector (needed for reflection and
	// refraction) from normalizing the view position as the incident vector
	// from our view is necessarily the direction of the fragment in view space!
	vec3 incident = normalize(cameraRelativePos);

	vec3 worldTangent  = worldTBN[0];
	vec3 worldBinormal = worldTBN[1];

	// Compute ddxWorldPos = dFdx(worldPos) and ddyWorldPos = dFdy(worldPos)
	// without actually requiring the screen-space partial derivative functions
	// dFdx or dFdy, which are not compatible with discarded fragments or any
	// other form of non-uniform control flow. This is primarily a limitation in
	// practice with Voxy.
	//
	// The two world-space vectors must be of length 1 to avoid needing to
	// divide later on within the function, and they must be orthogonal with
	// both each other and the normal vector for correct results, hence by
	// definition they must be the tangent and binormal vectors, but their
	// order does not matter.
	vec3 ddxWorldPos;
	vec3 ddyWorldPos;
	dWorldPosdxdy(
		// Inputs
		viewPos, worldTangent, worldBinormal,
		// Outputs
		ddxWorldPos, ddyWorldPos);

	#ifdef SCREENSPACE_REFRACTION
		if (materialID == WATER) {
			normal = parallaxWaterNormal(
				incident,
				cameraRelativePos,
				ddxWorldPos.xz,
				ddyWorldPos.xz,
				verticalNormal,
				worldNormal,
				worldTangent,
				worldBinormal);
		}
	#endif

	if (reflectionStrength > 0.0001) {
		// For non-water, allow the fresnel to go to zero and use the face
		// normal instead of any normal-mapping.
		//
		// Water uses a different F0 (minimum fresnel) value as well as normal
		// mapping for moving waves.
		//
		// If we wanted to be physically-based, the F0 for water should be
		// around 0.02 per Shlick's approximation, but that makes it too
		// see-through.
		float F0 = materialID == WATER ? 0.1 : 0.0;

		// If we didn't already calculate the water normal, calculate it now.
		#ifndef SCREENSPACE_REFRACTION
			if (materialID == WATER) {
				normal = parallaxWaterNormal(
					incident,
					cameraRelativePos,
					ddxWorldPos.xz,
					ddyWorldPos.xz,
					verticalNormal,
					worldNormal,
					worldTangent,
					worldBinormal);
			}
		#endif

		// First, determine the reflected normal.
		//
		// While a bit atypical, we compute this reflection with world-space
		// vectors instead of view-space vectors. This leads to no visual
		// difference in most scenes, but when under the effects of nausea,
		// view space is warped and skewed, and these sorts of calculations
		// give wacky results, while doing them in world space leads to
		// correct reflection results.
		vec3 reflected = reflect(incident, normal);

		// TODO: This is a hack. Sometimes, we hit the "back" of a wave we
		// technically should not be able to see, and the reflected direction
		// goes underwater. Checking against the face normal detects this and we
		// fall back to using the face normal. This still is not correct, but is
		// better than the seriously ugly artifacts of when that happens.
		//
		// Not sure how to fix this best.
		if (dot(worldNormal, reflected) <= 0.0) {
			reflected = reflect(incident, worldNormal);
		}
		
		// Fresnel calculation. The actual fresnel value is modulated by the sky
		// reflection strength, which is affected by material properties and the
		// sky light strength and isn't just 1.0.
		//
		// The incident vector and normal vector are always 90 degrees or more
		// apart from each other - conceptually, the incident vector is always
		// sideways or downwards if the normal vector is upwards. This means the
		// dot product is always negative so adding it is really a subtraction.
		//
		// Otherwise, this follows the physically-based Shlick's approximation
		// for the fresnel factor:
		// https://en.wikipedia.org/wiki/Schlick's_approximation
		float fresnel = F0 + (1.0 - F0) * pow(1.0 + dot(incident, normal), 5.0);
		fresnel *= reflectionStrength;

		// Very basic reflections using the sky gradient. There is no need to
		// apply fog to the sky reflection, as we apply fog at the very end for
		// the overall fragment (reflection + refraction + its own color.)
		vec3 skyReflection = SkyDither(gl_FragCoord.xy, SkyColor(reflected));
		vec3 reflectedColor = skyReflection;

		// Allows water and ice to reflect the world in addition to the sky.
		#define SCREENSPACE_REFLECTIONS

		#ifdef SCREENSPACE_REFLECTIONS
			// Note: We don't have a separate terrain reflection strength. As it
			// turns it, in the same places that sky reflections look bad, the
			// limitations of SSR makes terrain reflections look bad too.
			// 
			// As a result, reflections are reserved for outdoors, not caves and
			// indoors.
			vec2 hitPos;
			vec3 hitViewPos;

			// Controls the base thickness and increase in thickness over
			// distance during raytracing, effectively the tolerance of
			// determinining whether we are going
			// to accept a hit or not.
			//
			// X: initial thickness in meters
			// Y: additional increase in meters per raytracing step not directly
			//    related to distance
			vec2 thicknessControl;

			// The mirror-like reflection of ice makes it harder to hide the
			// stretching aspect caused by thickness, so use a low thickness for
			// that. However, the wavy reflection of water easily hides the
			// stretching, and reflecting something looks better than nothing in
			// that case.
			thicknessControl = vec2(materialID == ICE ? 0.5 : 1.0, 1.0);
			
			vec3 reflectedView = mat3(gbufferModelView) * reflected;

			bool hit = Raytrace(
				opaqueDepth,
				projectionMatrix,
				inverseProjectionMatrix,
				viewPos,
				reflectedView,
				thicknessControl,
				hitPos,
				hitViewPos);

			#if defined(DISTANT_HORIZONS) && !defined(DH_TERRAIN)
				// Try again for a distant hit if we didn't get a nearby hit
				//
				// TODO: Only do this if the reason for the miss was a depth
				// buffer escape along the Z axis.
				if (!hit) {
					hit = Raytrace(
						opaqueDepthDistant,
						projectionMatrixDistant,
						inverseProjectionMatrixDistant, 
						viewPos,
						reflectedView,
						thicknessControl,
						hitPos,
						hitViewPos);
				}
			#endif

			if (hit) {
				vec2 hitPosAbs = abs(hitPos * 2.0 - 1.0);
				float hitPosMax = max(hitPosAbs.x, hitPosAbs.y);
				float visibility = min(1.0, (1.0 - hitPosMax) / 0.10);

				// When we are looking upwards and there is an upwards-facing
				// water face, the Z-component of the normal  in view-space is
				// positive, and when we are looking downwards, it is negative.
				//
				// Essentially, this means that we only fade out the reflections
				// at the edge when it is necessary, ie, we are looking downward
				// at the water instead of level or upwards.
				//
				// This transformation is just getting the Z component of
				// the normal in view space.
				float viewNormalZ = dot(gbufferModelView[2].xyz, worldNormal);
				visibility = mix(1.0, visibility, clamp(viewNormalZ, 0.0, 1.0));

				vec3 terrainReflection = texture(colortex4, hitPos).rgb;
				vec3 cameraRelativePosW = 
					(gbufferModelViewInverse * vec4(hitViewPos, 1.0)).xyz;
				float fragDistanceW = max(
					abs(cameraRelativePosW.y),
					length(cameraRelativePosW.xz)
				);

				// Note: Using sky light strength of here, not of where we are
				// reflecting - this could look odd with caves reflecting, but
				// I have not noticed any issue and loading the sky light
				// texture would not be free.
				vec4 fogForWater = Fog(
					skyReflection,
					fragDistanceW,
					fragDistanceW,
					skyLight);

				// We apply fog to the terrain reflection, but critically, the
				// fog we are applying is from the standpoint of the reflected
				// direction - that is, we are fading the terrain reflection
				// into its background, even if the water the reflection will be
				// applied to is in a different situation fog-wise.
				reflectedColor = mix(
					reflectedColor,
					terrainReflection * fogForWater.a + fogForWater.rgb,
					visibility);
			}
		#endif

		// Mix in the reflection color based on the fresnel factor, and reduce
		// the intensity of the background (destination) color accordingly.
		//
		// The short version is that we need to reduce the visibility of the
		// terrain behind the water even more when incorporating reflections.
		fragmentColor.rgb = mix(fragmentColor.rgb, reflectedColor, fresnel);
		srcAlpha *= 1.0 - fresnel;
	}

	#if defined(WATER_REFRACTION_SAMPLE)
		// Only water is refractive for now as with our refraction calculation,
		// a normal map is a requirement for refraction, as otherwise the face
		// normal and normalmap normal are the same and we have no variance to
		// refract with.
		//
		// This is actually pretty desirable underground as it makes water far
		// more noticeable than it otherwise would be.
		//
		// TODO: Permit sideways water to refract, or make it just opaque.
		//       Just do something.
		if (materialID == WATER && verticalNormal) {
			// Screen-space refraction implementation. We are working within the
			// following constraints:
			//
			// - Realistic refraction is relatively unintuitive: when you
			//   encounter it in real life, it is a "whoa, weird, neat"
			//   situation, but when it is in a renderer, it feels like a bug.
			//   It's also not gameplay-friendly: objects appear in
			//   substantially different locations than they actually are.
			//   That would make mining sand from above water for example an
			//   odd experience.
			//
			// - Even if we wanted realism, all we have is data on the screen. 
			//   Realistic refraction will hide things that are on screen, and
			//   show underwater objects not visible on screen. This will
			//   reveal obvious artifacts when we can't access this information.
			//
			// - Realistic refraction results in such extreme distortion that we
			//   need to actually raytrace through the scene, but the artifacts
			//   and cost of doing so are not acceptable in screen space.
			// 
			// These combined factors mean that actually simulating physically
			// based refraction is a NOT the goal. Instead, the effect we are
			// going for is warping the background based on how deep the water
			// is, such that a given fragment moves around fairly uniformly
			// around where it would otherwise be, rather than offsetting the
			// background significantly upwards/downwards from its actual
			// location.
			//
			// Instead, we use a non-physically-based refraction direction
			// calculation. We take the incident vector, and add the difference
			// between the normal-mapped normal and the face normal. Finally, we
			// normalize the result so that we can calculate offsets along a ray
			// with it.
			//
			// When we subtract the face normal from the wave normal, what we
			// actually get is a short vector that points slightly downwards but
			// otherwise in the direction of the wave.
			//
			// In practice, this approximates a side-to-side movement of the
			// refracted direction while broadly going in the same direction as
			// the original incident vector, which means that the incident
			// vector and refracted vector are close enough to make some
			// important approximations.
			vec3 refractedDir = normalize(incident + normal - worldNormal);
			float maxRefractDistance = 32.0;

			vec3 refractedDirView = mat3(gbufferModelView) * refractedDir;

			// TODO: Simplify this or perhaps make refraction not care about
			//       the depth buffer at all.
			vec3 refractedScreenPos = RefractTrace(
				opaqueDepth, projectionMatrix, inverseProjectionMatrix,
			 	viewPos, refractedDirView, maxRefractDistance
			);
			vec3 ndcPosRefracted = refractedScreenPos * 2.0 - 1.0;
			vec4 viewPosHRefracted =
				inverseProjectionMatrix * vec4(ndcPosRefracted, 1.0);
			vec3 viewPosRefracted =
				vec3(viewPosHRefracted.xyz / viewPosHRefracted.w);

			#if defined(DISTANT_HORIZONS) && !defined(DH_TERRAIN)
				if (refractedScreenPos.z == 1.0) {
					refractedScreenPos = RefractTrace(
						opaqueDepthDistant,
						projectionMatrixDistant,
						inverseProjectionMatrixDistant,
						viewPos,
						refractedDirView,
						maxRefractDistance
					);

					ndcPosRefracted = refractedScreenPos * 2.0 - 1.0;
					viewPosHRefracted = inverseProjectionMatrixDistant
						* vec4(ndcPosRefracted, 1.0);
					viewPosRefracted =
						vec3(viewPosHRefracted.xyz / viewPosHRefracted.w);
				}
			#endif

			vec3 dstColor = RefractionSafeSample(
				colortex4, 
				refractedScreenPos.xy
			).rgb;

			#ifdef ROUGH_REFRACTION
				dstColor = mix(
					dstColor,
					texture(colortex6, refractedScreenPos.xy).rgb,
					ROUGH_REFRACTION_STRENGTH);
			#endif

			#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
				// The world-space upwards vector (0, 1, 0), transformed into
				// view space.
				//
				// Taking the dot product of the this vector and another view
				// space vector gives the Y-component of that vector in world
				// space, which is useful for measuring vertical distance and if
				// a vector is pointing up or down.
				//
				// This is just the simplified form of the standard matrix
				// multiplication for transforming from world space to view
				// space.
				//
				// TODO: This leads to inaccurate results during nausea
				vec3 upVector = gbufferModelView[1].xyz;

				dstColor = RefractionBasedWaterAbsorption(
					refractedScreenPos, viewPosRefracted, upVector,
					viewPos, verticalNormal,
					dstColor, colortex5
				);
			#endif

			// To apply the refraction, sample the background texture at the
			// refracted position. The sampled color becomes are new background,
			// and as a result, we replicate the blending equation with it as
			// the "destination color" in terms of OpenGL blending.
			//
			// Our blend equation is:
			//
			//   BlendResult = (SrcColor * 1) + (DstColor * SrcAlpha)
			//
			// In terms of our variable names, this is:
			//
			//   fragmentColor = (fragmentColor * 1) + (dstColor * srcAlpha)
			//
			// Which simpifies to the following:
			fragmentColor.rgb += srcAlpha * dstColor;

			// Finally, make the fragment opaque based on the above blending
			// equation.
			//
			// You might wonder - what is the point of forward-rendered
			// translucents if refraction means we have to turn off translucency
			// anyways? The answer is that we can still get benefits if
			// translucent objects are in front of refractive objects.
			//
			// In other words, you can see water through stained glass if
			// stained glass doesn't have refraction enabled.
			srcAlpha = 0.0;
		}
	#endif

	return vec4(fragmentColor.rgb, 1.0 - srcAlpha);
}
