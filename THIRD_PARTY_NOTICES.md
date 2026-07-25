# Third-party notices

This inventory is derived from `pnpm-lock.yaml`, `gradle/libs.versions.toml`,
and `mac/Package.resolved` for the checked-in release source. Those files and
the Gradle release output record the resolved dependency graph.

## Shipped components

| Component | Version | License |
| --- | --- | --- |
| `ws` | 8.21.1 | MIT |
| AndroidX Activity Compose | 1.12.4 | Apache-2.0 |
| AndroidX Compose | BOM 2026.06.00 | Apache-2.0 |
| AndroidX Core | 1.18.0 | Apache-2.0 |
| AndroidX Lifecycle | 2.10.0 | Apache-2.0 |
| AndroidX Wear Compose | 1.6.2 | Apache-2.0 |
| AndroidX Wear Ongoing Activity | 1.1.0 | Apache-2.0 |
| AndroidX WorkManager | 2.11.2 | Apache-2.0 |
| Kotlin coroutines | 1.10.2 | Apache-2.0 |
| OkHttp | 5.1.0 | Apache-2.0 |
| Sparkle | 2.9.2 | MIT with bundled third-party notices |

## Build and test components

| Component or family | Locked version | License |
| --- | --- | --- |
| TypeScript | 5.9.3 | Apache-2.0 |
| esbuild and platform packages | 0.28.1 | MIT |
| postject | 1.0.0-alpha.6 | MIT |
| Vitest | 3.2.7 | MIT |
| Vite | 7.3.6 | MIT |
| Rollup and platform packages | 4.62.2 | MIT |
| JUnit | 4.13.2 | EPL-1.0 |
| AndroidX Test JUnit | 1.3.0 | Apache-2.0 |
| `@types/node` | 24.13.3 | MIT |
| `@types/ws` | 8.18.1 | MIT |

The Node lock also resolves small MIT-licensed support packages used only by
the build and test tools, including Chai, cac, debug, deep-eql, magic-string,
nanoid, picocolors, picomatch, postcss, source-map-js, tinybench, tinypool,
tinyspy, and their declared helpers.

The Relay Mac application embeds Sparkle 2.9.2 for signed updates and also uses
Apple system frameworks including SwiftUI, Foundation, Security, and
CryptoKit. Sparkle's source package carries the copyright and third-party
notices that apply to its bundled update components.

License identifiers above are informational summaries. The authoritative
license text and copyright notices are shipped by each dependency in its
source package.
