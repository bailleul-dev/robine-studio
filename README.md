# Robine Amp

Robine Amp is a Zig project for semantically described musical equipment,
interactive equipment rendering, and shared desktop, CLAP, and VST3 audio hosts.

The first executable is a macOS Metal wireframe of a small rig. Pedals, controls,
connections, amplifier, cabinet, speakers, and microphone are described by the
model; the UI projection derives their render coordinates.

## Requirements

- macOS 13 or later
- Zig 0.16.x

## Run Robine Studio

```sh
zig build run-studio
```

The build creates `zig-out/Robine Studio.app`.

## Verify

```sh
zig build test
zig build
```

To enumerate Core Audio devices, negotiate the default output, and exercise its
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
