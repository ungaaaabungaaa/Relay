const watchScreens = {
  pairing: {
    index: "01",
    title: "Secure pairing",
    body: "The watch enters the six-character code from the Mac, verifies its fingerprint, and waits for explicit Mac approval.",
    rule: "Both people-visible fingerprints must match",
    render: () => `
      <span class="watch-time">PAIRING · 04:38</span>
      <p class="watch-kicker">Studio Mac</p>
      <h3 class="watch-title">Confirm Mac</h3>
      <article class="watch-card">
        <small>MAC FINGERPRINT</small>
        <strong class="mono-small">630D:CD29:66C4:3366</strong>
        <p>Enter the six-character code shown on the Mac.</p>
      </article>
      <div class="code-cells" aria-label="Pairing code">
        <span>R</span><span>7</span><span>K</span><span>2</span><span>M</span><span>Q</span>
      </div>
      <button class="watch-button primary wide" data-jump="home">Request Mac approval</button>
    `,
  },
  home: {
    index: "02",
    title: "Home",
    body: "The urgent thing is always first. A pending approval outranks active work, recent tasks, and connection details.",
    rule: "Two meaningful taps or fewer",
    render: () => `
      <span class="watch-time">10:24 · LIVE</span>
      <p class="watch-kicker">Needs you</p>
      <h3 class="watch-title">1 approval<br>is waiting</h3>
      <article class="watch-card urgent">
        <small>CODEWATCH · 22 SEC</small>
        <strong>Ship release checkpoint</strong>
        <p>git push origin main</p>
      </article>
      <button class="watch-button primary wide" data-jump="approval">Review approval</button>
      <div class="watch-actions">
        <button class="watch-button" data-jump="task">Tasks · 3</button>
        <button class="watch-button" data-jump="new-task">New task</button>
      </div>
    `,
  },
  approval: {
    index: "03",
    title: "Approval",
    body: "Relay shows the exact operation and consequence. Dangerous work uses a deliberate 1.5-second hold; moving away cancels it.",
    rule: "Unknown risk fails into dangerous",
    render: () => `
      <span class="watch-time">10:24 · EXPIRES 4:38</span>
      <p class="watch-kicker" style="color:var(--amber)">Dangerous</p>
      <h3 class="watch-title">Push branch?</h3>
      <article class="watch-card urgent">
        <small>NETWORK + REPOSITORY</small>
        <strong>git push origin main</strong>
        <p>~/Developer/SandBox/codewatch</p>
      </article>
      <button class="watch-button primary wide hold-button" style="--hold:0%">Hold to approve</button>
      <button class="watch-button danger wide">Deny</button>
    `,
  },
  task: {
    index: "04",
    title: "Task timeline",
    body: "The watch summarizes activity instead of shrinking a terminal. Commands and consequences remain available where they matter.",
    rule: "Useful signal, not raw terminal noise",
    render: () => `
      <span class="watch-time">10:24 · RUNNING</span>
      <p class="watch-kicker">Relay release</p>
      <h3 class="watch-title">Quality gates</h3>
      <div class="task-progress"><i></i></div>
      <div class="timeline">
        <p>41 bridge tests passed</p>
        <p>21 Mac tests passed</p>
        <p>Building signed APK…</p>
      </div>
      <div class="watch-actions">
        <button class="watch-button" data-jump="voice">Steer</button>
        <button class="watch-button danger">Stop</button>
      </div>
      <button class="watch-button wide" data-jump="home">Back home</button>
    `,
  },
  voice: {
    index: "05",
    title: "Reviewed voice",
    body: "Voice is never auto-sent. Record, transcribe on the Mac, review the words, and only then steer Codex.",
    rule: "Transcript review before every send",
    render: () => `
      <span class="watch-time">10:24 · PRIVATE</span>
      <p class="watch-kicker">Steer Codex</p>
      <h3 class="watch-title">Hold to speak</h3>
      <div class="record-ring">
        <button class="record-button" aria-label="Hold to record voice">REC</button>
      </div>
      <p class="watch-copy record-status">Audio stays temporary and is deleted after transcription.</p>
      <button class="watch-button wide" data-jump="task">Use keyboard instead</button>
    `,
  },
  "new-task": {
    index: "06",
    title: "New task",
    body: "A short guided flow chooses an approved workspace, current Codex model, reasoning effort, permission profile, and prompt.",
    rule: "Never hard-code Codex capabilities",
    render: () => `
      <span class="watch-time">10:24 · STEP 1/5</span>
      <p class="watch-kicker">New task</p>
      <h3 class="watch-title">Workspace</h3>
      <p class="watch-copy">Only folders approved on the Mac appear here.</p>
      <div class="picker-list">
        <button class="selected">Relay · codewatch</button>
        <button>Studio · dev-studio</button>
        <button>Shop · mmart</button>
      </div>
      <button class="watch-button primary wide">Continue</button>
    `,
  },
  offline: {
    index: "07",
    title: "Honest offline state",
    body: "Relay shows cached summaries as stale and disables actions. It never silently queues an approval for later.",
    rule: "Offline means read-only",
    render: () => `
      <span class="watch-time">10:24 · STALE</span>
      <div class="offline-symbol" aria-hidden="true"></div>
      <p class="watch-kicker" style="color:var(--amber)">Mac offline</p>
      <h3 class="watch-title">Wake your Mac</h3>
      <p class="watch-copy">Wake the Mac and confirm Relay Cloud is connected.</p>
      <button class="watch-button primary wide">Reconnect</button>
      <button class="watch-button wide">Settings</button>
    `,
  },
};

const dashboardPanels = {
  setup: {
    eyebrow: "Start here",
    title: "Nine steps, three installs",
    subtitle: "Install Codex and Relay on the Mac, then Relay on the watch. The wizard resumes at the first unfinished step.",
    rows: [
      ["01", "Relay and Codex", "Verify the arm64 sidecar and installed Codex.", "Done", true],
      ["02", "Email sign-in", "Use the one-time link in your browser.", "Done", true],
      ["03", "Cloud connection", "Open an outbound encrypted Relay tunnel.", "Done", true],
      ["04", "Security preflight", "Both Relay ports remain loopback-only.", "Done", true],
      ["05", "Install watch app", "Get Relay from the Play closed-test track.", "Current", false],
      ["06", "Enter pairing code", "The six-character code expires in five minutes.", "Waiting", false],
      ["07", "Pair and approve", "Compare fingerprints before approving.", "Waiting", false],
      ["08", "Workspaces", "Choose the only folders visible to Relay.", "Waiting", false],
      ["09", "Start at login", "Optional; disabled until you choose it.", "Off · safe", true],
    ],
    action: "Continue setup",
  },
  watches: {
    eyebrow: "Play closed test",
    title: "Install and pair a watch",
    subtitle: "The consumer setup uses Google Play. ADB remains an optional developer-only fallback outside this wizard.",
    rows: [
      ["01", "Play invitation", "Open the closed-test link with your Google account.", "Ready", true],
      ["02", "Relay for Wear OS", "Install directly on a Wear OS 3+ watch.", "Waiting", false],
      ["03", "Secure pairing", "Enter the Mac code and compare fingerprints.", "Waiting", false],
    ],
    action: "Open pairing",
  },
  remote: {
    eyebrow: "Encrypted transport",
    title: "Relay Cloud is connected",
    subtitle: "Both apps connect outbound. Relay Cloud routes authenticated ciphertext but has no key that can read Codex content.",
    rows: [
      ["LB", "Loopback bridge", "Admin and watch listeners are local only.", "Ready", true],
      ["ST", "Security self-test", "Unsigned and replayed requests are rejected.", "Ready", true],
      ["E2", "Encrypted tunnel", "Per-watch AES-GCM root key is device-held.", "Connected", true],
    ],
    action: "Manage connection",
  },
  workspaces: {
    eyebrow: "Filesystem boundary",
    title: "Approved workspaces",
    subtitle: "The watch can browse folder names only below roots you choose here. File contents stay on the Mac.",
    rows: [
      ["01", "codewatch", "~/Developer/SandBox/codewatch", "Approved", true],
      ["+", "Add a workspace", "Choose one folder; symlinks cannot escape it.", "Choose", false],
    ],
    action: "Choose folder",
  },
  voice: {
    eyebrow: "Optional mode",
    title: "Voice stays reviewed",
    subtitle: "System dictation needs no API key. Optional hold-to-record transcription stores its OpenAI key only in Keychain.",
    rows: [
      ["OS", "Wear OS input", "Built-in keyboard and dictation.", "Ready", true],
      ["AI", "Mac transcription", "Temporary audio; transcript is never auto-sent.", "Not configured", false],
    ],
    action: "Save Keychain key",
  },
  updates: {
    eyebrow: "Signed metadata",
    title: "Update without guessing",
    subtitle: "Relay verifies the Ed25519 manifest, Apple silicon architecture, tag, version, and SHA-256 before offering an update.",
    rows: [
      ["MAC", "Relay for Mac", "Sparkle stable or beta signed feed.", "Current", true],
      ["PLAY", "Relay for Wear OS 3+", "Google Play installs signed watch updates.", "Current", true],
      ["CDX", "Codex compatibility", "Supported range comes from the release manifest.", "Checked", true],
    ],
    action: "Check again",
  },
  diagnostics: {
    eyebrow: "Redacted evidence",
    title: "Local diagnostics",
    subtitle: "Status is useful, but credentials, prompts, command output, file contents, and audio never enter diagnostic logs.",
    rows: [
      ["BR", "Bridge process", "One running instance; bounded crash restart.", "Healthy", true],
      ["CX", "Codex adapter", "Capabilities loaded from installed app-server.", "Healthy", true],
      ["DB", "Local data", "Device, nonce, audit, and event metadata only.", "Healthy", true],
    ],
    action: "Copy redacted report",
  },
  about: {
    eyebrow: "One Relay product",
    title: "Native where it matters",
    subtitle: "The first GitHub DMG contains the Mac app, bridge, and Wear OS APK. Apple Watch follows through TestFlight.",
    rows: [
      ["MAC", "Apple silicon", "macOS 14+ · menu-bar control room.", "Initial", true],
      ["WEAR", "Wear OS 3+", "One APK · round and square.", "Initial", true],
      ["AW", "watchOS 10+", "Independent app · App Store delivery.", "Phase 2", false],
    ],
    action: "Apache 2.0",
  },
};

const watchScreen = document.querySelector("#watch-screen");
const noteIndex = document.querySelector("#note-index");
const noteTitle = document.querySelector("#note-title");
const noteBody = document.querySelector("#note-body");
const noteRule = document.querySelector("#note-rule");
const railButtons = [...document.querySelectorAll(".rail-button")];
const dashboardPanel = document.querySelector("#dashboard-panel");
const sideItems = [...document.querySelectorAll(".side-item")];

function showWatchScreen(name) {
  const screen = watchScreens[name];
  if (!screen) return;
  watchScreen.classList.remove("watch-screen");
  void watchScreen.offsetWidth;
  watchScreen.classList.add("watch-screen");
  watchScreen.innerHTML = screen.render();
  noteIndex.textContent = `SCREEN ${screen.index} / 07`;
  noteTitle.textContent = screen.title;
  noteBody.textContent = screen.body;
  noteRule.textContent = screen.rule;
  railButtons.forEach((button) => {
    const active = button.dataset.screen === name;
    button.classList.toggle("active", active);
    button.setAttribute("aria-selected", String(active));
  });
  attachWatchInteractions();
}

function attachWatchInteractions() {
  watchScreen.querySelectorAll("[data-jump]").forEach((button) => {
    button.addEventListener("click", () => showWatchScreen(button.dataset.jump));
  });

  const holdButton = watchScreen.querySelector(".hold-button");
  if (holdButton) {
    let started = 0;
    let frame = 0;
    const stop = () => {
      cancelAnimationFrame(frame);
      started = 0;
      holdButton.style.setProperty("--hold", "0%");
      holdButton.textContent = "Hold to approve";
    };
    const tick = (now) => {
      if (!started) started = now;
      const progress = Math.min(100, ((now - started) / 1500) * 100);
      holdButton.style.setProperty("--hold", `${progress}%`);
      if (progress >= 100) {
        holdButton.textContent = "Approved once";
        holdButton.disabled = true;
        return;
      }
      frame = requestAnimationFrame(tick);
    };
    holdButton.addEventListener("pointerdown", (event) => {
      holdButton.setPointerCapture(event.pointerId);
      holdButton.classList.add("holding");
      frame = requestAnimationFrame(tick);
    });
    holdButton.addEventListener("pointerup", () => {
      holdButton.classList.remove("holding");
      if (!holdButton.disabled) stop();
    });
    holdButton.addEventListener("pointercancel", stop);
  }

  const recordButton = watchScreen.querySelector(".record-button");
  if (recordButton) {
    const ring = watchScreen.querySelector(".record-ring");
    const status = watchScreen.querySelector(".record-status");
    const start = (event) => {
      recordButton.setPointerCapture(event.pointerId);
      ring.classList.add("recording");
      recordButton.textContent = "00:01";
      status.textContent = "Recording… release to transcribe on the Mac.";
    };
    const stop = () => {
      ring.classList.remove("recording");
      recordButton.textContent = "DONE";
      status.textContent = "Transcript ready for review. Nothing was sent.";
    };
    recordButton.addEventListener("pointerdown", start);
    recordButton.addEventListener("pointerup", stop);
    recordButton.addEventListener("pointercancel", stop);
  }
}

function showDashboardPanel(name) {
  const panel = dashboardPanels[name] ?? dashboardPanels.setup;
  dashboardPanel.classList.remove("dashboard-panel");
  void dashboardPanel.offsetWidth;
  dashboardPanel.classList.add("dashboard-panel");
  dashboardPanel.innerHTML = `
    <p class="dash-eyebrow">${panel.eyebrow}</p>
    <h3>${panel.title}</h3>
    <p class="dash-subtitle">${panel.subtitle}</p>
    <div class="requirement-panel">
      ${panel.rows.map(([symbol, title, detail, state, ready]) => `
        <div class="requirement-row">
          <span class="row-symbol">${symbol}</span>
          <div><strong>${title}</strong><small>${detail}</small></div>
          <span class="pill ${ready ? "" : "waiting"}">${state}</span>
        </div>
      `).join("")}
    </div>
    <button class="dash-action">${panel.action}</button>
  `;
  sideItems.forEach((item) => {
    item.classList.toggle("active", item.dataset.panel === name);
  });
}

railButtons.forEach((button) => {
  button.addEventListener("click", () => showWatchScreen(button.dataset.screen));
});

sideItems.forEach((item) => {
  item.addEventListener("click", () => showDashboardPanel(item.dataset.panel));
});

document.querySelectorAll("[data-shape]").forEach((button) => {
  button.addEventListener("click", () => {
    const square = button.dataset.shape === "square";
    document.querySelector(".watch").classList.toggle("square", square);
    document.querySelectorAll("[data-shape]").forEach((shapeButton) => {
      const active = shapeButton === button;
      shapeButton.classList.toggle("active", active);
      shapeButton.setAttribute("aria-pressed", String(active));
    });
  });
});

showWatchScreen("pairing");
showDashboardPanel("setup");
