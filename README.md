# Steadfast for Minecraft: Java Edition

Steadfast is a remarkably fast and unobtrusive shader pack with exceptional
attention-to-detail. Easy on the eyes and on your computer, Steadfast massively
improves the graphical quality and realism of Minecraft without getting in the
way of actually playing the game.

Steadfast is free and open-source software developed by coderbot, and can be downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth), https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and distribute it under the terms of the GNU General Public License, version 3.

## How fast is it really?

Steadfast runs great even on midrange laptops from 5+ years ago, with the
default High profile delivering a smooth 60+ FPS experience on most computers
capable of running Minecraft. On computers with a dedicated high-end graphics
card, Steadfast flies and even the High profile can reliably reach 250-500 FPS.
With a lower profile, it runs playably even on a Raspberry Pi!

Steadfast is designed for mobile / integrated graphics hardware, and is built to
require minimal graphics memory bandwidth and only moderate graphical compute
power.

## Features

* Semi-realistic atmosphere with high-quality sky and fog
* Real-time shadows cast by the sun and moon
* Foliage that waves with the wind and has subsurface light scattering
* Perfectly-tuned lighting to give the illusion of bright sunlight and darker
  nights and interiors, but without excessive changes in brightness or contrast,
  or obtrusive effects like auto-exposure
* Approximate light shafts ("godrays") from the sun and moon
* Exceptionally detailed water waves with actual visual depth, reflection,
  refraction, and realistic absorption based on water depth
* Water and ice can reflect anything visible on the screen
* Sunlight and moonlight cast bright water caustics on underwater surfaces
* Windswept high-altitude cirrus clouds as well as support for Minecraft's
  standard blocky clouds
* Ambient occlusion through Minecraft's built-in smooth lighting
* Integration with the Distant Horizons and Voxy mods, which offer extreme
  render distances without significant performance loss
* Wide compatibility with other mods and modpacks, including support for
  high-performance rendering pathways in mods like Create (through the
  Colorwheel add-on mod)

## Platform compatibility

Steadfast supports the following hardware and underlying platforms:

* NVIDIA, AMD, and Intel GPUs
* macOS, including Apple Silicon
* Linux, including most hardware supported through the open-source Mesa graphics
  drivers, such as the Raspberry Pi and the Steam Deck.
* Minecraft 1.18.2 and above using the Iris shader mod (Iris 1.5 or newer).
* Minecraft 1.7.10 using the Angelica shader mod

## Current limitations

Steadfast has some notable limitations that I hope to resolve in the future:

* Steadfast does not currently support any version of OptiFine.
	* Steadfast offloads a ton of calculations to the CPU, but the feature used
	to do this ("custom uniforms") works a bit differently in OptiFine compared
	to Iris and porting will take a lot of effort as a result.
* Steadfast lacks support for any dimension other than the Overworld, which
  includes a lack of any well-tuned support for the Nether and End.
	* To support another dimension basically requires making a new visual style
	  for the shader. This can take months of work to get right.
	* The current Nether / End appearance is entirely playable and lacks the
	  same serious bugs you might normally expect from shaders lacking dimension
	  support, but not optimized or tweaked to the same level of quality as the
	  Overworld dimension. In other words, it basically just works on accident.
* Steadfast does not currently support colored lighting.
	* This is really hard to implement in a high-performance and high-quality
	way, but I am looking into it and fortunately there is prior art in the
	community.

## Support policy

* I aim for a high standard of quality in my software, and the goal of the beta
  testing phase is to find and fix any bugs, stylistic issues, and similar
  defects.
* Please try to avoid duplicate bug reports, and use your best judgement when
  trying to find out if a bug is in Steadfast, Iris, Minecraft, another mod, or
  your graphics drivers / system, but if you aren't sure, please feel free to
submit a report.
* We aren't able to help you get Steadfast working properly on phones and mobile
  devices running Android or iOS, even with software like PojavLauncher, due to
  widespread correctness issues and bugs in the graphics drivers and required
  compatibility layers.

## Credits

* Steadfast takes heavy visual inspiration from Sonic Ether's Unbelievable
  Shaders (SEUS), especially SEUS Renewed, as well as some of Chocapic13's
  shaders. SEUS is a great shader pack, and I hope you enjoy this implementation
  of a similar visual style!
* Steadfast would not be possible without the Iris shader loader, in particular
  the continued development & maintenance by IMS212 allows Steadfast to work on
  many Minecraft versions with minimal fuss on the side of Steadfast.
* I would also like to thank my dedicated testers who helped highlight and
  uncover many of the bugs and issues fixed in the development of Steadfast!
