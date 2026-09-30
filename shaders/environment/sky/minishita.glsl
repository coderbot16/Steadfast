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

// Minishita (for "mini Nishita") is an atmospheric scattering model based on
// Nishita Tomoyuki's physically-based atmospheric model, which is the industry
// standard model that is either directly utilized or extended by all other
// physically-based atmosphere models in computer graphics:
//
//   Nishita, Tomoyuki & Sirai, Takao & Tadamura, Katsumi & Nakamae, Eihachiro.
//   (1996). Display of The Earth Taking into Account Atmospheric Scattering.
//   Computer Graphics. 27. 10.1145/166117.166140.
//
// Nishita scattering is as close as you can get to an industry standard in CG,
// but it was written well before it became practical to implement in real-time,
// and the paper does not cover some useful implementation details.
//
// Eric Bruneton extends Nishita scattering with multiple scattering and other
// new features not implemented in Minishita, but also discusses important
// details like physically-based constant values, phase functions, and similar,
// and this implementation references his paper multiple times:
//
//   Eric Bruneton, Fabrice Neyret. Precomputed Atmospheric Scattering.
//   Computer Graphics Forum, 2008, Special Issue: Proceedings of the 19th
//   Eurographics Symposium on Rendering 2008, 27 (4), pp.1079-1086.
//   10.1111/j.1467-8659.2008.01245.x. inria-00288758
//
// Link: https://ebruneton.github.io/precomputed_atmospheric_scattering
//
// As a fun fact, Eric Bruneton also created the OW2 ASM library, which is now
// the industry-standard Java bytecode manipulation library, heavily used in
// Minecraft modding.
//
// I highly recommend reading the Scratchapixel article "Simulating the Colors 
// of the Sky" to gain a background understanding of atmospheric scattering
// before reading the Bruneton and Nishita papers, but all are important.
//
// Otherwise, conceptually, computing the color of the atmosphere in a given
// direction through atmospheric scattering involves marching a ray towards the
// edge of the atmosphere in that direction. At each sample point along that
// ray, we march another ray (the light ray) to the edge of the atmosphere in
// the direction of the light source (sun / moon). We use optical depth as a way
// to compute the transmittance, which is just a way to figure out how much
// light of each color got scattered in the view direction (towards our eye).
// Finally, we multiply this transmittance with the scattering coefficients
// (which mostly determine the atmosphere color) and the phase functions (which
// mostly just make a bright spot around the sun, when multiplied with the
// scattering coefficients).
//
// Minishita scales down Nishita scattering with the following assumptions:
//
// * The planet is Earth-sized, and has an idealized Earth-like atmosphere with
//   clear blue skies that lack pollution or major haze.
// * The viewer (eye) lies at a fixed altitude within the atmosphere. Minecraft
//   has a playable depth range of less than 1 km and actually does take place
//   on a flat overworld, so this is not noticeable during standard gameplay.
// * We can ignore realistic aerial perspective, fog, and light shafts because
//   Minecraft uniquely requires that fog non-obstructively hide the edge of
//   the render distance, which physically-based models do not guarantee.
//
// These simplications allow the following simplifications:
//
// * Instead of requiring an implementation of multiple scattering for accurate
//   sky color, we can just add in a hardcoded nice-looking blue color.
// * The atmosphere is not particularly thick and we can get decently passable
//   results with a bare-minimum number of samples (2 samples along the view
//   ray, 1 sample towards the light from each view sample) if we pick good
//   sample positions.
// * There is no need to model Rayleigh and Mie scattering with separate scale
//   heights for trasmittance calculations, because Mie scattering has a minimal
//   attenuation contribution due to the low amount of of atmospheric pollution.
// * Where the above simplifications give odd colors, we can work around it with
//   some styization (ie, multiply a few things with magic numbers).
//
// Normally, basic Nishita scattering is quite expensive to implement due to the
// total number of light samples that result from standard sample counts. The
// Bruneton and Hillaire atmosphere models both utilize intermediate lookup
// tables to work around this, at the cost of a more complex implementation.
//
// These assumptions allow us to get the same (or better!) performance and a
// similiar level of quality while remining straightforward and self-contained.
//
// A corresponding copy of much of this code also exists in custom uniforms for
// computing the light source colors. If you modify this file, you must also
// ensure to keep that implementation in-sync.
//
// The shader-side implementation of this model follows below.

// Cornette-Shanks approximate analytical model of the Mie phase function
//
// This approximation is identical to the one used by Bruneton.
//
// Originally defined in https://doi.org/10.1364/AO.31.003152:
//
//   William M. Cornette and Joseph G. Shanks, "Physically reasonable analytic
//   expression for the single-scattering phase function," Appl. Opt. 31,
//   3152-3160 (1992)
//
// Input: mu, the dot product of the view vector with the light vector (aka, the
//        cosine of the angle between the given direction and the light source)
//
// Cost: 11 FLOPs (4x fma, 4x mul, 1x div, 1x pow, 1 sub)
float CornetteShanks(float mu) {
	// The value of pi approximated as a single-precision (32-bit) float
	// Copied from https://doc.rust-lang.org/std/f32/consts/constant.PI.html
	const float PI = 3.14159274;

	// Mie preferred scattering direction value used by Bruneton. I was not
	// immediately able to find where he got it from, but it looks fine to me.
	const float g = 0.76;

	// Scaling factor used by Bruneton. Most other papers use 3/2, but as it is
	// a constant multiplied by another constant it can be arbitrary; there is
	// no "right" or "wrong" value.
	return 3.0 / (8.0 * PI)
		// numerator
		* ((1.0 - g * g) * (1.0 + mu * mu))
		// denominator
		/ ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 3.0 / 2.0));
}

// Standard Rayleigh phase function with the same scaling factor as Bruneton.
//
// Input: Same as CornetteShanks.
//
// Cost: 2 FLOPs (1x fma, 1x mul)
float RayleighPhase(float mu) {
	// The value of pi approximated as a single-precision (32-bit) float
	// Copied from https://doc.rust-lang.org/std/f32/consts/constant.PI.html
	const float PI = 3.14159274;

	return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
}

// Ray-sphere intersection calculation that returns the distance of the forward
// and reverse intersection of a line with with a unit sphere centered at
// (0, 0, 0).
//
// The line origin must lie within the sphere, and the direction must be a unit
// vector.
//
// The algorithm derivation is based on the one provided by Wikipedia:
// https://en.wikipedia.org/wiki/Line%E2%80%93sphere_intersection
//
// The equation for the intersection of a ray with a sphere is:
//
// length(origin + distance * direction - center)^2 = radius^2
//
// With a sphere centered at (0, 0, 0) and radius 1, we can simplify to:
//
// length(origin + distance * direction)^2 = 1
//
// This can be rewritten as:
// 
// dot(origin + distance * direction, origin + distance * direction) = 1
//
// Because the dot product is a sum of the product of each vector component, we
// can move the dot products around like they are multiplications:
//
// distance * distance * dot(direction, direction)
// + 2 * distance * dot(direction, origin)
// + dot(origin, origin)
// - 1
// = 0
//
// Given the following:
//
// a = dot(direction, direction) = 1
// b = 2 * dot(direction, origin)
// c = dot(origin, origin) - 1
// d = distance
//
// Then our equation is a quadratic:
//
// ad^2 + bd + c = 0
//
// This quadratic has a solution given by the quadratic equation:
//
// d = (-b +/- sqrt(b^2 - 4ac)) / 2a
//
// However, the direction has length 1 as a unit vector, so
// dot(direction, direction) is 1. Therefore, a = 1.
//
// There are two solutions to this equation, given the +/-. The positive one
// is the intersection with in the forward direction, and the negative one is
// in the reverse direction. Starting with the forward / positive one:
//
// forward = (-b / 2) + sqrt((b^2) / 4 - c)
// forward = -dot(direction, origin)
//     + sqrt(dot(direction, origin) * dot(direction, origin)
//            + 1 - dot(origin, origin))
//
// This leaves the negative / reverse direction. As explained in SkyColor, we
// want to negate this negative distance, which cancels out like so:
//
// reverse = -(-(-b / 2) - sqrt((b^2) / 4 - c))
// reverse = (-b / 2) + sqrt((b^2) / 4 - c)
// reverse = dot(direction, origin)
//     + sqrt(dot(direction, origin) * dot(direction, origin)
//            + 1 - dot(origin, origin))
struct RaySphereIntersect {
	float forward;
	float reverse;
};

RaySphereIntersect RayIntersectUnitSphere(float3 origin, float3 direction) {
	// Cost: 5 FLOPs (2x dot, 1x subtract, 1x fma, 1x sqrt)
	float od = dot(origin, direction);
	float oo = dot(origin, origin);
	float sq = sqrt(od * od + (1.0 - oo));

	// Cost: 2 FLOPs (1x subtract, 1x add)
	float forward = sq - od;
	float reverse = sq + od;

	return RaySphereIntersect(forward, reverse);
}

// Rayleigh scatteing coefficient as used by Bruneton, given wavelengths
// of 680 nm (red), 550 nm (green), and 440 nm (blue)
//
// Expressed with the unit (10^-6)*(m^-1), aka "per 1000km"
static const float3 RAYLEIGH_SCATTER_COEFFICIENTS = float3(5.8, 13.5, 33.1);

// Mie scattering coefficient. Bruneton uses 20.0, but because we take a
// shortcut of using the same scale height for Rayleigh and Mie scattering in
// the scattering integral, this tweak is part of what prevents Mie scattering
// from becoming excessively dominant.
//
// Expressed with the unit (10^-6)*(m^-1), aka "per 1000km"
static const float MIE_SCATTER_COEFFICIENT = 5.0;

// The radius of the planet (Earth) used by Bruneton.
//
// Technically, this is very close to the radius near the poles, which is
// 6357 km, but this is not far off of the equatorial radius of 6378 km.
// 
// https://en.wikipedia.org/wiki/Earth_radius
static const float PLANET_RADIUS_KM = 6360.0;

// These values are somewhat arbitrary though are inspired by Earth-like values.
// I mostly selected them by tweaking them incrementally over time. They are not
// set in stone or derived from underlying physics.
//
// For context, Bruneton uses an atmosphere 60km thick.
//
// Typically, Nishita scattering uses separate scale heights for Rayleigh and
// Mie scattering. Using a single scale height allows merging together some
// calculations at the cost of some appearance changes.
//
// Typically, Mie and Rayleigh scattering use quite different scale heights
// (8 km for Rayleigh, 1.2 km for Mie). However, in our atmosphere the primary
// contribution in the scattering integral is from Rayleigh scattering, so
// we can skip some calculations by using the same height for Mie scattering.
static const float ATMOSPHERE_THICKNESS_KM = 100.0;
static const float SCALE_HEIGHT_KM = 25.0;

// We measure lengths in a space where the atmosphere radius is 1.0, that is,
// the atmosphere is a unit sphere.
//
// This scaling is worth it, because it does not require additional operations
// elsewhere outside of changing the constants in use. It is therefore a free
// reduction in computation because computing intersections against a unit
// sphere involves simpler calculations.
static const float ATMOSPHERE_RADIUS_KM =
	PLANET_RADIUS_KM + ATMOSPHERE_THICKNESS_KM;
static const float KM_TO_UNIT = 1.0 / ATMOSPHERE_RADIUS_KM;
static const float PLANET_RADIUS_UNIT = KM_TO_UNIT * (PLANET_RADIUS_KM);
static const float SCALE_HEIGHT_UNIT = KM_TO_UNIT * (SCALE_HEIGHT_KM);

// Scattering coefficients scaled to work with a unit sphere when calculating
// optical depth.
//
// The original coefficients are given with the units (10^-6)*(m^-1), aka
// "per 1000km". Because the lengths used for optical depth calculations are
// in the space where the atmosphere is a unit sphere, we can avoid extra
// computation by converting the units of these coefficients.
//
// We can multiply by (1 megameter / 1000 km) such that the coefficients are
// "per km", then multiply by the atmosphere radius divided by the unit radius.
// Numerically, the unit radius is 1, hence we get the following:
static const float COEFFICIENT_TO_UNIT = ATMOSPHERE_RADIUS_KM * (1.0 / 1000.0);
static const float3 RAYLEIGH_UNIT =
	COEFFICIENT_TO_UNIT * RAYLEIGH_SCATTER_COEFFICIENTS;
static const float MIE_UNIT = COEFFICIENT_TO_UNIT * MIE_SCATTER_COEFFICIENT;

// In normal atmospheric scattering, we would set the eye height at the real
// height compared to sea level, which would be close to zero in our case.
//
// However, because our near-surface atmosphere approximation wraps the horizon
// around the bottom to mimic the sky of vanilla Minecraft, and because
// Minecraft's height range is very small even between the ocean and the top of
// mountains, it is better to use values from some distance off the ground.
//
// 5 km is not a fixed value, but worked well in my testing. Otherwise, the
// unit height scaling is the same as above.
static const float EYE_HEIGHT_KM = 5.0;
static const float EYE_HEIGHT_UNIT =
	KM_TO_UNIT * (PLANET_RADIUS_KM + EYE_HEIGHT_KM);

// Typically, Nishita scattering involves sampling multiple (4-8) points
// along the light ray per each view sample. Because each view sample would
// then require multiple light samples in an inner loop, light samples can
// easily become the most computationally expensive part.
// 
// As it turns out, at least for for an Earth-like environment when viewing
// from near sea level, we can reduce the number of light samples to as
// little as one per view sample. However, when using a single sample, the
// selection of the sample point becomes significant.
//
// The light samples closer to the edge of the atmosphere contribute
// minimally to the optical depth compared to those deeper within the
// atmosphere. Mathematically, we can reason about this as the part of the
// e^-x curve farther away from the origin where it flattens out.
//
// Therefore, we should select a sample point (value of t) that is low
// (within the range 0 to 1). In my testing, t = 0.15 was acceptable, and it
// happens to match the first view sample point (used in SkyColor).
//
// We compute the change in optical depth identically to the view traces,
// but because we only have one sample along each light trace, there is no
// need to divide by the number of samples, as there is only one.
//
// Cost: 12 FLOPs
float OpticalDepthLight(float3 samplePos, float3 lightDir, float distance) {
	// Cost: 7 FLOPs (2x mul + 5x fma + 1x sqrt + 1x subtract)
	float3 lightSamplePos = lightDir * (0.15 * distance) + samplePos;
	float lightHeight = length(lightSamplePos) - PLANET_RADIUS_UNIT;

	// Cost: 3 FLOPs (2x mul, 1x exp)
	return distance * exp((-1.0 / SCALE_HEIGHT_UNIT) * lightHeight);
}

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	// Scattering coefficients and exposure multiplied together.
	uniform float3 rayleighStrengthSun;
	uniform float mieStrengthSun;
	uniform float3 rayleighStrengthMoon;
	uniform float mieStrengthMoon;

	// These are two colors multiplied with the luminance of the day / night sky
	// respectively and blended with the alpha value. This allows recoloring the
	// sky stylistically, which is currently done during rain (gray) and at
	// night (blue-gray).
	uniform float4 daySkyOverridePremultiplied;
	uniform float4 nightSkyOverridePremultiplied;

	// The ambient sky color is added to the physically-based sky model and is
	// generally a blue color during the day.
	uniform float3 ambientSkyColor;

	// The direction of the sun in world space. We can assume the moon lies in
	// the exact opposite direction.
	uniform float3 worldSunVector;
#endif

// This is the actual implementation of the sky color calculation utilizing
// atmospheric scattering.
//
// The computations of the night and day sky color are logically separate
// because the final sky color is just the sum of each. However, because their
// calculations are largely the same and only diverge with the light traces,
// this implementation computes both sky colors side-by-side to avoid duplicate
// calculations for the view traces.
//
// With some clever tricks we can still further deduplicate calculations of the
// light traces between the sun and moon, which is explained below.
//
// An artifact of this single-scattering transmittance approximation is that
// colors near the horizon are always red-ish or yellowish, which looks
// inaccurate at noon or during normal daytime. We trivially mitigate this
// artifact during the day by adding in some hardcoded blue color based on the
// time of day; though not remotely physically-based, it mitigates the artifacts
// in a visually appealing way. Similarly, at night we recolor the sky entirely
// in a stylized way, which also hides these artifacts.
//
// Ths computational cost is around 200 FLOPs, assuming an in-order scalar GPU
// microarchitecture where most built-in GLSL math functions take 1 cycle.
//
// This is a slightly pessimistic model of modern GPUs, but still helpful for
// reasoning about the performance impact of this function.
//
// For context, a by-the-book Nishita scattering with a transmittance integral
// using 16 view traces and 8 light traces per view trace could cost 2000 - 4000
// FLOPs per pixel, which would be significantly more difficult to utilize in
// real-time rendering.
float3 SkyColor(float3 worldDir) {
	// Compute the cosine of the angle of the view vector with the sun and moon
	// using the dot product. The Rayleigh phase function is the same when
	// negating the cosine, so there is no need to recompute it for the moon.
	//
	// Cost: 6 FLOPs (2x fma, 1x mul, 1x negate, 2 FLOPs per RayleighPhase)
	float muSun = dot(worldDir, worldSunVector);
	float muMoon = -muSun;
	float rayleighPhase = RayleighPhase(muSun);

	// Compute the atmospheric scattering multiplied with the exposure, which
	// leaves only the transmittance to calculate the atmosphere color.
	//
	// Cost: 30 FLOPs (2x 11 FLOPs per CornetteShanks, 2x mul, 2x3 fma)
	float scatterMieSun = CornetteShanks(muSun) * mieStrengthSun;
	float scatterMieMoon = CornetteShanks(muMoon) * mieStrengthMoon;
	float3 scatterSun = rayleighPhase * rayleighStrengthSun + scatterMieSun;
	float3 scatterMoon = rayleighPhase * rayleighStrengthMoon + scatterMieMoon;

	// The color of the atmosphere below the horizon has no clear definition
	// in physically-based atmosphere models, as you cannot actually see that
	// part of the atmosphere in real life, as you would have to see through the
	// surface of the planet to do so.
	//
	// This is not the case in Minecraft with its short render distances.
	//
	// Vanilla Minecraft's sky consists of a blue gradient above the horizon,
	// and the fog color mixed in at and below the horizon. Therefore, it is
	// appropriate to mimic a similiar look in our sky model.
	//
	// By clamping below-horizon directions to the horizon here, we can stretch
	// the transmittance around the horizon while leaving the Rayleigh / Mie
	// phase functions unchanged, preventing stretching the bright spot around
	// the sun below the horizon, too.
	//
	// Cost: 6 FLOPs (1x max, 2x fma, 1x mul, 1x sqrt, 1x div)
	worldDir.y = max(0.0, worldDir.y);
	worldDir = normalize(worldDir);

	// The distance from the eye position to the edge of the atmosphere in the
	// provided view direction.
	//
	// This is the same as RayIntersectUnitSphere(eyePos, worldDir), but
	// specialized from the eye positioned at (0, EYE_HEIGHT_UNIT, 0) as we can
	// assume in this function, and only caring about the forward intersection.
	//
	// Cost: 4 FLOPs (1x mul, 1x subtract, 1x sqrt, 1x fma)
	float od = EYE_HEIGHT_UNIT * worldDir.y;
	const float oo = EYE_HEIGHT_UNIT * EYE_HEIGHT_UNIT;
	float atmosphereDistance = sqrt(od * od + (1.0 - oo)) - od;

	// We select two view sample positions along the view ray. Because typical
	// reference implementations use upwards of 16 samples, the positioning
	// of our two samples are important; hence, they are not uniformly placed.
	//
	// The first sample, within the lower atmosphere, primarily contributes to
	// the color of the sky during daytime. The second sample, within the upper
	// atmosphere, primarily contributes to the color of the sky in the early
	// sunrise and late sunset.
	//
	// Finally, we calculate the height above the planet at each view sample
	// point.
	//
	// Cost: 18 FLOPs (4x mul + 2x5 fma + 2x sqrt + 2x subtract)
	const float3 eyePos = float3(0.0, EYE_HEIGHT_UNIT, 0.0);
	float3 samplePos1 = worldDir * (0.15 * atmosphereDistance) + eyePos;
	float3 samplePos2 = worldDir * (0.65 * atmosphereDistance) + eyePos;
	float vHeight1 = length(samplePos1) - PLANET_RADIUS_UNIT;
	float vHeight2 = length(samplePos2) - PLANET_RADIUS_UNIT;

	// Next, we calculate the change in optical depth caused by traveling
	// through both sample points. To get the total optical depth, we integrate
	// e^(-h/H)ds with respect to the path distance ("s").
	//
	// The change in optical depth at each sample point, with two sample points,
	// is the path distance divided by the number of samples times the density
	// ration, e^(-h/H), at the sample point.
	//
	// It's better to keep the multiply outside since ISAs like GCN have the
	// option of using an OMOD to make the multiply basically free.
	//
	// Cost: 6 FLOPs (2x fma, 2x exp, 2x mul)
	const float unitScale = (-1.0 / SCALE_HEIGHT_UNIT);
	float depthV1 = 0.5 * (atmosphereDistance * exp(unitScale * vHeight1));
	float depthV2 = 0.5 * (atmosphereDistance * exp(unitScale * vHeight2));

	// From each sample point along the view ray, we then trace towards the
	// light source, which similarly requires the distance to the edge of the
	// atmosphere.
	//
	// Because the sun and the moon vectors are the negative of each other, we
	// can exploit an interesting property of the ray-sphere intersection
	// calculation: that it typically returns a positive distance of the forward
	// intersection, but also a negative distance for the reverse intersection,
	// to advance backwards along the ray.
	//
	// In our case, if we compute the intersection in the direction of the sun,
	// the positive distance is the distance to the sun, and the negative
	// distance is towards the moon. Negating that gives the distance to the
	// moon, which we need and now no longer need to compute separately.
	//
	// The final piece of the puzzle is moving the negation inside the intersect
	// function, where it cancels out for a further simplification. All that is
	// the "bidirectional" part of the ray-sphere intersection.
	//
	// Cost: 14 FLOPs (7 FLOPs per RayIntersectUnitSphere)
	RaySphereIntersect d1 = RayIntersectUnitSphere(samplePos1, worldSunVector);
	RaySphereIntersect d2 = RayIntersectUnitSphere(samplePos2, worldSunVector);
	float dS1 = d1.forward;
	float dM1 = d1.reverse;
	float dS2 = d2.forward;
	float dM2 = d2.reverse;

	// We compute the change in optical depth identically to the view traces,
	// but we only have one sample along each light trace.
	//
	// Cost: 48 FLOPs (12 FLOPs per OpticalDepthLight)
	float depthLightSun1  = OpticalDepthLight(samplePos1,  worldSunVector, dS1);
	float depthLightSun2  = OpticalDepthLight(samplePos2,  worldSunVector, dS2);
	float depthLightMoon1 = OpticalDepthLight(samplePos1, -worldSunVector, dM1);
	float depthLightMoon2 = OpticalDepthLight(samplePos2, -worldSunVector, dM2);

	// The stylized scale values mitigate some of the artifacts of our
	// simplications, including selecting a single light sample at t = 0.15 an
	// using the same scale height for Mie and Rayleigh scattering.
	//
	// These are not physically-based, but these were selected because I thought
	// they looked nice.
	//
	// Technically, you are also supposed to add the two optical depth samples
	// along the view vector. However, I did not like how it looked, and it
	// probably does not work well because the two samples are so far apart.
	//
	// Cost: 8 FLOPs (4x fma, 4x mul)
	float opticalDepthS1 = (depthLightSun1  * 0.5) + (depthV1 * 0.05);
	float opticalDepthS2 = (depthLightSun2  * 0.5) + (depthV2 * 3.0);
	float opticalDepthM1 = (depthLightMoon1 * 0.5) + (depthV1 * 0.05);
	float opticalDepthM2 = (depthLightMoon2 * 0.5) + (depthV2 * 3.0);

	// The final step of the integral is to sum up, along each view sample
	// position, the density ratio, the change in path distance, and the actual
	// transmittance contribution in the exponent.
	//
	// The density ratio times the change in path distance is the same as the
	// optical depth contribution we already calculated for each view sample,
	// hence why we re-use it here.
	//
	// Cost: 36 FLOPs (4x3 mul + 4x3 exp + 4x3 mul)
	float3 tmS = depthV1 * exp(opticalDepthS1 * (-(RAYLEIGH_UNIT + MIE_UNIT)))
	           + depthV2 * exp(opticalDepthS2 * (-(RAYLEIGH_UNIT + MIE_UNIT)));
	float3 tmM = depthV1 * exp(opticalDepthM1 * (-(RAYLEIGH_UNIT + MIE_UNIT)))
	           + depthV2 * exp(opticalDepthM2 * (-(RAYLEIGH_UNIT + MIE_UNIT)));

	// Multiply transmittance and scattering to get the atmosphere color.
	//
	// Then, to prepare for changing the color while maintaining luminance,
	// calculate the luminance of the atmosphere color.
	//
	// Cost: 12 FLOPs (2x3 mul, 2x2 fma, 2x mul)
	float3 day = tmS * scatterSun;
	float3 night = tmM * scatterMoon;
	float luminanceDay = dot(day, float3(0.2126, 0.7152, 0.0722));
	float luminanceNight = dot(night, float3(0.2126, 0.7152, 0.0722));

	// Micro-optimized variant of the following, allowing tweaking the color
	// of the sky while retaining its luminance:
	//
	// day = lerp(day, luminanceDay * daySkyOverride.rgb, daySkyOverride.a);
	// night = lerp(night, luminanceNight * nightSkyOverride.rgb, 
	//                                                      nightSkyOverride.a);
	// float3 sky = day + night + ambientSkyColor;
	//
	// We also pre-multiply the alpha value into the day and night sky override,
	// and move the subtraction as well.
	//
	// Cost: 12 FLOPs (4x3 fma)
	float3 sky = day * daySkyOverridePremultiplied.a + ambientSkyColor;
	sky += night * nightSkyOverridePremultiplied.a;
	sky += luminanceDay * daySkyOverridePremultiplied.rgb;
	sky += luminanceNight * nightSkyOverridePremultiplied.rgb;

	return sky;
}
