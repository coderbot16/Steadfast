// Units: J / K
const BOLTZMANN: f64 = 1.380_649e-23;

// Units: J * s
const PLANCKS: f64 = 6.626_070e-34;

// Units: m / s
const C: f64 = 299_792_458.0;

// Spectral radiance per unit wavelength
// https://en.wikipedia.org/wiki/Planck%27s_law
//
// Input units: Kelvin, meters
// Output units: W / (m^3 * sr)
fn radiance(kelvin: f64, wavelength: f64) -> f64 {
	let l = (2.0 * PLANCKS * C * C) / wavelength.powi(5);
	let r = (PLANCKS * C / (wavelength * BOLTZMANN * kelvin)).exp() - 1.0;

	return l / r;
}

// Rec709 / sRGB primaries used in shaderLABS
const RED:   f64 = 660e-9;
const GREEN: f64 = 550e-9;
const BLUE:  f64 = 440e-9;

fn main() {
	let default_temperature = 2000;
	let temperatures: Vec<u32> = (1750u32..=7500u32).step_by(250).collect();

	for &k in &temperatures {
		let mut r = radiance(k as f64, RED);
		let mut g = radiance(k as f64, GREEN);
		let mut b = radiance(k as f64, BLUE);

		// Rec709 luminance: https://en.wikipedia.org/wiki/Relative_luminance
		let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
		r /= lum;
		g /= lum;
		b /= lum;

		println!("const vec3 BLACKBODY_{}K = vec3({:.3}, {:.3}, {:.3});", k, r, g, b);
	}

	let ti: Vec<String> = temperatures.iter().map(|k| format!("BLACKBODY_{}K", k)).collect();

	print!("#define BLOCKLIGHT_COLOR BLACKBODY_{}K // [{}]", default_temperature, ti.join(" "));
}
