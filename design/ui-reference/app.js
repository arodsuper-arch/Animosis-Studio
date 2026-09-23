/*
 * Animosis Patcher — shell controller.
 *
 * The UI is a pure function of state. It owns no update logic: it renders what
 * the backend reports and sends back exactly three intents (install, retry,
 * launch). Every decision about what to download, verify or apply lives in
 * Rust, where it can be tested without a window.
 *
 * Transport is swappable. Under Tauri it talks to the real backend; opened
 * directly in a browser it drives itself from MockTransport, so the shell can
 * be designed and reviewed before any Rust exists.
 */

(() => {
  'use strict';

  // ---- DOM ---------------------------------------------------------------

  const $ = (id) => document.getElementById(id);
  const el = {
    root: document.documentElement,
    headline: $('headline'), subline: $('subline'),
    progress: $('progress'), bar: $('bar'), barFill: $('bar-fill'),
    progressWhat: $('progress-what'), progressNums: $('progress-nums'),
    changes: $('changes'), changesList: $('changes-list'),
    changesCount: $('changes-count'), changesSize: $('changes-size'),
    callout: $('callout'), calloutIcon: $('callout-icon'),
    calloutTitle: $('callout-title'), calloutText: $('callout-text'),
    log: $('log'), logLines: $('log-lines'),
    sig: $('sig'), sigText: $('sig-text'), ver: $('ver'),
    btnPrimary: $('btn-primary'), btnSecondary: $('btn-secondary'),
    btnMinimize: $('btn-minimize'), btnClose: $('btn-close'),
  };

  const ICON = {
    check: '<path d="M2.5 8.5l3.5 3.5 7.5-8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
    alert: '<path d="M8 1.6l6.6 12H1.4L8 1.6z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><path d="M8 6.2v3.1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="8" cy="11.6" r="0.85" fill="currentColor"/>',
    info: '<circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M8 7.2v4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="8" cy="4.8" r="0.85" fill="currentColor"/>',
  };

  // ---- Formatting --------------------------------------------------------

  // Decimal MB, matching what a browser and the OS both report. Users compare
  // these numbers against their download folder; matching the OS beats being
  // pedantic about MiB.
  const bytes = (n) => {
    if (!Number.isFinite(n) || n < 0) return '—';
    if (n < 1000) return `${n} B`;
    const u = ['kB', 'MB', 'GB', 'TB'];
    let i = -1;
    do { n /= 1000; i++; } while (n >= 1000 && i < u.length - 1);
    return `${n.toFixed(n < 10 ? 1 : 0)} ${u[i]}`;
  };

  const rate = (bps) => (Number.isFinite(bps) && bps > 0 ? `${bytes(bps)}/s` : '—');

  const eta = (remaining, bps) => {
    if (!Number.isFinite(bps) || bps <= 0) return '';
    const s = Math.round(remaining / bps);
    if (s < 60) return `${s}s left`;
    if (s < 3600) return `${Math.round(s / 60)}m left`;
    return `${(s / 3600).toFixed(1)}h left`;
  };

  // ---- Render ------------------------------------------------------------

  let logSeen = [];

  function setButton(node, label, onClick, { primary = false } = {}) {
    if (!label) { node.hidden = true; node.onclick = null; return; }
    node.hidden = false;
    node.textContent = label;
    node.disabled = !onClick;
    node.onclick = onClick || null;
    void primary;
  }

  function setCallout(kind, title, text) {
    if (!kind) { el.callout.hidden = true; return; }
    el.callout.hidden = false;
    el.callout.className = `callout callout--${kind}`;
    el.calloutIcon.innerHTML = kind === 'error' ? ICON.alert : kind === 'success' ? ICON.check : ICON.info;
    el.calloutTitle.textContent = title;
    el.calloutText.textContent = text;
  }

  function renderChanges(items) {
    if (!items || !items.length) { el.changes.hidden = true; return; }
    el.changes.hidden = false;
    el.changesList.replaceChildren(...items.map((p) => {
      const li = document.createElement('li');
      li.className = 'changes__row';

      const id = document.createElement('span');
      id.className = 'changes__id';
      id.textContent = p.id;

      const ver = document.createElement('span');
      ver.className = 'changes__ver';
      ver.textContent = p.from ? `${p.from} → ${p.to}` : p.to;

      const tag = document.createElement('span');
      const kind = p.kind === 'delta' ? 'delta' : p.from ? 'full' : 'new';
      tag.className = `changes__tag changes__tag--${kind}`;
      tag.textContent = kind;

      const size = document.createElement('span');
      size.className = 'changes__ver';
      size.textContent = bytes(p.size);

      li.append(id, ver, tag, size);
      return li;
    }));

    const total = items.reduce((a, p) => a + (p.size || 0), 0);
    el.changesCount.textContent = `${items.length} package${items.length === 1 ? '' : 's'} to update`;
    el.changesSize.textContent = bytes(total);
  }

  function renderLog(lines) {
    if (!lines || !lines.length) { el.log.hidden = true; return; }
    el.log.hidden = false;
    // Append only what is new, so the live region does not re-announce the
    // whole log on every progress tick.
    for (let i = logSeen.length; i < lines.length; i++) {
      const li = document.createElement('li');
      li.textContent = lines[i];
      el.logLines.appendChild(li);
    }
    logSeen = lines.slice();
    el.logLines.scrollTop = el.logLines.scrollHeight;
  }

  function render(s) {
    el.root.dataset.state = s.state;
    el.ver.textContent = s.version ? `v${s.version}` : '';

    el.sig.hidden = !s.signatureVerified;
    if (s.signatureVerified) {
      el.sigText.textContent = s.serial ? `Signature verified · serial ${s.serial}` : 'Signature verified';
    }

    const determinate = s.state === 'downloading';
    el.progress.hidden = !(determinate || s.state === 'applying');
    el.bar.classList.toggle('bar--indeterminate', s.state === 'applying');

    if (determinate) {
      const pct = s.total > 0 ? Math.min(100, (s.done / s.total) * 100) : 0;
      el.barFill.style.width = `${pct}%`;
      el.bar.setAttribute('aria-valuenow', Math.round(pct));
      el.progressWhat.textContent = s.current ? `Downloading ${s.current}` : 'Downloading…';
      const left = eta(s.total - s.done, s.bps);
      el.progressNums.textContent =
        `${bytes(s.done)} / ${bytes(s.total)} · ${rate(s.bps)}${left ? ` · ${left}` : ''}`;
    } else if (s.state === 'applying') {
      el.bar.removeAttribute('aria-valuenow');
      el.progressWhat.textContent = s.current || 'Applying update…';
      el.progressNums.textContent = '';
    }

    renderChanges(s.state === 'available' ? s.plan : null);
    renderLog(s.log);

    switch (s.state) {
      case 'checking':
        el.headline.textContent = 'Checking for updates';
        el.subline.textContent = `Contacting the ${s.channel || 'stable'} channel…`;
        setCallout(null);
        setButton(el.btnPrimary, null);
        setButton(el.btnSecondary, null);
        break;

      case 'uptodate':
        el.headline.textContent = 'Animosis Studio is up to date';
        el.subline.textContent = `You are on the latest ${s.channel || 'stable'} release.`;
        setCallout('success', 'Nothing to install', 'Every package matches the current manifest.');
        setButton(el.btnPrimary, 'Launch', () => transport.send('launch'));
        setButton(el.btnSecondary, 'Check again', () => transport.send('check'));
        break;

      case 'available':
        el.headline.textContent = `Update available — ${s.targetVersion}`;
        el.subline.textContent = `You are on ${s.version}. Nothing is changed on disk until every file is downloaded and verified.`;
        setCallout(null);
        setButton(el.btnPrimary, 'Install', () => transport.send('install'));
        setButton(el.btnSecondary, 'Release notes', () => transport.send('notes'));
        break;

      case 'downloading':
        el.headline.textContent = `Updating to ${s.targetVersion}`;
        el.subline.textContent = 'Downloading and verifying. You can cancel safely — your install is untouched.';
        setCallout(null);
        setButton(el.btnPrimary, null);
        setButton(el.btnSecondary, 'Cancel', () => transport.send('cancel'));
        break;

      case 'applying':
        el.headline.textContent = 'Applying update';
        el.subline.textContent = 'Swapping files in. This is quick — please do not close the patcher.';
        setCallout(null);
        setButton(el.btnPrimary, null);
        setButton(el.btnSecondary, null);
        break;

      case 'done':
        el.headline.textContent = `Updated to ${s.version}`;
        el.subline.textContent = 'All packages verified and installed.';
        setCallout('success', 'Update complete', `${s.appliedCount} package${s.appliedCount === 1 ? '' : 's'} updated and verified.`);
        setButton(el.btnPrimary, 'Launch', () => transport.send('launch'));
        setButton(el.btnSecondary, null);
        break;

      case 'error':
        el.headline.textContent = 'Update failed';
        el.subline.textContent = s.rolledBack
          ? 'Your install was rolled back and is safe to use.'
          : 'Your install was not changed.';
        // Amber, icon, left rule, plain-language cause — never red, and never
        // colour alone. docs/patcher-protocol.md §6.
        setCallout('error', s.errorTitle || 'Something went wrong', s.errorText || '');
        setButton(el.btnPrimary, 'Retry', () => transport.send('retry'));
        setButton(el.btnSecondary, 'Launch anyway', () => transport.send('launch'));
        break;
    }
  }

  // ---- Transports --------------------------------------------------------

  const TauriTransport = {
    available: () => typeof window.__TAURI__ !== 'undefined',
    start() {
      const { event, core } = window.__TAURI__;
      event.listen('patcher://state', (e) => render(e.payload));
      this.send = (intent) => core.invoke('patcher_intent', { intent });
      this.send('check');
    },
    send() {},
  };

  /* Drives the shell through a realistic run so the UI can be judged without a
     backend. Timings and sizes mirror the worked example in
     schema/examples/stable-0.5.0.json. */
  const MockTransport = {
    available: () => true,
    start() { this.reset(); },

    reset() {
      this.s = {
        state: 'checking', channel: 'stable', version: '0.4.1',
        log: [], signatureVerified: false,
      };
      render(this.s);
      this.step(700, () => {
        Object.assign(this.s, {
          state: 'available', targetVersion: '0.5.0', serial: 42,
          signatureVerified: true,
          plan: [
            { id: 'animosis.schema',  from: '0.4.0', to: '0.5.0', kind: 'delta', size: 88420 },
            { id: 'animosis.core',    from: '0.4.1', to: '0.5.0', kind: 'delta', size: 19087654 },
            { id: 'animosis.terrain', from: null,    to: '0.5.0', kind: 'full',  size: 358318080 },
          ],
          log: [
            'manifest.json fetched — 4.2 kB',
            'signature verified — ed25519 key 2026a',
            'serial 42 accepted (last seen 41)',
            'plan: 2 deltas, 1 full — 377.5 MB',
          ],
        });
        render(this.s);
      });
    },

    send(intent) {
      if (intent === 'check') return this.reset();
      if (intent === 'cancel') { this.cancelled = true; return this.reset(); }
      if (intent === 'retry')  { this.cancelled = false; return this.install(); }
      if (intent === 'install') return this.install();
      if (intent === 'launch') this.note('launch requested');
      if (intent === 'notes')  this.note('release notes opened in browser');
    },

    note(line) { this.s.log = [...this.s.log, line]; render(this.s); },

    install() {
      this.cancelled = false;
      const total = this.s.plan.reduce((a, p) => a + p.size, 0);
      Object.assign(this.s, { state: 'downloading', total, done: 0, bps: 0, current: this.s.plan[0].id });
      this.s.log = [...this.s.log, 'staging/ prepared'];
      render(this.s);

      const started = performance.now();
      let idx = 0, acc = 0;

      const tick = () => {
        if (this.cancelled) return;
        const chunk = 9_500_000 + Math.random() * 5_000_000;
        this.s.done = Math.min(total, this.s.done + chunk);
        acc += chunk;
        this.s.bps = acc / ((performance.now() - started) / 1000);

        let seen = 0;
        for (const p of this.s.plan) {
          seen += p.size;
          if (this.s.done <= seen) { this.s.current = p.id; break; }
        }
        while (idx < this.s.plan.length && this.s.done >= this.s.plan.slice(0, idx + 1).reduce((a, p) => a + p.size, 0)) {
          const p = this.s.plan[idx++];
          this.s.log = [...this.s.log, `${p.id} ${p.kind === 'delta' ? 'patched' : 'fetched'} — sha256 ok`];
        }

        render(this.s);
        if (this.s.done < total) this.step(220, tick); else this.apply();
      };
      this.step(260, tick);
    },

    apply() {
      Object.assign(this.s, { state: 'applying', current: 'Writing journal…' });
      this.s.log = [...this.s.log, 'journal written, fsync ok'];
      render(this.s);

      this.step(620, () => {
        this.s.current = 'Swapping files…';
        this.s.log = [...this.s.log, '3 packages staged → live'];
        render(this.s);
        this.step(780, () => {
          Object.assign(this.s, {
            state: 'done', version: '0.5.0', appliedCount: 3,
            log: [...this.s.log, 'state.json committed', 'journal cleared, backup removed'],
          });
          render(this.s);
        });
      });
    },

    step(ms, fn) { setTimeout(fn, ms); },
  };

  // ---- Window controls ---------------------------------------------------

  const win = () => window.__TAURI__ && window.__TAURI__.window.getCurrentWindow();
  el.btnMinimize.onclick = () => (win() ? win().minimize() : null);
  el.btnClose.onclick    = () => (win() ? win().close()    : window.close());

  // ---- Boot --------------------------------------------------------------

  const transport = TauriTransport.available() ? TauriTransport : MockTransport;
  transport.start();
})();
