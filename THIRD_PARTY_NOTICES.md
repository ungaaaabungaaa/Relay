# Third-party notices

This curated inventory comes from the checked-in `pnpm-lock.yaml` and
`mac/Package.resolved`. Those files contain the resolved dependency records for
the JavaScript workspace and Mac Swift package.

## Shipped components

| Component | Locked version | License |
| --- | --- | --- |
| `ws` | 8.21.1 | MIT |
| Sparkle | 2.9.2 | MIT with bundled third-party notices |

The Relay bridge uses `ws` for authenticated event and cloud sockets. The Mac
application embeds Sparkle for signed updates. Sparkle's package carries the
copyright and third-party notices for its bundled update components.

## Build and test components

| Component or family | Locked version | License |
| --- | --- | --- |
| TypeScript | 5.9.3 | Apache-2.0 |
| esbuild and platform packages | 0.28.1 | MIT |
| postject | 1.0.0-alpha.6 | MIT |
| Vitest | 3.2.7 | MIT |
| Vite | 7.3.6 | MIT |
| Rollup and platform packages | 4.62.2 | MIT |
| `@types/node` | 24.13.3 | MIT |
| `@types/ws` | 8.18.1 | MIT |

The JavaScript lockfile also resolves small support packages used by build and
test tools. This group includes Chai, cac, debug, deep-eql, magic-string,
nanoid, picocolors, picomatch, postcss, source-map-js, tinybench, tinypool,
tinyspy, and their declared helpers.

Relay uses Apple system frameworks such as SwiftUI, Foundation, Security, and
CryptoKit. The license identifiers above summarize the checked-in dependency
records. Each dependency's source package supplies its authoritative license
text and copyright notices.
