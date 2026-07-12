# PlasmaDemo — AI Agent Guidelines

## Project overview

PlasmaDemo is a classic **demoscene** app for macOS written in **Swift + Metal**
(SwiftPM executable, macOS 13+). It renders five parts, switched with `Space`
via unique demoscene transitions (melting, iris, raster tear, bit-crush,
and dither); each part features a buildup animation and an artful outro:

1. sine-sum plasma + Amiga-style copper bars + bouncing rainbow scroller
2. tunnel (polar-mapped checkerboard) + unique scroller
3. C64-style raster bars with their own static scroller band
4. 3D flying starfield + rotating Rubik's-style cube + "struggling train" scroller
5. unlimited bobs (procedural spheres) + C64-style bottom band scroller

There are **no assets** and **no `.metal` build step** — all shader source
lives in a Swift string and is compiled at runtime.

## Repository layout

| Path | Purpose |
|---|---|
| `Package.swift` | SwiftPM manifest (single executable target) |
| `Sources/PlasmaDemo/main.swift` | AppKit window, `MTKView` setup, keyboard handling, `--selftest` entry |
| `Sources/PlasmaDemo/Renderer.swift` | Metal device/pipeline, per-frame uniforms, CoreText scrolltext texture, part/fade state |
| `Sources/PlasmaDemo/Shaders.swift` | One big Metal source string: fullscreen-triangle vertex shader + fragment shaders for all effects |
| `README.md` | User-facing docs — keep the feature list in sync with code changes |

## Build, run, verify

```sh
swift build            # must compile with no errors (warnings are OK to fix, not ignore)
swift run              # opens the demo window (Space = next part, Esc/Cmd+Q = quit)
swift run PlasmaDemo --selftest   # headless check; must print "selftest OK ..."
```

Releases are handled by GitHub Actions (`.github/workflows/release.yml`) which builds a universal binary (arm64 + x86_64) and packages it as a ZIP and DMG.

After **any** change, always run `swift build` and the `--selftest` — it
verifies that the runtime-compiled Metal shaders still compile, the pipeline
builds and the scrolltext texture is generated. There is no other test suite.
Visual output cannot be verified headlessly; mention this in your report and
suggest `swift run` for the user to confirm looks.

## Conventions

- Keep the project **self-contained**: no external dependencies, no asset
  files, no `.metal` files — shaders stay as Swift strings in `Shaders.swift`.
- Effects are computed in the **fragment shader** where possible; Swift code
  only feeds uniforms (time, resolution, part index, fade) and textures.
- Tunable effect constants (wave frequency/speed/amplitude, bounce, colors)
  live as literals in the shader with a short comment — follow that style and
  mention relevant tunables in your summary when you add new ones.
- Match the existing comment style: brief `//` comments explaining intent,
  section banners like `// MARK: -` in Swift files.
- New demo parts follow the existing pattern: add a fragment path selected by
  the part uniform, wire keyboard/fade handling in `Renderer.swift`, update
  the README feature list and controls.

## Git

- `.build/` is git-ignored; never stage build artifacts.
- Do **not** commit unless explicitly asked. When asked, use concise,
  imperative commit messages like the existing history and add the co-author
  trailer required by the global guidelines.
