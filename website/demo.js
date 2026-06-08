class UsageDemoController {
  static svg(inner, vb = "0 0 24 24", extra = "") {
    return `<svg viewBox="${vb}" fill="none" xmlns="http://www.w3.org/2000/svg" ${extra}>${inner}</svg>`;
  }

  static get ICONS() {
    const s = UsageDemoController.svg;
    return {
      spark: s(`<g stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 3v6"/><path d="M12 15v6"/><path d="M3 12h6"/><path d="M15 12h6"/><path d="M5.6 5.6l4.2 4.2"/><path d="M14.2 14.2l4.2 4.2"/><path d="M18.4 5.6l-4.2 4.2"/><path d="M9.8 14.2l-4.2 4.2"/></g>`),
      gear: s(`<circle cx="12" cy="12" r="3.2" stroke="currentColor" stroke-width="1.8"/><path d="M12 2.5v2.2M12 19.3v2.2M21.5 12h-2.2M4.7 12H2.5M18.7 5.3l-1.6 1.6M6.9 17.1l-1.6 1.6M18.7 18.7l-1.6-1.6M6.9 6.9 5.3 5.3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`),
      palette: s(`<path d="M12 3a9 9 0 1 0 0 18c1 0 1.6-.8 1.6-1.7 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.1 0-.9.8-1.6 1.7-1.6H16a5 5 0 0 0 5-5c0-4.1-4-7.4-9-7.4Z" stroke="currentColor" stroke-width="1.7"/><circle cx="7.5" cy="11" r="1.1" fill="currentColor"/><circle cx="11" cy="7.5" r="1.1" fill="currentColor"/><circle cx="15.5" cy="8" r="1.1" fill="currentColor"/>`),
      bell: s(`<path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M10 19a2 2 0 0 0 4 0" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`),
      user: s(`<circle cx="12" cy="8.5" r="3.6" stroke="currentColor" stroke-width="1.8"/><path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`),
      info: s(`<circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.8"/><path d="M12 11v5" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><circle cx="12" cy="7.8" r="1.2" fill="currentColor"/>`),
      chevR: s(`<path d="M9 6l6 6-6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`),
      refresh: s(`<path d="M20 11a8 8 0 1 0-1.5 5.5M20 5v5h-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`),
      external: s(`<path d="M14 4h6v6M20 4l-9 9M18 13v6a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`),
      logout: s(`<path d="M14 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2v-2M9 12h11m0 0-3-3m3 3-3 3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`),
      wifi: s(`<path d="M2 8.5C5 6 8.4 4.6 12 4.6S19 6 22 8.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M5 12c2-1.8 4.4-2.8 7-2.8s5 1 7 2.8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M8 15.4c1.1-1 2.5-1.6 4-1.6s2.9.6 4 1.6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><circle cx="12" cy="19" r="1.4" fill="currentColor"/>`),
      battery: s(`<rect x="2" y="8" width="17" height="9" rx="2.2" stroke="currentColor" stroke-width="1.6"/><rect x="4" y="10" width="10" height="5" rx="1" fill="currentColor"/><path d="M21.5 11v3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`),
      volume: s(`<path d="M4 9v6h3l5 4V5L7 9H4Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M16 9.5a3.5 3.5 0 0 1 0 5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>`),
      search: s(`<circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="1.7"/><path d="m16 16 4 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`),
      control: s(`<rect x="3" y="3" width="18" height="18" rx="5" stroke="currentColor" stroke-width="1.6"/><circle cx="9" cy="9" r="2.2" fill="currentColor"/><circle cx="15" cy="15" r="2.2" fill="currentColor"/>`),
      power: s(`<path d="M12 3v8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M6.5 6.5a8 8 0 1 0 11 0" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`),
      files: s(`<path d="M4 7a2 2 0 0 1 2-2h3l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>`),
      winlogo: s(`<rect x="3" y="3" width="8" height="8" rx="1" fill="currentColor"/><rect x="13" y="3" width="8" height="8" rx="1" fill="currentColor"/><rect x="3" y="13" width="8" height="8" rx="1" fill="currentColor"/><rect x="13" y="13" width="8" height="8" rx="1" fill="currentColor"/>`),
      min: s(`<path d="M4 12h16" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>`),
      max: s(`<rect x="5" y="5" width="14" height="14" rx="2" stroke="currentColor" stroke-width="1.6"/>`),
      close: s(`<path d="M6 6l12 12M18 6 6 18" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`),
    };
  }

  static icon(name) { return UsageDemoController.ICONS[name] || ""; }

  constructor() {
    this.roots = [...document.querySelectorAll(".demo")];
    if (!this.roots.length) return;
    this.media = window.matchMedia("(prefers-color-scheme: light)");
    this.state = {
      platform: "mac",
      theme: "dark",
      accent: "warm",
      trayStyle: "percent",
      showPct: true,
      launchLogin: true,
      autoUpdate: true,
      showStatus: true,
      refresh: "5m",
      reduceTransp: false,
      compact: false,
      notify: true,
      sessionThresh: "85%",
      weeklyThresh: "90%",
      message: "Heads up — you've used {pct} of your {limit} limit. Resets {reset}.",
      page: "general",
      signedIn: true,
    };
    this.usage = {
      session: { name: "Session (5 hour)", pct: 67, reset: "Resets at 3:45 PM", tokens: "58.2k tokens left", limit: "session" },
      weekly: { name: "Weekly (7 day)", pct: 82, reset: "Resets Mon, Jun 9", tokens: "1.4M tokens left", limit: "weekly" },
    };
    this.pageMeta = {
      general: { ico: "gear", bg: "#5a6b7a", title: "General" },
      appearance: { ico: "palette", bg: "#c8603f", title: "Tray & Appearance" },
      notifications: { ico: "bell", bg: "#e0823a", title: "Notifications" },
      account: { ico: "user", bg: "#8a6db0", title: "Account" },
      about: { ico: "info", bg: "#7d8389", title: "About" },
    };
    this.nav = [
      { sec: "General" },
      { id: "general", label: "General", ico: "gear", bg: "#5a6b7a" },
      { sec: "Appearance" },
      { id: "appearance", label: "Tray & Appearance", ico: "palette", bg: "#c8603f" },
      { id: "notifications", label: "Notifications", ico: "bell", bg: "#e0823a" },
      { sec: "Account" },
      { id: "account", label: "Account", ico: "user", bg: "#8a6db0" },
      { id: "about", label: "About", ico: "info", bg: "#7d8389" },
    ];
    this.toastTimer = null;
    this.bind();
    this.renderAll();
  }

  query(sel, scope = document) { return scope.querySelector(sel); }
  queryAll(sel, scope = document) { return [...scope.querySelectorAll(sel)]; }

  levelKey(pct) {
    if (pct >= 87) return "crit";
    if (pct >= 70) return "high";
    if (pct >= 45) return "mid";
    return "low";
  }

  levelColor(pct) {
    return getComputedStyle(this.roots[0]).getPropertyValue("--lv-" + this.levelKey(pct)).trim();
  }

  worstPct() { return Math.max(this.usage.session.pct, this.usage.weekly.pct); }

  fillIcons(scope = document) {
    this.queryAll("[data-ico]", scope).forEach(el => {
      const n = el.getAttribute("data-ico");
      if (el.dataset.done !== n) { el.innerHTML = UsageDemoController.icon(n); el.dataset.done = n; }
    });
  }

  resolvedTheme() {
    if (this.state.theme === "system") return this.media.matches ? "light" : "dark";
    return this.state.theme;
  }

  applyChrome() {
    const theme = this.resolvedTheme();
    this.roots.forEach(r => {
      r.dataset.theme = theme;
      r.dataset.platform = this.state.platform;
      r.dataset.accent = this.state.accent;
    });
    this.queryAll("#platformSeg button").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.platform === this.state.platform)));
    this.queryAll("#themeSeg button").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.theme === this.state.theme)));
  }

  trayGlyphHTML(style, pct) {
    const col = this.levelColor(pct);
    if (style === "ring") {
      const r = 6.4, c = 2 * Math.PI * r, off = c * (1 - pct / 100);
      return `<svg class="tray-glyph" viewBox="0 0 16 16">
        <circle cx="8" cy="8" r="${r}" fill="none" stroke="currentColor" stroke-width="2.2" opacity=".28"/>
        <circle cx="8" cy="8" r="${r}" fill="none" stroke="${col}" stroke-width="2.2" stroke-linecap="round"
          stroke-dasharray="${c.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}" transform="rotate(-90 8 8)"/>
      </svg>`;
    }
    if (style === "logo") {
      return `<svg class="tray-glyph" viewBox="0 0 24 24" style="color:${col}">${UsageDemoController.icon("spark")}</svg>`;
    }
    return `<span class="tray-glyph" style="width:8px;height:8px;border-radius:50%;background:${col}"></span>`;
  }

  renderTray() {
    const pct = this.worstPct();
    const html = this.trayGlyphHTML(this.state.trayStyle, pct) +
      (this.state.showPct ? `<span class="tray-pct" style="color:${this.levelColor(pct)}">${pct}%</span>` : "");
    this.queryAll("#desktop .tray-btn").forEach(btn => {
      const open = btn.classList.contains("is-open");
      btn.innerHTML = html;
      btn.classList.toggle("is-open", open);
    });
  }

  meterHTML(d) {
    const col = this.levelColor(d.pct);
    return `<div class="meter">
      <div class="meter-top"><span class="meter-name">${d.name}</span><span class="meter-reset">${d.reset}</span></div>
      <div class="track"><div class="fill" style="background:${col}" data-pct="${d.pct}"></div></div>
      <div class="meter-bottom"><span class="meter-used">${d.pct}% used</span><span class="meter-tokens">${d.tokens}</span></div>
    </div>`;
  }

  renderPopover() {
    const pop = this.query("#popover");
    if (!pop) return;
    pop.innerHTML = `
      <div class="pop-title">Claude Usage</div>
      ${this.meterHTML(this.usage.session)}
      ${this.meterHTML(this.usage.weekly)}
      ${this.state.showStatus ? `<div class="pop-divider"></div>
      <div class="status-row"><span class="status-dot"></span><span class="status-text">All Claude services operational</span></div>` : ""}
      <div class="pop-foot">
        <span class="pop-updated">Last updated: <span id="lastUpd">${this.nowLabel()}</span></span>
        <button class="pop-refresh" id="popRefresh">${UsageDemoController.icon("refresh")}<span>Refresh</span></button>
      </div>`;
    if (pop.classList.contains("open")) this.animateFills(pop);
    this.query("#popRefresh").addEventListener("click", () => this.onRefresh());
  }

  nowLabel() {
    return new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  }

  animateFills(scope) {
    this.queryAll(".fill", scope).forEach(f => {
      f.style.width = "0";
      requestAnimationFrame(() => requestAnimationFrame(() => { f.style.width = f.dataset.pct + "%"; }));
    });
  }

  onRefresh() {
    const btn = this.query("#popRefresh");
    btn.classList.add("spinning");
    setTimeout(() => {
      btn.classList.remove("spinning");
      const el = this.query("#lastUpd");
      if (el) el.textContent = this.nowLabel();
    }, 850);
  }

  togglePopover(force) {
    const pop = this.query("#popover");
    if (!pop) return;
    const open = force != null ? force : !pop.classList.contains("open");
    pop.classList.toggle("open", open);
    this.query("#desktop").classList.toggle("opened", open);
    this.queryAll("#desktop .tray-btn").forEach(b => b.classList.toggle("is-open", open));
    if (open) this.animateFills(pop);
  }

  row(opts) {
    return `<div class="srow ${opts.btn ? "btn" : ""}" ${opts.attr || ""}>
      <div class="srow-tx"><div class="srow-tt">${opts.title}</div>${opts.sub ? `<div class="srow-sub">${opts.sub}</div>` : ""}</div>
      ${opts.right || ""}
    </div>`;
  }

  toggle(key, on) {
    return `<label class="switch"><input type="checkbox" data-toggle="${key}" ${on ? "checked" : ""}/><span class="slider"></span></label>`;
  }

  mseg(key, val, opts) {
    return `<div class="mseg" data-mseg="${key}">${opts.map(o =>
      `<button data-val="${o}" aria-pressed="${String(o === val)}">${o}</button>`).join("")}</div>`;
  }

  pageGeneral() {
    return `
      <div class="group-label">Startup</div>
      ${this.row({ title: "Launch at login", sub: "Open Usage Bar automatically when you sign in", right: this.toggle("launchLogin", this.state.launchLogin) })}
      ${this.row({ title: "Check for updates automatically", right: this.toggle("autoUpdate", this.state.autoUpdate) })}
      <div class="group-label">Appearance</div>
      ${this.row({ title: "Theme", sub: "Match your system or pick a side", right: this.mseg("theme", this.state.theme, ["light", "dark", "system"]) })}
      <div class="group-label">Data</div>
      ${this.row({ title: "Refresh interval", sub: "How often usage is pulled", right: this.mseg("refresh", this.state.refresh, ["1m", "5m", "15m"]) })}
      ${this.row({ title: "Show service status", sub: "Display Claude status line in the popover", right: this.toggle("showStatus", this.state.showStatus) })}
    `;
  }

  pageAppearance() {
    const icoOpt = (style, cap, glyph) => `<button class="opt ${this.state.trayStyle === style ? "sel" : ""}" data-trayopt="${style}">
      <span class="opt-preview" style="background:var(--field)">${glyph}</span><span class="opt-cap">${cap}</span></button>`;
    const ringPrev = `<svg width="22" height="22" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.2" fill="none" stroke="var(--track)" stroke-width="2.2"/><circle cx="8" cy="8" r="6.2" fill="none" stroke="var(--lv-mid)" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="39" stroke-dashoffset="12" transform="rotate(-90 8 8)"/></svg>`;
    const accentSwatch = (key, c1, c2) => `<button class="swatch ${this.state.accent === key ? "sel" : ""}" data-accent="${key}" title="${key}" style="background:linear-gradient(135deg, ${c1} 0 50%, ${c2} 50% 100%)"></button>`;
    return `
      <div class="group-label">Tray icon</div>
      ${this.row({ title: "Show percentage in tray", sub: "Display the busiest limit as a number", right: this.toggle("showPct", this.state.showPct) })}
      <div class="group-label">Icon style</div>
      <div class="opt-grid">
        ${icoOpt("percent", "Number", `<span style="font-size:13px;font-weight:700;color:var(--lv-mid)">82%</span>`)}
        ${icoOpt("ring", "Ring", ringPrev)}
        ${icoOpt("logo", "Mark", `<span style="color:var(--lv-mid);width:22px;height:22px;display:block">${UsageDemoController.icon("spark")}</span>`)}
      </div>
      <div class="group-label">Accent palette</div>
      <div class="srow" style="display:block">
        <div class="swatches">
          ${accentSwatch("warm", "#e0a84a", "#d4583a")}
          ${accentSwatch("cool", "#36c97a", "#e0613e")}
          ${accentSwatch("coral", "#cf9168", "#bd5238")}
          ${accentSwatch("mono", "#9aa0a6", "#5f656b")}
        </div>
        <div class="note">Bars shade from amber → red as a limit fills. The palette sets the family.</div>
      </div>
      <div class="group-label">Window</div>
      ${this.row({ title: "Reduce transparency", right: this.toggle("reduceTransp", this.state.reduceTransp) })}
      ${this.row({ title: "Compact popover", sub: "Tighter spacing, smaller footprint", right: this.toggle("compact", this.state.compact) })}
    `;
  }

  pageNotifications() {
    const count = this.state.message.length;
    return `
      <div class="group-label">Alerts</div>
      ${this.row({ title: "Enable notifications", sub: "Warn you before you hit a limit", right: this.toggle("notify", this.state.notify) })}
      ${this.row({ title: "Session warning at", sub: "Notify when your 5-hour limit reaches", right: this.mseg("sessionThresh", this.state.sessionThresh, ["75%", "85%", "95%"]) })}
      ${this.row({ title: "Weekly warning at", sub: "Notify when your 7-day limit reaches", right: this.mseg("weeklyThresh", this.state.weeklyThresh, ["80%", "90%", "95%"]) })}
      <div class="group-label">Custom message</div>
      <div class="srow" style="display:block">
        <textarea class="tinput" id="msgInput" rows="3" maxlength="160">${this.state.message}</textarea>
        <div class="char-count"><span id="msgCount">${count}</span>/160</div>
        <div class="note">Tokens: <span class="kbd">{pct}</span> <span class="kbd">{limit}</span> <span class="kbd">{reset}</span> are filled in automatically.</div>
      </div>
      <div class="srow btn" data-action="previewNotif"><div class="srow-tx"><div class="srow-tt">Preview notification</div><div class="srow-sub">Send a test toast with your message</div></div><span class="srow-chev" data-ico="chevR"></span></div>
    `;
  }

  pageAccount() {
    if (!this.state.signedIn) {
      return `<div class="group-label">Account</div>
        ${this.row({ title: "Not signed in", sub: "Connect a Claude account to pull real usage" })}
        <div class="row-actions"><button class="btn-primary" data-action="signin"><span data-ico="spark"></span>Continue with Claude</button></div>`;
    }
    return `
      <div class="group-label">Signed in</div>
      <div class="account-card">
        <div class="avatar" style="background:var(--accent-int)">A</div>
        <div><div class="acc-name">Alex Tran</div><div class="acc-mail">alex.tran@gmail.com</div></div>
        <span class="acc-plan">Max plan</span>
      </div>
      ${this.row({ title: "Connected", sub: "Since May 2, 2026", right: `<span class="srow-val">claude.ai</span>` })}
      ${this.row({ title: "Sync usage across devices", right: this.toggle("sync", true) })}
      <div class="row-actions">
        <button class="btn-ghost" data-action="signout"><span style="display:inline-flex;width:15px;height:15px;vertical-align:-2px;margin-right:6px" data-ico="logout"></span>Sign out</button>
      </div>
    `;
  }

  pageAbout() {
    return `
      <div style="display:flex;align-items:center;gap:14px;margin-bottom:18px">
        <span style="width:48px;height:48px;border-radius:12px;background:var(--accent-int);display:grid;place-items:center;color:#fff" data-ico="spark"></span>
        <div><div style="font-size:17px;font-weight:680">Claude Usage Bar</div><div class="srow-sub" style="margin-top:2px">Version 1.4.0 (build 240)</div></div>
      </div>
      <div class="group-label">App</div>
      ${this.row({ title: "Check for updates", btn: true, right: `<span class="srow-chev" data-ico="chevR"></span>` })}
      ${this.row({ title: "What's new", btn: true, right: `<span class="srow-chev" data-ico="chevR"></span>` })}
      ${this.row({ title: "Website", btn: true, right: `<span class="srow-chev" data-ico="external"></span>` })}
      <div class="group-label">License</div>
      ${this.row({ title: "Status", right: `<span class="srow-val" style="color:#35c46b">● Activated</span>` })}
      ${this.row({ title: "Acknowledgements", btn: true, right: `<span class="srow-chev" data-ico="chevR"></span>` })}
      <div class="note">Made for macOS, Windows &amp; Linux. Not affiliated with Anthropic.</div>
    `;
  }

  pageFor(id) {
    const pages = {
      general: () => this.pageGeneral(),
      appearance: () => this.pageAppearance(),
      notifications: () => this.pageNotifications(),
      account: () => this.pageAccount(),
      about: () => this.pageAbout(),
    };
    return pages[id]();
  }

  renderNav() {
    const nav = this.query("#settingsNav");
    if (!nav) return;
    nav.innerHTML = this.nav.map(n => {
      if (n.sec) return `<div class="nav-sec">${n.sec}</div>`;
      return `<button class="nav-item ${this.state.page === n.id ? "active" : ""}" data-nav="${n.id}">
        <span class="nav-ico" style="background:${n.bg}">${UsageDemoController.icon(n.ico)}</span><span>${n.label}</span></button>`;
    }).join("");
  }

  renderPanel() {
    const panel = this.query("#settingsPanel");
    if (!panel) return;
    const m = this.pageMeta[this.state.page];
    panel.innerHTML = `
      <div class="panel-head"><span class="panel-ico" style="background:${m.bg}">${UsageDemoController.icon(m.ico)}</span><span class="panel-title">${m.title}</span></div>
      <div class="page active">${this.pageFor(this.state.page)}</div>`;
    this.fillIcons(panel);
  }

  renderSettings() { this.renderNav(); this.renderPanel(); }

  galTray(style, pct, showPct) {
    return `<span class="tray-btn" style="background:rgba(255,255,255,.12);color:#fff">
      ${this.trayGlyphHTML(style, pct)}${showPct ? `<span class="tray-pct" style="color:${this.levelColor(pct)}">${pct}%</span>` : ""}</span>`;
  }

  renderGallery() {
    const grid = this.query("#galGrid");
    if (!grid) return;
    const items = [
      { s: "percent", p: 32, t: "Number", d: "Plenty left" },
      { s: "percent", p: 67, t: "Number", d: "Session warming" },
      { s: "percent", p: 89, t: "Number", d: "Near the cap" },
      { s: "ring", p: 45, t: "Ring", d: "Quarter used" },
      { s: "ring", p: 82, t: "Ring", d: "Weekly busy" },
      { s: "ring", p: 96, t: "Ring", d: "Almost out" },
      { s: "logo", p: 58, t: "Mark", d: "With %", showPct: true },
      { s: "logo", p: 90, t: "Mark", d: "Mark only", showPct: false },
    ];
    grid.innerHTML = items.map(i => `
      <div class="gal-card">
        <div class="gal-bar">${this.galTray(i.s, i.p, i.showPct != null ? i.showPct : true)}</div>
        <div class="gal-cap"><b>${i.t} · ${i.p}%</b>${i.d}</div>
      </div>`).join("");
  }

  buildMessage(which) {
    const d = which === "weekly" ? this.usage.weekly : this.usage.session;
    const reset = d.reset.replace(/^Resets (at )?/, "");
    return this.state.message
      .replace(/\{pct\}/g, d.pct + "%")
      .replace(/\{limit\}/g, d.limit)
      .replace(/\{reset\}/g, reset);
  }

  toastHTML(os, label) {
    return `<div class="toast ${os}">
      <span class="toast-ico">${UsageDemoController.icon("spark")}</span>
      <div class="toast-bd">
        <div class="toast-os">${label}</div>
        <div class="toast-tt"><span>Claude Usage Bar</span><span class="toast-time">now</span></div>
        <div class="toast-msg">${this.buildMessage("weekly")}</div>
      </div>
    </div>`;
  }

  renderNotifications() {
    const stack = this.query("#notifStack");
    if (!stack) return;
    stack.innerHTML =
      this.toastHTML("mac", "macOS · Notification Center") +
      this.toastHTML("win", "Windows · Action Center") +
      this.toastHTML("ubuntu", "Ubuntu · GNOME Shell");
  }

  fireLiveToast() {
    const el = this.query("#liveToast");
    if (!el) return;
    el.innerHTML = this.toastHTML(this.state.platform, "Claude Usage Bar");
    void el.offsetHeight;
    el.classList.add("show");
    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => el.classList.remove("show"), 4200);
  }

  renderAll() {
    this.applyChrome();
    this.renderTray();
    this.renderPopover();
    this.renderSettings();
    this.renderGallery();
    this.renderNotifications();
    this.fillIcons();
  }

  setTweak(key, val) {
    this.state[key] = val;
    this.applyChrome();
    this.renderTray();
    this.renderPopover();
    this.renderGallery();
    if (this.state.page === "appearance") this.renderPanel();
  }

  bind() {
    const platformSeg = this.query("#platformSeg");
    if (platformSeg) platformSeg.addEventListener("click", e => {
      const b = e.target.closest("button"); if (!b) return;
      this.state.platform = b.dataset.platform; this.togglePopover(false); this.renderAll();
    });
    const themeSeg = this.query("#themeSeg");
    if (themeSeg) themeSeg.addEventListener("click", e => {
      const b = e.target.closest("button"); if (!b) return;
      this.state.theme = b.dataset.theme; this.renderAll();
    });

    this.media.addEventListener("change", () => {
      if (this.state.theme === "system") { this.applyChrome(); this.renderAll(); }
    });

    document.addEventListener("click", e => {
      const tray = e.target.closest(".tray-btn[data-tray]");
      if (tray) { this.togglePopover(); return; }

      const nav = e.target.closest("[data-nav]");
      if (nav) { this.state.page = nav.dataset.nav; this.renderSettings(); return; }

      const trayopt = e.target.closest("[data-trayopt]");
      if (trayopt) { this.setTweak("trayStyle", trayopt.dataset.trayopt); return; }

      const acc = e.target.closest(".swatch[data-accent]");
      if (acc) { this.setTweak("accent", acc.dataset.accent); return; }

      const mseg = e.target.closest("[data-mseg] button");
      if (mseg) {
        const key = mseg.closest("[data-mseg]").dataset.mseg;
        this.state[key] = mseg.dataset.val;
        if (key === "theme") { this.renderAll(); } else { this.renderPanel(); this.renderPopover(); }
        return;
      }

      const action = e.target.closest("[data-action]");
      if (action) {
        const a = action.dataset.action;
        if (a === "previewNotif") this.fireLiveToast();
        if (a === "signout") { this.state.signedIn = false; this.renderPanel(); }
        if (a === "signin") { this.state.signedIn = true; this.renderPanel(); }
        return;
      }

      if (!e.target.closest("#popover") && !e.target.closest(".tray-btn")) {
        const pop = this.query("#popover");
        if (pop && pop.classList.contains("open")) this.togglePopover(false);
      }
    });

    document.addEventListener("change", e => {
      const t = e.target.closest("[data-toggle]");
      if (t) {
        this.state[t.dataset.toggle] = t.checked;
        this.renderTray(); this.renderPopover();
      }
    });

    document.addEventListener("input", e => {
      if (e.target.id === "msgInput") {
        this.state.message = e.target.value;
        const c = this.query("#msgCount"); if (c) c.textContent = e.target.value.length;
        this.renderNotifications();
      }
    });

    const trigger = this.query("#notifTrigger");
    if (trigger) trigger.addEventListener("click", () => this.fireLiveToast());

    document.addEventListener("keydown", e => {
      if ((e.metaKey || e.ctrlKey) && e.key === "u") {
        e.preventDefault();
        this.togglePopover();
        const pop = this.query("#popover");
        if (pop && pop.classList.contains("open")) pop.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    });
  }
}

document.addEventListener("DOMContentLoaded", () => { window.usageDemo = new UsageDemoController(); });
