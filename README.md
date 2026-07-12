# PlasmaDemo

A classic demoscene **plasma** effect with a **bouncing rainbow scroller** on top,
written in Swift + Metal for macOS.

## Features

- Five demo **parts**, switched with `Space` via a fade-to-black transition:
  1. plasma + copper bars
  2. a classic **tunnel** — polar-mapped checkerboard flying towards the
     viewer, with a wandering center, slow twist and depth-cycled colors
  3. Commodore 64-style **raster bars** — eight full-width, step-shaded bars
     sweeping over a black screen, with their own scroller: a static black
     band framed by two white lines, warm-white Silom
     glyphs, no bounce, no wave, no rainbow
  4. a classic **starfield** with a **rotating 3D cube** — 3D "flying" starfield
     and a raymarched cube with distinct Rubik's-style colors and 3x3 stickers
  5. **unlimited bobs** — thousands of colorful, C64-style spheres moving in a
     snake pattern, a traditional demoscene blitter test; the number of bobs
     grows quickly until the screen is full; spheres stay above the
     static band scroller at the bottom (similar to part 3)
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
