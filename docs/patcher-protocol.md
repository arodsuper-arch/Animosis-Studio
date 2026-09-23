# Animosis Patcher — protocol and trust model

Status: design, pre-implementation. Stack-independent: every rule here holds
whichever language the client is written in.

The patcher's job is narrow and it should stay narrow: **learn what the channel
contains, fetch only the difference, prove it is genuine, and put it in place
without ever leaving the install half-updated.** Anything beyond that (accounts,
news feeds, telemetry dashboards) belongs in the Studio app, not in the thing
that has write access to the install directory.

---

## 1. Trust model

### What is signed

**Only `manifest.json`.** Every artifact is authenticated by a SHA-256 recorded
inside the manifest, so one signature transitively covers the entire release.
This is deliberate: one signing operation per release means the private key is
used rarely and can live offline, and adding a package never means re-signing
hundreds of files.

```
manifest.json          the signed document
manifest.json.sig      Ed25519 detached signature, 64 raw bytes
```

### Verify over the bytes as received

The signature is checked against **the exact bytes downloaded**, before the JSON
is parsed. Never re-serialise the document and verify that — JSON
canonicalisation is a well-known source of signature-bypass bugs, because two
parsers can disagree about duplicate keys, number formatting or Unicode escapes.
Bytes in, verify, then parse. If parsing then fails, discard everything.

### Key pinning and rotation

The client ships a **list** of trusted Ed25519 public keys compiled into the
binary, not a single key:

```
TRUSTED_KEYS = [ key_2026a, key_2027a ]
```

A manifest is accepted if its signature validates against **any** pinned key.
Rotation without bricking older clients:

1. Ship a patcher release trusting `[old, new]`. Keep signing with `old`.
2. Wait for adoption.
3. Switch signing to `new`.
4. A later patcher release drops `old`.

Skipping step 1 strands every user who has not updated, and they cannot update
*because* updating is the thing that broke. Never rotate in one step.

The private key lives offline — a hardware token or an air-gapped machine —
and signing is a deliberate manual step in the release process, never something
CI can do unattended. CI produces artifacts and an unsigned manifest; a human
signs it.

### Downgrade protection

Signatures prove authenticity, not freshness. An attacker who can serve you
files (a hostile network, a compromised CDN edge) can replay a *genuinely
signed* older manifest to push you back onto a version with a known
vulnerability.

The defence is `serial`: a monotonically increasing integer per channel. The
client records the highest serial it has ever accepted and **refuses any
manifest with a lower one**, signature valid or not. Serials are never reused
or reordered. `released` is informational only — clocks skew legitimately and
can be influenced by an attacker, so they cannot be the ordering authority.

Switching channels resets this, because channels are independent timelines.
Moving stable → beta is a deliberate user action with its own confirmation.

### What TLS is and is not for

HTTPS is mandatory on `baseUrl`, but it is **not** the integrity guarantee —
the signature is. TLS is there so a passive observer cannot see which packages
a user installs. Treat a successful TLS handshake as worth nothing for trust
purposes: verify the signature and every hash regardless.

### Hostile input discipline

Everything from the network is attacker-controlled until proven otherwise:

- **Hash before decompress.** A decompressor handed unverified bytes is a
  parser handed attacker data. Verify SHA-256 over the compressed artifact
  first, then unpack.
- **Cap every read** at the manifest's declared `size`. Stop and fail if the
  body exceeds it — a hostile CDN must not be able to stream unbounded data at
  the disk.
- **Bound unpacking** with `unpackedSize`, and check it against free space
  before starting. This is what stops a decompression bomb.
- **Re-derive every path** locally. `installPath` and artifact `url` come from
  a signed document, but signed is not the same as correct — a compromised
  build pipeline signs whatever it is handed. Reject any path containing `..`,
  a leading `/`, a drive letter, or a symlink component, and confirm the
  resolved absolute path is still inside the install root. This is the check
  that turns a build-server compromise into a failed update instead of
  arbitrary file write.
- **Never render remote content.** `notes` opens in the user's browser. An
  in-app HTML view would make signed-but-hostile markup an attack surface for
  no benefit.

---

## 2. Update flow

```
  ┌─ resolve ────────────────────────────────────────────┐
  │ GET {base}/{product}/{channel}/manifest.json + .sig   │
  │ verify signature over raw bytes                       │
  │ parse; check schema == 1                              │
  │ check serial > highestSeenSerial       else ABORT     │
  │ check patcherVersion >= minPatcher     else SELF-UPDATE│
  └───────────────────────────────────────────────────────┘
                          │
  ┌─ plan ────────────────▼───────────────────────────────┐
  │ filter packages by platform                           │
  │ diff against state.json                               │
  │ topologically sort by dependsOn (reject cycles)       │
  │ per package: delta if local version matches a          │
  │   delta.from exactly, else full artifact              │
  │ sum bytes; check free space >= sum + unpacked + slack │
  └───────────────────────────────────────────────────────┘
                          │
  ┌─ fetch ───────────────▼───────────────────────────────┐
  │ download to staging/, HTTP Range resume, size-capped  │
  │ verify SHA-256 of each downloaded file                │
  │ apply deltas; verify resultSha256                     │
  │   mismatch -> discard, fall back to full, once        │
  │ unpack into staging/{pkgid}/, bounded                 │
  └───────────────────────────────────────────────────────┘
                          │
  ┌─ apply (atomic) ──────▼───────────────────────────────┐
  │ write journal, fsync                                  │
  │ per file: current -> backup/, staged -> destination   │
  │ write state.json (temp + fsync + rename)              │
  │ delete journal, then backup/                          │
  └───────────────────────────────────────────────────────┘
```

Nothing touches the live install until every byte is downloaded, verified and
unpacked. A user who loses their connection mid-update has a full install and a
wasted staging directory, never a broken one.

### Deltas are an optimisation, never a dependency

A delta is used only when the recorded local version matches `delta.from`
exactly. After applying, the result must hash to `resultSha256`, which the
schema requires to equal the full artifact's `sha256` — that is what proves
both paths converge on identical bytes. On any mismatch: discard, fall back to
the full artifact, once, and report it. The full artifact must always stay
downloadable so recovery is always possible.

---

## 3. Atomic apply and rollback

Journal is append-only and fsync'd before each destructive step:

```
{"op":"begin","serial":42,"at":"..."}
{"op":"move","from":"core/engine.dll","to":"backup/core/engine.dll"}
{"op":"move","from":"staging/animosis.core/engine.dll","to":"core/engine.dll"}
...
{"op":"commit"}
```

**Recovery on startup:** if a journal exists without a `commit`, the previous
run died mid-apply. Replay the recorded moves **backwards** to restore the
previous install, delete the journal, and report a rolled-back update. Because
every step was fsync'd before the move it describes, the journal can never be
behind the filesystem — only ahead, and an already-undone move is a no-op.

`state.json` is written temp-then-`rename` so it is never observed
half-written; on POSIX and NTFS a rename over an existing file is atomic.

Only after `state.json` lands does the journal get deleted, then `backup/`.
Deleting `backup/` first would create a window where a crash leaves nothing to
roll back to.

### Local state

```json
{
  "schema": 1,
  "product": "animosis-studio",
  "channel": "stable",
  "highestSerial": 42,
  "patcherVersion": "0.3.0",
  "packages": {
    "animosis.core": { "version": "0.5.0", "sha256": "...", "installPath": "core" }
  }
}
```

State records what the patcher *believes* is installed. A `--verify` mode
re-hashes the install and rebuilds state from the files on disk, which is the
repair path when a user deletes something by hand or an antivirus quarantines a
file mid-write.

---

## 4. Self-update

The patcher updates itself before anything else when `patcherVersion <
minPatcher`. On Windows a running executable cannot be deleted or overwritten —
but it **can be renamed**, which is the whole trick:

1. Download the new patcher to `patcher.exe.new`; verify hash and Authenticode.
2. `MoveFile(patcher.exe → patcher.exe.old)` — legal while running.
3. `MoveFile(patcher.exe.new → patcher.exe)`.
4. Launch the new `patcher.exe` with the original arguments; exit immediately.
5. The new patcher deletes `patcher.exe.old` on startup. If it is locked,
   leave it; the next run tries again.

On Linux and macOS the running binary's inode survives an unlink, so a plain
replace works — but keep the same rename sequence everywhere so one code path
is tested on all platforms.

**The self-update artifact is signed the same way as everything else, and is
additionally code-signed for the OS.** A patcher that can replace itself over
the network is the highest-value target in the whole system; it gets the
strictest checks, not the most convenient ones.

---

## 5. Code signing

Separate from the Ed25519 manifest signature, and not optional:

- **Windows:** Authenticode. An unsigned installer gets a SmartScreen
  interstitial that destroys install conversion. An **EV certificate** earns
  SmartScreen reputation immediately; a standard OV cert has to build
  reputation over weeks of downloads. Budget for EV.
- **macOS:** Developer ID signing **and notarisation**. Without notarisation,
  Gatekeeper refuses to run it at all on current macOS — this is a hard block,
  not a warning.
- **Linux:** no OS-level equivalent. Publish detached GPG signatures and the
  SHA-256 of each release artifact.

---

## 6. Error presentation

Red is the Animosis brand accent, which creates a specific hazard: **a failed
patch and a primary button must not look alike.**

| State | Treatment |
|---|---|
| Primary action | `--red-primary` fill, `--on-red` label |
| Progress | `--red-primary` bar on `--surface-raised` |
| Success | `--status-success` + check icon |
| Warning | `--status-warn` + left rule |
| **Error** | `--status-error` amber + icon + left rule + plain-language cause |

Never colour alone, for errors or anything else — roughly 1 in 12 men has a
colour vision deficiency, and red/green is the common axis. Icon plus text
carries the meaning; colour reinforces it.

Error copy names the cause and the next action: "Couldn't verify
`animosis.core` — the download was corrupted. Retry." Not "Error 0x80070005".
Log the code; show the sentence.

---

## 7. Deliberately out of scope

Kept out on purpose, because each one widens the attack surface of a process
that writes to the install directory:

- Accounts, licensing, entitlement checks — the Studio app's job.
- Telemetry beyond an anonymous version ping, if any, and off by default.
- Rendering any remote HTML or Markdown.
- Plugin or script execution during apply. Packages are **data**, never code
  that the patcher runs. Post-install steps, if ever needed, are a declarative
  allowlist in the schema — never an arbitrary command string, which would make
  a signed manifest a remote code execution primitive by design.
