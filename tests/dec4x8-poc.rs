// Implementation of a component-wise saturating decrement of 8 nibble
// components packed into a 32-bit integer.
//
// Subtracts 1 from each component unless the component is already zero.
//
// Cost: 6 operations to process 8 components (0.75 ops/component)
pub fn dec4x8(input: u32) -> u32 {
	// First, check if any bit is set in each component by OR-ing each bit
	// of every component together into the first bit of that component.
	let mut merge = input; // result: 0b0110_0100_1000_0000
	merge |= merge >> 2;   // result: 0b0111_1101_1010_0000
	merge |= merge >> 1;   // result: 0b0111_1111_1111_0000

	// Then, subtract only that first bit of each component, which will
	// decrement nonzero components, but have no effect on zero components
	// as it will subtract zero from zero.
	let dec = merge & 0x1111_1111;  // result: 0b0001_0001_0001_0000
	return input - dec;             // result: 0b0101_0011_0111_0000
}

fn main() {
	assert_eq!(
		dec4x8(0b0000_0001_0010_0011_0100_0101_0110_0111),
		0b0000_0000_0001_0010_0011_0100_0101_0110);

	assert_eq!(
		dec4x8(0b1000_1001_1010_1011_1100_1101_1110_1111),
		0b0111_1000_1001_1010_1011_1100_1101_1110);
}
