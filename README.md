# Robine Amp

Robine Amp is a Zig project for semantically described musical equipment,
interactive equipment rendering, and shared desktop, CLAP, and VST3 audio hosts.

The first executable is a native desktop renderer of a small rig (Metal on
macOS, OpenGL/X11 on Linux). Pedals, controls, connections, amplifier, cabinet,
speakers, and microphone are described by the model; the UI projection derives
their render coordinates.

## Requirements

- macOS 13 or later, or Linux with X11/XWayland, OpenGL, and ALSA
- Zig 0.16.x

On Debian/Ubuntu, the Linux build headers are provided by `libx11-dev`,
`libgl-dev`, and `libpng-dev`; ALSA is loaded at runtime through `libasound2`.

## Run Robine Studio

```sh
zig build run-studio
```

On macOS the build creates `zig-out/Robine Studio.app`. On Linux it creates
`zig-out/bin/robine-studio`.

## Verify

```sh
zig build test -Doptimize=ReleaseSafe
zig build
```

To enumerate native audio devices, negotiate the default output, and exercise its
real-time callback silently:

```sh
make audio-probe
```

The first standalone audio slice accepts one synchronous duplex device. Separate
input and output devices require the later clock-drift bridge; they are never
treated as synchronous merely because their nominal sample rates match.

Project specifications are indexed in [`docs/specs/README.md`](docs/specs/README.md).

## Web service

The Next.js landing page and PostgreSQL-backed user accounts live in [`web`](web/README.md).
