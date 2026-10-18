# portable-pi

Research and tooling for distributing the [pi coding agent](https://github.com/earendil-works/pi)
as a fully offline, self-contained bundle for Linux and Windows targets
(no Node.js, npm, or JS libraries required on the target machine).

## Contents

- **[Offline bundling research](docs/offline-bundling-research.md)** — extensive research (pi v1.3.0):
  what pi is built from, its existing distribution channels, verified target-machine
  requirements (glibc/musl/Windows/CPU), a comparison of all viable bundling strategies
  (official Bun-compiled binaries, self-built `bun build --compile`, vendored Node,
  Node SEA, pkg/yao-pkg, OS-native wrappers), a recommended offline-kit design with
  installer sketches, and open gaps.
