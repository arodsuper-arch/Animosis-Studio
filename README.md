# Animosis Studio

A creation platform for virtual worlds: asset design, character creation,
scalable terrain, animation and effects, plus the simulation systems
(combat, economy, locomotion) that make a world run.

Built as **Animosis Core** — a runtime-agnostic, deterministic simulation and
content layer — with presentation delivered through a fork of the
MIT-licensed Godot engine. Core owns the systems and the schema; the renderer
is replaceable.

---

## Repository layout

| Path | Contents |
|---|---|
| `brand/` | The Animosis mark. Original artwork, drawn letterforms, no font dependency. |
| `design/` | `tokens.css` — colour, type, spacing. Source of truth for every Animosis UI. |
| `docs/` | Protocol and policy specs. |
| `schema/` | `manifest.schema.json` + worked examples. The release manifest contract. |
| `patcher/` | The updater client. |

## Start here

- **[docs/patcher-protocol.md](docs/patcher-protocol.md)** — trust model,
  update flow, atomic apply and rollback, self-update, error presentation.
- **[schema/manifest.schema.json](schema/manifest.schema.json)** — the signed
  document that describes a release. Everything downstream keys off this.
- **[docs/licensing-policy.md](docs/licensing-policy.md)** — dependency
  allowlist and the rules that keep the product commercially shippable.

## Why the manifest came first

The patcher is the first consumer of the content manifest, not a standalone
updater. Package identity, versioning, dependency graph, integrity and
migration are the same problems the character creator, terrain streamer and
asset pipeline will each have. Solving them once, here, means every later
system is a package in an established format rather than a new format to
reconcile.

## Design references

- [Mark exploration](https://claude.ai/artifact/9wXyR48w4YUy1HnpaqEHT8) —
  four routes, colour system with measured contrast, real-size checks.

## Typography

**Source Sans 3** (UI) and **JetBrains Mono** (versions, paths, logs), both
SIL OFL 1.1 — free for commercial use, embeddable, bundled with the
application. `OFL.txt` ships for each.

## Licensing

Dependencies are gated by [docs/licensing-policy.md](docs/licensing-policy.md).
Allowlist only, enforced in CI, `THIRD-PARTY-NOTICES.txt` generated at release.
