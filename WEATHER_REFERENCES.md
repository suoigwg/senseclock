# Current Visual Style

Version 1.4.1 changed the weather visuals to a photorealistic style at the user's request. Bundled transparent cloud and moon images generated with the built-in image generation tool replaced the earlier geometric icons. Assets and prompts are listed in [Assets/Weather/PROMPTS.md](Assets/Weather/PROMPTS.md).

The current animation uses subdued lighting, slow cloud movement, light rain, layered snowfall, and brief localized lightning. Decorative auroras and cartoon sun rays have been removed. The CSS works below are research notes for the 1.3 design; none of their code or images was copied into this project.

# Weather Animation References and Implementation Notes

The design research reviewed these publicly available web animations:

- Fabrizio Bianchi — [Pure CSS One Div Weather Animated Icons](https://codepen.io/_fbrz/pen/ExbeQQ): layered shadows that form clouds, independent floating cycles, rotating sunlight, staggered rain and snow, and lightning keyframes.
- Dayton Johnson — [Weather – Pure CSS Animated Icons](https://codepen.io/idifyable/pen/gmPjQK): cloud occlusion, day and night motifs, gradients and inset shadows, varied precipitation speeds, and visual distinctions between weather states.
- mantoufan — [yZhanWeather](https://github.com/mantoufan/yZhanWeather): background particles moving in layers with different delays and speeds.

This project draws on layered composition and animation timing and implements its effects independently in Swift and Core Graphics. It does not copy source code, images, or fonts from those projects, and the screen saver does not load CodePen or other web pages remotely.

## Visual Changes in Version 1.3

- Enlarged the main weather icon and combined geometric cloud shapes with highlights, shadows, cool ambient light, and foreground and background layers.
- Added varied sun rays, warm volumetric beams, and floating dust motes for clear weather. Partly cloudy weather places two cloud layers with different motion cycles in front of the sun.
- Added three layers of cool blue rain at different speeds, foreground raindrops with lit trails, and expanding water ripples.
- Distinguished distant snow particles, foreground bokeh, and rotating hexagonal snow crystals.
- Added branching lightning with a bright core, cloud illumination, and staggered afterglow. Flashes stayed within the weather area instead of filling the screen with white.
- Built fog from overlapping gradient clouds to replace the older hard-edged horizontal bars.
- Added a moon with shading and crater detail, cross-shaped stars, fading meteor trails, and a dim aurora at night.

Background animation is drawn behind the clock cards; only the central weather icon appears in front of them. The weather toggle, animation toggle, and system Reduce Motion setting remain available. The update, cache, and demo status line at the bottom of the main view remains removed.
