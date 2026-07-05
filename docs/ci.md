# Continuous Integration & Review Notes

`.github/workflows/ci.yml` runs on every PR (and pushes to `main`). The five jobs have no `needs:` dependency, so they run in parallel:

- **SwiftLint** — `swiftlint lint` against `.swiftlint.yml` (non-strict: style issues are warnings/annotations; only error-severity rules fail). Observed runtime: **~10–20s**.
- **BadmintonCore Tests** — `swift test --package-path BadmintonCore --enable-code-coverage` on macOS (no simulator). All core unit tests live here; runs in well under a minute. A follow-up step runs `xcrun llvm-cov report` against the resulting `.profdata` and prints a per-file coverage table straight into the job log (no external coverage service).
- **Localization Sync** — extracts the key set from each of the 6 `.lproj/Localizable.strings` files and fails, naming the missing locale/key, if any locale's keys don't match the union. Pure bash/grep, no Xcode toolchain needed. Runtime: seconds.
- **Watch App Build** — `xcodebuild build-for-testing` of the Watch App scheme against `generic/platform=watchOS Simulator` (no concrete simulator device needed — runner images don't reliably ship watchOS simulators). Compiles the app **and both test bundles** without executing them, so it's the integration gate for project-file, linking, and app-code errors, and app-layer test code can't silently rot. Observed runtime: **~1.5–4 min** — this is the long pole. Note: app-target tests are compiled but not *run* in CI (running needs a concrete simulator); core logic that needs behavioral verification belongs in the package where `swift test` runs it.
- **Complication Build** — `xcodebuild build` of the `badminton score tracker ComplicationExtension` scheme (shared scheme checked into `xcshareddata/xcschemes/`) against the same generic watchOS Simulator destination. Uses plain `build`, not `build-for-testing` — the WidgetKit extension has no test target. Catches breakage in `BadmintonComplication.swift` that the Watch App Build job doesn't compile.

All targets' `WATCHOS_DEPLOYMENT_TARGET` are aligned at **11.4** (the Complication extension previously drifted to 26.5 with no `@available` usage requiring it — an unaligned Xcode-template default, not an intentional API dependency).

A PR is checkable within **~4 minutes** of pushing. If you're polling/scheduling a check-in on a PR (e.g. an agent session without webhook access to CI success events), don't default to a long cadence like 20 minutes — check back in ~3–5 minutes first, and only back off if the run is still in progress.

## Local checks before pushing

- `swiftlint` (install via `brew install swiftlint`) — fix or intentionally silence findings rather than letting warnings accumulate.
- `swift test --package-path BadmintonCore` — seconds on any Mac.
- When possible, also build locally (`xcodebuild build`) before pushing SwiftUI changes: CI's watchOS build is the safety net, but it's a slow feedback loop, and a local compile catches type-check timeouts and errors in seconds.

## Reviewing risky changes

CI (lint + unit tests) proves the code compiles and the logic it covers is correct — it does not catch architectural/interaction bugs. The worst bug found in this codebase so far wasn't in any single PR: it was two independently-correct changes to `CloudSyncManager`/`AppStore` (the id-based history merge and the clear-history feature) combining to silently undo "Clear History." CI was green on both. For anything beyond mechanical changes (docs, string localization, dead-code removal):

- Use plan mode before implementing, especially anything touching `CloudSyncManager`/`AppStore` — that's where both real bugs in this codebase have lived. A wrong plan costs one sentence to fix; a wrong diff already cost the rewrite.
- Run a `/code-review` pass before merging non-trivial PRs. CI-green is evidence the mechanics work, not that the change is correct.
- **CloudKit sync (`CloudKitSyncManager`, #109) is not CI-provable.** CI only confirms the CloudKit code compiles/links; actual sync, deletion propagation, migration, offline queue, and conflict handling need a real two-device iCloud test (a provisioned CloudKit container + two watches on one Apple ID). The code ships inert behind `cloudKitSyncEnabled` (default off) precisely so it can't affect anyone until that test passes and the flag is flipped on.
