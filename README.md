# PlasmaDemo

A classic demoscene **plasma** effect with a **bouncing rainbow scroller** on top,
written in Swift + Metal for macOS.

## Features

- Five demo **parts**, switched with `Space` via **unique demoscene transitions**;
  each part features a **buildup animation** when it starts and an
  **artful outro** when it exits:
  1. plasma + copper bars — organic "melting" transition; copper bars grow/shrink in height and plasma fades in/out
  2. a classic **tunnel** — radial "iris" wipe transition; tunnel grows/implodes from/to the center
  3. Commodore 64-style **raster bars** — horizontal "raster tear" wipe; bars grow/shrink vertically;
     includes their own scroller: a static black band framed by two white lines,
     warm-white Silom glyphs, no bounce, no wave, no rainbow
  4. a classic **starfield** with a **rotating 3D cube** — "bit-crush" resolution downsample;
     stars fade in/out and the cube scales up/down
  5. **unlimited bobs** — 4x4 dithered dissolve; thousands of colorful spheres moving in a
     snake pattern; the number of bobs grows/shortens quickly; 
     spheres stay above the static band scroller at the bottom
- All scrollers now feature entrance and exit animations (fade, band growth,
  or sinking off-screen) and start fresh from the beginning of the text when
  the part is selected.
- Old-school sine-sum plasma computed entirely in a Metal fragment shader
- Amiga-style **copper bars** — six metallic bars with specular cores,
  sweeping up and down on phase-shifted sine paths, layered between the
  plasma and the scroller
- Scrolltext rendered with CoreText into a texture, then warped in the shader
  (parts 1, 2 & 4):
  - unique message for each part
  - horizontal wrap-around scrolling
  - animated per-column sine wave — characters ride up and down the wave as they scroll
  - big vertical bounce (`abs(sin)`)
  - tunnel scroller (part 2) has a slower, calmer sine/bounce animation
  - cube scroller (part 4) moves at the bottom with a variable "struggling train"
    speed and no vertical animation
  - rainbow color cycling and a drop shadow
- C64-style static scroller band framed by two white lines (parts 3 & 5):
  - part 3 is in the middle, part 5 is at the bottom
  - no bounce, no wave, no rainbow color cycling
  - warm white (part 3) or light blue (part 5) glyphs on a black band
- No assets, no `.metal` build step — shaders are compiled at runtime

## Build & run

You can download a pre-compiled **universal binary** (supporting both Intel and Apple Silicon Macs) from the [Releases](https://github.com/Grrrolf/PlasmaDemo/releases) page. This allows you to run the demo on a vanilla macOS 13+ install without needing Xcode or Swift installed.

To build from source:

```sh
swift build -c release
.build/release/PlasmaDemo
```

Or during development:

```sh
swift run
```

## Controls

- `Space` — fade out and start the next part
- `Esc` or `Cmd+Q` — quit
- The window is resizable; the effect adapts to any size

## Self-test

A headless check that the Metal pipeline and the scrolltext texture build
correctly (no window is opened):

```sh
swift run PlasmaDemo --selftest
```

## Credits
- Coded by **Junie** (powered by Gemini 3 Flash Preview) and **Fable 5**.
- "Fable 5" and "Junie" are AI agents collaborating on this project.
