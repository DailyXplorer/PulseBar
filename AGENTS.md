# AGENTS.md

PulseBar is a macOS menu bar app (SwiftUI + AppKit) plus a `PulseBarCore` Swift package
that holds the platform-agnostic-looking logic and its tests. See `README.md` for the full
feature list, build, install, and release instructions.

## Cursor Cloud specific instructions

Cursor Cloud Agent VMs run **Linux (Ubuntu x86_64)**. PulseBar is a **macOS-only** project,
so the application and its test suite **cannot be built, run, or tested inside a Cloud Agent
VM**. This is a hard platform limitation, not a missing-dependency problem — do not spend time
trying to "fix" the environment to build it here.

What this means concretely:

- The app target requires **Xcode 16 / `xcodebuild`** on **macOS 15+**. `xcodebuild` does not
  exist on Linux, so `script/build_and_run.sh`, `script/install_signed_local.sh`, and
  `script/notarize_release.sh` cannot run here. Build/run commands are documented in `README.md`.
- The `PulseBarCore` Swift package looks portable but `Sources/PulseBarCore/ProcessProtection.swift`
  (and `Tests/PulseBarCoreTests/ProcessProtectionTests.swift`) do `import Darwin`, which does not
  exist on Linux. A Swift-for-Linux toolchain compiles standalone Swift fine, but
  `swift build` / `swift test --package-path PulseBarCore` fail with `no such module 'Darwin'`.
  Running the tests therefore also requires macOS.
- CI reflects this: `.github/workflows/build.yml` runs on `runs-on: macos-15`, builds with
  `xcodebuild`, and runs `swift test --package-path PulseBarCore`. Lint/test/build validation
  should be done on a macOS machine or the macOS CI runner, not in a Cloud Agent.

Because nothing in this repo can be built on Linux and there are no external package
dependencies to fetch, there is **no useful dependency-install/update step** for the Cloud Agent
environment. Verify changes on macOS (locally or via the `macos-15` CI job).
