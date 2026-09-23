# Licensing policy

Animosis ships commercial, closed-source binaries and a creation tool other
people will use. That combination makes dependency licensing a build-time
gate, not a pre-launch cleanup. A single GPL transitive dependency discovered
late can force a rewrite of whatever links it.

**The rule: if a dependency's licence is not on the allowlist, it does not go
in.** No exceptions granted informally, no "we'll swap it later."

---

## Allowlist — use freely

| Licence | Obligation |
|---|---|
| MIT / Expat / X11 | Reproduce notice |
| BSD-2-Clause, BSD-3-Clause | Reproduce notice; BSD-3 also forbids using the author's name to endorse |
| Apache-2.0 | Reproduce notice **and propagate any `NOTICE` file**; carries a patent grant |
| ISC, Zlib, BSL-1.0 | Reproduce notice |
| Unlicense, CC0-1.0, MIT-0 | None |
| SIL OFL 1.1 (fonts) | Reproduce notice; don't sell the font alone; rename if modified |

## Conditional — needs a decision on the record

| Licence | Why it is not automatic |
|---|---|
| **MPL-2.0** | File-level copyleft. Fine if used unmodified. If you edit a covered file you must publish **that file's** source. Acceptable for leaf libraries; record the decision. |
| **LGPL-2.1 / 3.0** | Only compliant if **dynamically** linked with relinking possible. Static linking or NativeAOT trimming silently violates it — and AOT is exactly what a small patcher wants. Treat as banned unless someone has genuinely verified the linking model. |
| **CC-BY-4.0** | Fine for docs and assets, requires attribution. Not for code. |

## Banned

**GPL-2.0, GPL-3.0, AGPL-3.0, SSPL, BUSL, Commons Clause, CC-BY-NC, CC-BY-SA,
"free for personal use", "source available", any licence with a field-of-use or
revenue restriction.**

AGPL deserves a specific note: its network clause triggers on *users
interacting over a network*, so it reaches a hosted asset service or an update
server, not just shipped binaries. Several popular "open source" infrastructure
projects are AGPL or have relicensed to it. Check at adoption, and re-check at
major version bumps — **relicensing mid-project is common** and your pinned
version's licence is the one you got, not the one on the README today.

---

## Enforcement

1. **At adoption.** Read the actual `LICENSE` file in the pinned version. Not
   the README, not the package registry's metadata field, not a summary site —
   registry metadata is self-reported and frequently wrong.
2. **In CI.** A licence scan on the full transitive graph, failing the build on
   anything off the allowlist. This is the control that matters; step 1 is
   human and humans miss things. Transitive dependencies are where GPL actually
   enters a project — nobody adds it on purpose.
3. **At release.** `THIRD-PARTY-NOTICES.txt` regenerated from the resolved
   dependency graph and shipped in the install directory, reachable from an
   About screen. Generated, never hand-maintained: a hand-written list is out
   of date the first time someone bumps a lockfile.

Keep dependency count deliberately low. Every dependency is a licence to track,
a supply-chain risk, and bytes in a download users are waiting on. A patcher
should have very few.

---

## Known dependency positions

Verified against upstream licence files, not summaries.

| Component | Licence | Note |
|---|---|---|
| **Zstandard** | BSD-3-Clause (dual GPLv2) | Dual-licensed — **elect BSD-3**. Record the election. Covers both compression and `--patch-from` deltas. |
| **Ed25519** | ISC (libsodium) / BSD-3 (ed25519-dalek) / MIT (BouncyCastle, NSec) | All clean. Prefer the platform's vetted crypto where one exists. |
| **SHA-256** | — | Use the OS/runtime primitive. Never hand-roll crypto. |
| **Source Sans 3** | SIL OFL 1.1 | Adobe. Bundled, not fetched — the patcher must render with no network. |
| **JetBrains Mono** | SIL OFL 1.1 | Bundled. |
| **Godot** (engine fork) | MIT | Third-party manifest audited: no GPL/LGPL code. Only MPL-2.0 file is Mozilla's CA bundle (data, replaceable). Strip `misc/logo/*` (CC-BY-4.0 **and** trademarked) and all `Godot` branding. |

### Fonts are bundled, not linked from a CDN

A patcher that fetches fonts at runtime renders in a fallback face exactly when
the network is broken — which is when people are most likely to be staring at
it. Ship the `.woff2`/`.ttf` files and their `OFL.txt`.

---

## Trademark discipline

Licence compliance and trademark compliance are separate problems, and the
second is where forks actually get letters:

- Nothing ships under the name **Godot**, and the Godot logo is never used as
  ours. Factual "derived from Godot Engine" is fine; implied endorsement is not.
- The Animosis mark is original artwork with drawn letterforms — no font
  rendering, so no font licence attaches to the logo itself.
- Deliberately **not** adopting Adobe's icon system (bordered squircle +
  two-letter monogram on a tinted field). See the mark exploration; Route D was
  chosen partly for this reason.

---

## Contributions

Any outside contribution requires a signed **CLA** before merge. Without one
you accumulate contributor copyrights you do not control, which blocks
relicensing, dual-licensing and some acquisition paths — permanently, because
tracking down past contributors for retroactive permission rarely works.

Set this up before the first external PR, not after.

---

## Not legal advice

This is an engineering policy derived from reading the licences. Before public
launch, have an IP attorney review the dependency manifest, the Godot fork
position and the trademark clearance. An hour of counsel is the cheapest
insurance in the project.
