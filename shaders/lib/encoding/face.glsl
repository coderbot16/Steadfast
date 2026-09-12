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

// Common encoding of per-face data that does not vary with each vertex.
//
// The following data is currently packed into a single 32-bit unsigned integer:
//
// * The face normal in world space
// * The tangent and handedness needed to reconstruct the world space TBN matrix
// * The material ID
//
// The face normal is first encoded with octahedral unit vector encoding, giving
// two values from 0 to 1, then these values are re-encoded as fixed-point
// integers and rounded accordingly. Note that with octahedral encoding, the
// 1.0 and 0.0 are NOT equivalent (the values do not wrap around), unlike angle
// measurements.
//
// The current encoding is: Octahedral X (9 bits), Octahedral Y (9 bits),
// and material ID (4 bits).
//
// This leaves 10 bits available for a diamond-encoded tangent vector and
// corresponding bitangent handedness bit, so we can store the material ID and
// data to reconstruct the TBN matrix in 32 bits. Neat!
//
// There is a fixed amount of buffer space available on graphics hardware for
// transferring data from the vertex shader to the fragment shader, and this is
// a common bottleneck in Minecraft, so packing this data into a single 32-bit
// value helps reduce this bottleneck.
//
// Reference for the octahedral unit vector encoding in use:
//
//  Quirin Meyer, Jochen Süßmuth, Gerd Sußner, Marc Stamminger, and Günther
//  Greiner. 2010. On floating-point normal vectors. In Proceedings of the 21st
//  Eurographics conference on Rendering (EGSR'10). Eurographics Association,
//  Goslar, DEU, 1405–1409. https://doi.org/10.1111/j.1467-8659.2010.01737.x
//
// PDF link: https://coburggraphicslab.github.io/files/Meyer10OFN.pdf

// With the diamond shape of the top and bottom projection of an octahedron, we
// can fill a square by folding one diamond outward into the 4 triangles on the
// edges of the other diamond within the square.
//
// Applying this function again reverses it. In other words, fold(fold(v)) = v.
vec2 fold(vec2 octahedral) {
	// With the diamond shape, we can fill a square by using the 4 triangles
	// on the edges of the diamond within the square.
	//
	// Our basic strategy is to take the absolute value of the coordinates to
	// get into the upper right quadrant, then mirror the point across the line
	// y = x (diagonal), then move back to the original square by restoring
	// the sign values.
	//
	// Excuse the stretching from the limitations of ASCII art:
	// 
	// |----/|\----|
	// |   / | \M  |
	// |  /  |  \ R|
	// | /   |  P\ |
	// |-----+-----|
	// | \   |   / |
	// |  \  |  /  |
	// |   \ | /   |
	// |----\|/----|
	//
	// Consider (0.5, 0.33) located at P. Subtracting from 1.0 would give
	// (0.5, 0.67) located at M. But, if we visually unwrap the octahedron,
	// we can easily see that we ended up on the wrong side of the octahedral
	// face. Instead, we need to end up at R, which swapping Y and X does.
	//
	// This gives us our wrapping algorithm:
	vec2 mirrored = 1.0 - abs(octahedral.yx);

	// Annoyingly, we cannot actually use the sign function here, as sign(0)
	// gives 0, when we actually need 1. But this is just a "compare" and a
	// "select" instruction in comparison to just extracting the sign bit.
	//
	// When we have zeroes, we aren't selecting a quadrant but rather are
	// just creating a singularity at the center. This needs to be -1 or 1.
	vec2 quadrant = vec2(
		octahedral.x >= 0.0 ? 1.0 : -1.0,
		octahedral.y >= 0.0 ? 1.0 : -1.0
	);

	return mirrored * quadrant;
}

// Given a normalized unit vector, returns the octahedral encoding of that
// vector with each component in the 0 to 1 range.
vec2 EncodeUnitVector(vec3 v) {
	// Project the vector on to an octahedron using the 1-norm. In this step,
	// we have projected the vector assuming that it is pointing upward, and it
	// occupies a diamond shape on a flat plane from [-1, -1] to [1, 1].
	vec2 octahedral = v.xy / dot(abs(v), vec3(1.0));

	// To store both the bottom and top diamonds of the octahedron, we can fold
	// the bottom octahedron outwards to fill in the gaps between the diamond
	// and the enclosing square.
	if (v.z < 0.0) {
		octahedral = fold(octahedral);
	}

	// Finally, scale to the 0 to 1 range.
	return octahedral * 0.5 + 0.5;
}

// Given the octahedral encoding of a unit vector with each component in the 0
// to 1 range, returns a vector codirectional to that unit vector.
//
// If you desire the same unit vector, use normalize() on the result.
vec3 DecodeCodirectionalVector(vec2 octahedral) {
	// Scale to the -1 to 1 range
	octahedral = octahedral * 2.0 - 1.0;

	// Reconstruct the Z value using the 1-norm. Conveniently, our fold function
	// gives the same Z value but negative if we are outside the inner diamond.
	float z = 1.0 - abs(octahedral.x) - abs(octahedral.y);

	// Applying the fold function again reverses it.
	if (z < 0.0) {
		octahedral = fold(octahedral);
	}

	// We now have a vector normalized at the 1-norm.
	// The caller calls normalize to normalize it with the 2-norm.
	return vec3(octahedral, z);
}

// "Building an Orthonormal Basis, Revisited"
// https://jcgt.org/published/0006/01/01/
//
// The signZ should be 1.0 if normal.z is positive, and -1.0 if it is negative.
// For values very close to zero the caller is mostly free to select 1.0 or -1.0
// arbitrarily, but it must select a consistent result after accounting for
// rounding and any encoding.
mat2x3 OrthonormalBasisOf(vec3 normal, float signZ) {
	float sign = signZ;
	float a = -1.0 / (sign + normal.z);
	float b = normal.x * normal.y * a;

	return mat2x3(
		vec3(1.0 + sign * normal.x * normal.x * a, sign * b, -sign * normal.x),
		vec3(b, sign + normal.y * normal.y * a, -normal.y)
	);
}

// We encode 2D unit vectors using "diamond encoding", an analog of octahedral
// encoding described in the following blog post:
//
// www.jeremyong.com/graphics/2023/01/09/tangent-spaces-and-diamond-encoding
//
// While we could use transcendental functions to store it as an angle, those
// functions are more costly than diamond encoding.
float EncodeUnitVector(vec2 v) {
	// Project to the unit diamond (1-norm)
	float x = v.x / (abs(v.x) + abs(v.y));

	// Contract the x coordinate by a factor of 4 to represent all 4 quadrants
	// in the unit range and remap.
	//
	// * 0° to 90° are mapped between 0.0 and 0.25
	// * 90° to 180° are mapped between 0.25 and 0.5
	// * 180° to 270° are mapped between 0.5 and 0.75
	// * 270° to 360° (0°) are mapped between 0.75 and 1.0 (0.0)
	//
	// Importantly, the mapping is continuous like an angle.
	float quarter = v.y >= 0.0 ? -0.25 : 0.25;

	// Written explicitly like a fused multiply-add
	return x * quarter + (0.5 - quarter);
}

// Given the diamond encoding of a unit vector with each component in the 0
// to 1 range, returns a vector codirectional to that unit vector.
//
// If you desire the same unit vector, use normalize() on the result.
vec2 DecodeCodirectionalVector(float diamond) {
	// To decode the above mapping, we have two cases.
	//
	// When diamond <= 0.5 (y >= 0):
	//
	// x = 4 * diamond - 1
	// y = 1 - |x|
	//
	// When diamond > 0.5 (y < 0):
	//
	// x = 3 - 4 * diamond
	// y = -(1 - |x|)
	//
	// The below is a branchless translation of this piecewise function.
	float sign = diamond >= 0.5 ? 1.0 : -1.0;
	float x = (-4.0 * sign) * diamond + (2.0 * sign + 1.0);

	// We now have a vector normalized at the 1-norm.
	// The caller calls normalize to normalize it with the 2-norm.
	return vec2(
		x,
		sign * (1.0 - abs(x))
	);
}

// Whether to encode and decode a full TBN matrix from vertex to fragment
//#define TBN_MATRIX

// Bits used for each of the two fixed-point encoded octahedral coordinates
const uint OCT_BITS = 9u;

// Bits used for the single diamond-encoded tangent vector
const uint TANGENT_BITS = 9u;
const uint TANGENT_SHIFT = 4u + OCT_BITS + OCT_BITS;

uint EncodePerFace(
	vec3 worldNormal,
	vec3 worldTangent,
	bool handedness,
	uint materialID
) {
	// Pack the floating point normal using fixed-point octahedral encoding
	vec2 worldNormalOct = EncodeUnitVector(worldNormal);
	uint octFixedX = uint(worldNormalOct.x * float((1u << OCT_BITS) - 1u));
	uint octFixedY = uint(worldNormalOct.y * float((1u << OCT_BITS) - 1u));
	uint normalBits = (octFixedX << (OCT_BITS + 4u)) | (octFixedY << 4u);

	// Truncate the material ID if needed
	uint materialBits = materialID & 0xFu;

#ifdef TBN_MATRIX
	// Encode the tangent and bitangent. The bitangent can be reconstructed from
	// the normal and tangent using the handedness boolean.
	uint handednessBits = uint(handedness) << 31u;

	// To encode the tangent vector, we first identify two basis unit vectors
	// that form an orthogonal basis when combined with the normal vector.
	//
	// The function that derives the basis vectors relies on splitting the unit
	// sphere into two hemispheres, but it's important that we get the same
	// hemisphere decision on both the encode and decode path. Specifically, we
	// select a hemisphere based on the sign of the Z component of the normal.
	//
	// Since we round after converting to octahedral encoding, to predict what
	// hemisphere the decoder would select, we need to decode the Z value to
	// determine its sign. We can skip normalizing, and this lets the optimizer
	// remove the rest of the decode calls not needed to derive the Z value.
	//
	// Without this roundtrip, the derived basis vectors during decoding would
	// be inconsistent with what this encoding function selected.
	float basisSign = DecodeCodirectionalVector(vec2(
		float(octFixedX) * (1.0 / float((1u << OCT_BITS) - 1u)),
		float(octFixedY) * (1.0 / float((1u << OCT_BITS) - 1u))
	)).z >= 0.0 ? 1.0 : -1.0;

	mat2x3 basis = OrthonormalBasisOf(worldNormal, basisSign);

	// Since the tangent vector is inherently orthogonal with the normal vector,
	// and these two basis vectors are both orthogonal with the normal vector,
	// they form a plane that the tangent vector exists within.
	//
	// It follows that we can express the tangent vector as a linear combination
	// of the two basis vectors.
	vec2 plane = normalize(worldTangent) * basis;

	// Further, since the length of the basis vectors are both 1, and the length
	// of the tangent is 1, the length of the 2D vector used to express this
	// linear combination is also 1! We can encode a 2D unit vector into a
	// single value.
	float tangentEncoded = EncodeUnitVector(plane);

	// The encoded vector is continuous like an angle, so we can get a bit of
	// extra precision by wrapping 1.0 around to 0.0. This departs from the
	// octahedral encoding which is not continuous.
	uint tangentFixed = uint(tangentEncoded * float(1u << TANGENT_BITS));
	tangentFixed &= (1u << TANGENT_BITS) - 1u;
	uint tangentBits = tangentFixed << TANGENT_SHIFT;

	normalBits |= handednessBits | tangentBits;
#endif

	return normalBits | materialBits;
}

uint DecodePerFaceMaterialID(uint perFace) {
	return perFace & 0xFu;
}

vec3 DecodePerFaceWorldNormal(uint perFace) {
	uint octFixedX = ((1u << OCT_BITS) - 1u) & (perFace >> (4u + OCT_BITS));
	uint octFixedY = ((1u << OCT_BITS) - 1u) & (perFace >> 4u);

	return normalize(DecodeCodirectionalVector(vec2(
		float(octFixedX) * (1.0 / float((1u << OCT_BITS) - 1u)),
		float(octFixedY) * (1.0 / float((1u << OCT_BITS) - 1u))
	)));
}

mat3 DecodePerFaceWorldTBN(uint perFace, vec3 worldNormal) {
#ifndef TBN_MATRIX
	// Default for upwards facing normal
	return mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, 0.0, 1.0),
		worldNormal
	);
#else
	const float fromTangentFixed = 1.0 / float(1u << TANGENT_BITS);

	// Determine the basis vectors the tangent was expressed with
	float basisSign = worldNormal.z >= 0.0 ? 1.0 : -1.0;
	mat2x3 basis = OrthonormalBasisOf(worldNormal, basisSign);

	// Unpack the diamond-encoded tangent from fixed point
	uint tangentBits = perFace >> TANGENT_SHIFT;
	uint tangentFixed = tangentBits & ((1u << TANGENT_BITS) - 1u);
	float tangentEncoded = float(tangentFixed) * fromTangentFixed;

	// Decode the tangent and bitangent using a linear combination of the
	// octahedral basis unit vectors.
	vec2 plane = normalize(DecodeCodirectionalVector(tangentEncoded));
	vec3 worldTangent = basis * plane;

	// Reconstruct the bitangent using the handedness. We can skip most of the
	// typical cross product math, since we already have these basis vectors.
	float handedness = (perFace >> 31u) > 0u ? 1.0 : -1.0;
	vec3 worldBitangent = basis * vec2(plane.y, -plane.x) * handedness;

	return mat3(worldTangent, worldBitangent, worldNormal);
#endif
}
