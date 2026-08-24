# Iris agent-browser controller provenance

Iris keeps the npm package metadata and JavaScript layer pinned to
`agent-browser` 0.33.2, but replaces only its Windows x64 native controller.
The npm 0.33.2 controller races while installing allowed-domain controls on a
fresh Chrome target and can fail with `Cannot find default execution context`.

The replacement is built from the official
[`vercel-labs/agent-browser`](https://github.com/vercel-labs/agent-browser)
pull-request head below, plus the checked-in Iris patch:

- upstream issue: `#1651`
- upstream pull request: `#1655`
- upstream PR head: `c21c9b741a1eb23218c2bc9d165dc9c0af718604`
- upstream PR parent: `acbc22bdc5d4f6c5a88d97d4a4745d3c5eb0591f`
- local patch: `iris-default-context-race.patch`
- target: `x86_64-pc-windows-msvc`
- build: `cargo build --release --locked --manifest-path cli/Cargo.toml`

The local patch retries only the exact missing-default-context startup error.
It permits a still-missing current context only for an empty or `about:blank`
startup page after Fetch interception and the new-document guard have already
been installed. Loaded pages, frames, workers, all other CDP errors, and every
disallowed top-level navigation still fail closed.

`provenance.json` binds the upstream commit, local patch, compact vendor
archive, expanded executable, and tested Chrome-for-Testing version by SHA-256.
Provisioning verifies every binding before replacing the npm Windows
controller. The vendor archive itself is not copied into a release; packaging
ships only the expanded replacement executable.
