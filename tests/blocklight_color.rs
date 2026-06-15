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

fn write_color(label: String, mut r: f64, mut g: f64, mut b: f64) {
	// Rec709 luminance: https://en.wikipedia.org/wiki/Relative_luminance
	let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
	r /= lum;
	g /= lum;
	b /= lum;

	// Once blue and green start to go to zero, luminance stops accurately
	// predicting the brightness and starts just multiplying red by 5. This
	// caps out how bright the reds can be so their brightness does not get
	// blown out.
	let max = r.max(g.max(b));

	if max > 2.5 {
		let adjust = max / 2.5;
		r /= adjust;
		g /= adjust;
		b /= adjust;
	}

	println!("const vec3 {} = vec3({:.3}, {:.3}, {:.3});", label, r, g, b);
}

fn main() {
	let default_temperature = 3000;
	let mut temperatures: Vec<u32> = (250u32..=7500u32).step_by(250).collect();
	temperatures.extend((8000u32..=12000u32).step_by(1000));

	for &k in &temperatures {
		let r = radiance(k as f64, RED);
		let g = radiance(k as f64, GREEN);
		let b = radiance(k as f64, BLUE);

		write_color(format!("BLACKBODY_{}K", k), r, g, b);
	}

	let mut options: Vec<String> = temperatures.iter()
		.map(|k| format!("BLACKBODY_{}K", k))
		.collect();

	write_color("LIGHT_MAGIC".to_owned(), 0.6, 0.1, 1.0);
	options.push("LIGHT_MAGIC".to_owned());

	for channel in ["LIGHT_CUSTOM_R", "LIGHT_CUSTOM_G", "LIGHT_CUSTOM_B"] {
		let values: Vec<String> = (0..=250)
			.map(|v| format!("{:.2}", (v as f64) / 100.0))
			.collect();
		println!("#define {} 1.00 // [{}]", channel, values.join(" "));
	}

	println!("const vec3 LIGHT_CUSTOM = vec3(
		LIGHT_CUSTOM_R,
		LIGHT_CUSTOM_G,
		LIGHT_CUSTOM_B);");
	options.push("LIGHT_CUSTOM".to_owned());

	let default = format!("BLACKBODY_{}K", default_temperature);

	println!("#define BLOCKLIGHT_COLOR {} // [{}]", default, options.join(" "));
}
