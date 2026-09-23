# Animosis Patcher

Tauri v2 — Rust backend, HTML/CSS/JS shell. Windows first; all filesystem and
path handling stays platform-neutral so Linux and macOS are later build
targets rather than a rewrite.

## See the UI right now

No toolchain needed. The shell detects that `window.__TAURI__` is absent and
drives itself from `MockTransport`, replaying a realistic update using the
sizes from `schema/examples/stable-0.5.0.json`:

```sh
start ui/index.html          # Windows
```

It runs the full sequence — check → available → downloading with live
throughput and ETA → applying → done. The buttons work: **Check again**
restarts it, **Cancel** aborts mid-download, **Install** runs it through.

Fonts fall back to Segoe UI until the bundled `.woff2` files land (see below);
everything else is final.

## Build (needs Rust)

Not installed on this machine yet:

```sh
winget install Rustlang.Rustup
cargo install tauri-cli --version "^2"
cd src-tauri && cargo tauri dev
```

## Layout

```
ui/                 shell — runs standalone in a browser
  index.html        state-driven markup, no framework
  tokens.css        copied from design/tokens.css (source of truth)
  app.css           shell styles, tokens only
  app.js            render(state) + transport (Tauri | Mock)
src-tauri/
  tauri.conf.json   window, CSP, NSIS bundle
  Cargo.toml        dependencies, all allowlisted
  src/              backend — not yet written
```

## Contract between shell and backend

The UI owns no update logic. It renders a state object and sends three
intents. Every decision about what to download, verify or apply lives in Rust,
where it is testable without a window.

Backend → shell, on the `patcher://state` event:

```ts
{
  state: 'checking' | 'uptodate' | 'available' | 'downloading'
       | 'applying' | 'done' | 'error',
  channel, version, targetVersion, serial,
  signatureVerified: boolean,
  plan: [{ id, from, to, kind: 'delta'|'full', size }],
  total, done, bps, current,          // downloading
  appliedCount,                       // done
  errorTitle, errorText, rolledBack,  // error
  log: string[],
}
```

Shell → backend, via `invoke('patcher_intent', { intent })`:
`check` · `install` · `cancel` · `retry` · `launch` · `notes`

Because the shell is a pure function of that object, the backend can be
developed against the mock's exact shape and swapped in with no UI changes.

## Still to do

- [ ] `src/` — manifest fetch + Ed25519 verify, planner, downloader, applier,
      self-update. Specified in [docs/patcher-protocol.md](../docs/patcher-protocol.md).
- [ ] `icons/icon.ico` — needs a rasteriser; none installed here.
      Source is [brand/animosis-mark.svg](../brand/animosis-mark.svg), with
      [animosis-mark-16.svg](../brand/animosis-mark-16.svg) for the 16/24px
      frames.
- [ ] Bundle Source Sans 3 + JetBrains Mono `.woff2` with their `OFL.txt`.
      Bundled, never CDN-fetched: a patcher that fetches fonts renders in a
      fallback face exactly when the network is broken.
- [ ] Ed25519 keypair; public keys pinned in the binary, private key offline.
- [ ] Authenticode EV certificate for the installer.

## Notes

`ui/tokens.css` is a **copy** of `design/tokens.css`. Edit the original and
re-copy; a build step should enforce this once one exists.

The CSP in `tauri.conf.json` is locked to `'self'`. Release notes open in the
system browser rather than in-window, so a compromised CDN cannot inject
script into a process that has write access to the install directory.
