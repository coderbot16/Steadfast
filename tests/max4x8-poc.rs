// Implementation of a component-wise saturating maximum given two sets of
// 8 nibble components where each set is packed into a 32-bit integer.
//
// Cost: 21 operations to process 8 components (2.625 ops/component)
pub fn max4x8(a: u32, b: u32) -> u32 {
	// Find bit differences
	//
	// 1 operation (1x xor)
	let diffs = a ^ b;

	// Make a mask of ones behind each different bit within each component:
	//
	// 1xxx_yyyy -> 0111_0zzz
	// 01xx_yyyy -> 0011_0zzz
	// 001x_yyyy -> 0001_0zzz
	// 0001_yyyy -> 0000_0zzz
	//
	// 8 operations (3x and, 3x shift, 2x or)
	let trailing =
		((diffs >> 1) & 0x7777_7777) |
		((diffs >> 2) & 0x3333_3333) |
		((diffs >> 3) & 0x1111_1111);
	
	// Use that prior mask to extract the most-significant (highest)
	// different bit, then check whether a has it set and b does not,
	// in which case a is greater, or vice-versa.
	//
	// 3 operations (2x and, 1x not)
	let ha = (diffs & !trailing) & a;

	// Expand that single bit to full trailing nibble mask
	//
	// 6 operations (2x or, 2x shift, 2x and)
	let mut m = ha;
	m |= (m >> 1) & 0x7777_7777;
	m |= (m >> 2) & 0x3333_3333;

	// Not using b here, to reduce register pressure
	//
	// 3 operations (1x xor, 1x and, 1x not)
	return a ^ (diffs & !m);
}

fn main() {
	let a: u32 = 0b0000_0001_0010_0011_0100_0101_0110_0111;
	let b: u32 = 0b1000_1001_1010_1011_1100_1101_1110_1111;

	fn case(expected: u32, a: u32, b: u32) {
		let result = max4x8(a, b);

		assert_eq!(expected, result,
			"expected {:#010X} from max4x8({:#010X}, {:#010X}), got {:#010X}",
			expected, a, b, result);
	}

	case(b, a, b);
	case(b, b, a);
	case(b, b, b);
	
	// You can also just give a single nibble
	case(2, 1, 2);
	case(2, 2, 1);

	for x0 in 0..=0xFFu32 {
		for x1 in 0..=0xFFu32 {
			let expected = 
				std::cmp::max(x0 & 0xF0, x1 & 0xF0) |
				std::cmp::max(x0 & 0xF, x1 & 0xF);

			case(expected, x0, x1);
		}
	}
}
