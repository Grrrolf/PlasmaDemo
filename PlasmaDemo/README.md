# PlasmaDemo

A classic demoscene **plasma** effect with a **bouncing rainbow scroller** on top,
written in Swift + Metal for macOS.

## Features

- Old-school sine-sum plasma computed entirely in a Metal fragment shader
- Amiga-style **copper bars** — six metallic bars with specular cores,
  sweeping up and down on phase-shifted sine paths, layered between the
  plasma and the scroller
- Scrolltext rendered with CoreText into a texture, then warped in the shader:
  - horizontal wrap-around scrolling
  - animated per-column sine wave — characters ride up and down the wave as they scroll
  - big vertical bounce (`abs(sin)`)
  - rainbow color cycling and a drop shadow
- No assets, no `.metal` build step — shaders are compiled at runtime

## Build & run

```sh
cd PlasmaDemo
swift build -c release
.build/release/PlasmaDemo
```

Or during development:

```sh
swift run
```

## Controls

- `Esc` or `Cmd+Q` — quit
- The window is resizable; the effect adapts to any size

## Self-test

A headless check that the Metal pipeline and the scrolltext texture build
correctly (no window is opened):

```sh
swift run PlasmaDemo --selftest
```
