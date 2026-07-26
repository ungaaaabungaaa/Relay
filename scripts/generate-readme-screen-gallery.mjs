import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = resolve(SCRIPT_DIR, "..");

export const SCREEN_GROUPS = [
  {
    file: "screens-connection.svg",
    index: "01",
    eyebrow: "CONNECTION / ONBOARDING",
    title: "Get the watch safely online",
    description: "Pair once, verify the Mac, and fail clearly when the link is not safe.",
    screens: [
      {
        name: "Welcome",
        label: "Welcome",
        layout: "hero",
        eyebrow: "RELAY",
        title: ["Codex", "on your wrist"],
        body: ["Tasks stay on your Mac"],
        primary: "Get started",
        tone: "green",
      },
      {
        name: "PairingCode",
        label: "Pairing code",
        layout: "pairing",
        eyebrow: "PAIR WATCH",
        title: ["Enter the Mac code"],
        code: "A7K9Q2",
        body: ["Found Studio Mac on Wi-Fi"],
        primary: "Request approval",
        tone: "green",
      },
      {
        name: "MacIdentity",
        label: "Mac identity",
        layout: "identity",
        eyebrow: "VERIFY DEVICE",
        title: ["Is this your Mac?"],
        body: ["Studio Mac", "630D:CD29:66C4:3366"],
        primary: "It matches",
        secondary: "Back",
        tone: "blue",
      },
      {
        name: "Connecting",
        label: "Connecting",
        layout: "status",
        eyebrow: "PRIVATE LINK",
        title: ["Connecting"],
        body: ["Opening a signed", "Relay session"],
        tone: "blue",
      },
      {
        name: "Offline",
        label: "Offline",
        layout: "status",
        eyebrow: "CONNECTION",
        title: ["Mac offline"],
        body: ["Wake the Mac and check", "Relay Cloud"],
        primary: "Reconnect",
        tone: "amber",
      },
      {
        name: "Revoked",
        label: "Revoked watch",
        layout: "status",
        eyebrow: "ACCESS REMOVED",
        title: ["Watch revoked"],
        body: ["Clear cached pairing", "and pair again"],
        primary: "Pair again",
        tone: "red",
      },
      {
        name: "UpdateRequired",
        label: "Update required",
        layout: "status",
        eyebrow: "COMPATIBILITY",
        title: ["Update required"],
        body: ["This version cannot use", "the bridge safely"],
        primary: "About updates",
        tone: "amber",
      },
    ],
  },
  {
    file: "screens-daily-control.svg",
    index: "02",
    eyebrow: "DAILY CONTROL",
    title: "See, answer, and steer Codex",
    description: "Attention first: approvals, questions, live task progress, and explicit controls.",
    screens: [
      {
        name: "Home",
        label: "Home",
        layout: "home",
        eyebrow: "RELAY / LIVE",
        title: ["Good evening"],
        metric: "2",
        metricLabel: "need you",
        items: [
          ["Relay release", "Running"],
          ["README gallery", "Codex working"],
        ],
        tone: "green",
      },
      {
        name: "Inbox",
        label: "Action inbox",
        layout: "list",
        eyebrow: "INBOX / 2",
        title: ["Needs attention"],
        items: [
          ["Approve command", "Dangerous", "red"],
          ["Choose release path", "Question", "blue"],
        ],
        tone: "green",
      },
      {
        name: "Approval",
        label: "Approval detail",
        layout: "approval",
        eyebrow: "DANGEROUS",
        title: ["Approve command?"],
        code: "git push origin main",
        body: ["Writes to a remote repository"],
        primary: "HOLD TO APPROVE",
        secondary: "Deny",
        tone: "red",
      },
      {
        name: "Question",
        label: "Codex question",
        layout: "choice",
        eyebrow: "CODEX ASKED",
        title: ["Which release path?"],
        items: [
          ["GitHub release", "Selected"],
          ["Keep private", ""],
        ],
        primary: "Review answer",
        tone: "blue",
      },
      {
        name: "Tasks",
        label: "Task list",
        layout: "list",
        eyebrow: "TASKS / 3",
        title: ["Your Codex tasks"],
        items: [
          ["Relay release", "Running", "green"],
          ["Security review", "Waiting", "amber"],
          ["Bridge tests", "Done", "muted"],
        ],
        tone: "green",
      },
      {
        name: "TaskDetail",
        label: "Task detail",
        layout: "timeline",
        eyebrow: "RELAY RELEASE",
        title: ["Codex is working"],
        items: [
          ["11:42", "Updated README"],
          ["11:43", "Running tests"],
          ["NOW", "Building preview"],
        ],
        primary: "Add instruction",
        tone: "green",
      },
      {
        name: "Instruction",
        label: "Send instruction",
        layout: "composer",
        eyebrow: "STEER TASK",
        title: ["Tell Codex what changed"],
        body: ["Also add every screen", "preview to the README"],
        primary: "Review & send",
        secondary: "Voice",
        tone: "blue",
      },
      {
        name: "SystemInput",
        label: "System input",
        layout: "composer",
        eyebrow: "WEAR OS INPUT",
        title: ["Type or dictate"],
        body: ["Make the setup easier", "for first-time users"],
        primary: "Use this text",
        secondary: "Cancel",
        tone: "blue",
      },
      {
        name: "VoiceRecord",
        label: "Voice recording",
        layout: "record",
        eyebrow: "VOICE / REVIEWED",
        title: ["Hold to record"],
        body: ["00:08 / 00:30"],
        secondary: "Use keyboard",
        tone: "red",
      },
      {
        name: "TranscriptReview",
        label: "Transcript review",
        layout: "review",
        eyebrow: "CHECK BEFORE SEND",
        title: ["Transcript"],
        body: ["“Add every screen preview", "to the README.”"],
        primary: "Send to Codex",
        secondary: "Record again",
        tone: "green",
      },
      {
        name: "TaskControls",
        label: "Task controls",
        layout: "controls",
        eyebrow: "RELAY RELEASE",
        title: ["Task controls"],
        items: [
          ["Add instruction", "Steer safely", "blue"],
          ["Stop task", "Ends this run", "red"],
        ],
        secondary: "Back to task",
        tone: "amber",
      },
    ],
  },
  {
    file: "screens-new-task.svg",
    index: "03",
    eyebrow: "NEW TASK",
    title: "Start work with the right boundaries",
    description: "Choose an approved folder, model, effort, permissions, and review before launch.",
    screens: [
      {
        name: "Workspaces",
        label: "Workspace list",
        layout: "list",
        eyebrow: "NEW TASK / 1 OF 7",
        title: ["Choose workspace"],
        items: [
          ["codewatch", "~/Developer/SandBox", "green"],
          ["dev-studio", "~/Developer/SandBox", "muted"],
        ],
        tone: "green",
      },
      {
        name: "Folders",
        label: "Folder browser",
        layout: "folders",
        eyebrow: "NEW TASK / 2 OF 7",
        title: ["codewatch"],
        body: ["~/Developer/SandBox/codewatch"],
        items: [
          ["docs", "Folder"],
          ["preview", "Folder"],
          ["wear", "Folder"],
        ],
        primary: "Use this folder",
        tone: "green",
      },
      {
        name: "Models",
        label: "Model selector",
        layout: "choice",
        eyebrow: "NEW TASK / 3 OF 7",
        title: ["Choose model"],
        items: [
          ["gpt-5.6-codex", "Selected"],
          ["gpt-5.6", ""],
          ["gpt-5.5-codex", ""],
        ],
        primary: "Continue",
        tone: "blue",
      },
      {
        name: "Effort",
        label: "Reasoning effort",
        layout: "choice",
        eyebrow: "NEW TASK / 4 OF 7",
        title: ["Reasoning effort"],
        items: [
          ["Low", "Fast"],
          ["Medium", "Selected"],
          ["High", "Deep"],
        ],
        primary: "Continue",
        tone: "blue",
      },
      {
        name: "Permissions",
        label: "Permission profile",
        layout: "choice",
        eyebrow: "NEW TASK / 5 OF 7",
        title: ["Permission profile"],
        items: [
          ["Safer public", "Selected"],
          ["Standard", ""],
          ["Expanded", "Warns first"],
        ],
        primary: "Continue",
        tone: "amber",
      },
      {
        name: "Prompt",
        label: "Prompt input",
        layout: "composer",
        eyebrow: "NEW TASK / 6 OF 7",
        title: ["What should Codex do?"],
        body: ["Prepare an Apple silicon", "GitHub release for Relay"],
        primary: "Review task",
        secondary: "Voice",
        tone: "blue",
      },
      {
        name: "NewTaskReview",
        label: "Review new task",
        layout: "summary",
        eyebrow: "NEW TASK / REVIEW",
        title: ["Ready to start?"],
        items: [
          ["Folder", "codewatch"],
          ["Model", "gpt-5.6-codex"],
          ["Effort", "Medium"],
          ["Access", "Safer public"],
        ],
        primary: "Start task",
        secondary: "Edit",
        tone: "green",
      },
    ],
  },
  {
    file: "screens-management.svg",
    index: "04",
    eyebrow: "MANAGEMENT",
    title: "Audit, tune, and understand Relay",
    description: "History stays visible; connection, monitoring, license, and versions stay explicit.",
    screens: [
      {
        name: "History",
        label: "Approval history",
        layout: "list",
        eyebrow: "APPROVAL HISTORY",
        title: ["Recent decisions"],
        items: [
          ["git push origin", "Approved", "green"],
          ["rm release.zip", "Denied", "red"],
          ["pnpm test", "Approved", "green"],
        ],
        tone: "green",
      },
      {
        name: "Settings",
        label: "Settings",
        layout: "settings",
        eyebrow: "SETTINGS",
        title: ["Relay preferences"],
        items: [
          ["Connection", "Live"],
          ["Live monitoring", "On"],
          ["Refresh", "15 min"],
        ],
        primary: "Refresh now",
        secondary: "Unpair watch",
        tone: "green",
      },
      {
        name: "About",
        label: "About & versions",
        layout: "about",
        eyebrow: "ABOUT RELAY",
        title: ["Relay 0.2 beta"],
        body: ["Watch + Mac matched", "Wear OS 3+  •  Apple silicon", "Apache License 2.0"],
        primary: "Check for update",
        tone: "blue",
      },
    ],
  },
];

const COLORS = {
  green: "#62E790",
  blue: "#6EB7FF",
  amber: "#FFBE55",
  red: "#FF6B6B",
  muted: "#A2A8B0",
};

function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function extractNativeScreens(kotlinSource) {
  const enumBody = kotlinSource.match(
    /enum\s+class\s+Screen\s*\{([\s\S]*?)\n\}/,
  )?.[1];

  if (!enumBody) {
    throw new Error("Could not find enum class Screen in RelayState.kt.");
  }

  return enumBody
    .replace(/\/\/.*$/gm, "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function validateCatalog(nativeScreens) {
  const catalogScreens = SCREEN_GROUPS.flatMap((group) =>
    group.screens.map((screen) => screen.name),
  );
  const duplicates = catalogScreens.filter(
    (name, index) => catalogScreens.indexOf(name) !== index,
  );
  const missing = nativeScreens.filter((name) => !catalogScreens.includes(name));
  const extra = catalogScreens.filter((name) => !nativeScreens.includes(name));

  if (duplicates.length || missing.length || extra.length) {
    throw new Error(
      [
        "README screen catalog does not match the native Screen enum.",
        duplicates.length ? `Duplicate: ${[...new Set(duplicates)].join(", ")}` : "",
        missing.length ? `Missing: ${missing.join(", ")}` : "",
        extra.length ? `Extra: ${extra.join(", ")}` : "",
      ]
        .filter(Boolean)
        .join(" "),
    );
  }
}

function text(x, y, value, className, anchor = "start") {
  return `<text x="${x}" y="${y}" class="${className}" text-anchor="${anchor}">${escapeXml(value)}</text>`;
}

function textLines(x, y, lines = [], className = "body", anchor = "middle", gap = 17) {
  return lines
    .map((line, index) => text(x, y + index * gap, line, className, anchor))
    .join("");
}

function pill(x, y, width, label, tone = "muted", filled = false) {
  const color = COLORS[tone] ?? COLORS.muted;
  const fill = filled ? color : "#191D20";
  const labelColor = filled ? "#050505" : color;
  return [
    `<rect x="${x}" y="${y}" width="${width}" height="28" rx="14" fill="${fill}" stroke="${color}" stroke-opacity="${filled ? 0 : 0.48}"/>`,
    text(x + width / 2, y + 18.5, label, "pill", "middle").replace(
      'class="pill"',
      `class="pill" fill="${labelColor}"`,
    ),
  ].join("");
}

function actionRow(screen, y = 272) {
  if (!screen.primary && !screen.secondary) return "";

  if (screen.primary && screen.secondary) {
    return [
      pill(82, y, 102, screen.secondary, "muted"),
      pill(192, y, 126, screen.primary, screen.tone, true),
    ].join("");
  }

  return pill(116, y, 168, screen.primary ?? screen.secondary, screen.tone, Boolean(screen.primary));
}

function statusMark(tone, layout) {
  const color = COLORS[tone] ?? COLORS.muted;
  const marks = {
    blue: `<path d="M185 117a22 22 0 1 1 30 0" fill="none" stroke="${color}" stroke-width="5" stroke-linecap="round"/><circle cx="200" cy="101" r="4" fill="${color}"/>`,
    amber: `<path d="M200 77l28 47h-56z" fill="none" stroke="${color}" stroke-width="4" stroke-linejoin="round"/><path d="M200 91v16" stroke="${color}" stroke-width="4" stroke-linecap="round"/><circle cx="200" cy="116" r="2.5" fill="${color}"/>`,
    red: `<circle cx="200" cy="101" r="24" fill="none" stroke="${color}" stroke-width="4"/><path d="M188 89l24 24m0-24l-24 24" stroke="${color}" stroke-width="4" stroke-linecap="round"/>`,
  };
  return marks[tone] ?? marks[layout === "status" ? "blue" : "amber"];
}

function renderListItems(screen, startY = 151, rowHeight = 43) {
  return (screen.items ?? [])
    .map(([label, meta, itemTone], index) => {
      const y = startY + index * rowHeight;
      const color = COLORS[itemTone] ?? COLORS.muted;
      return [
        `<rect x="77" y="${y}" width="246" height="36" rx="12" fill="#1A1E21" stroke="#343A3F"/>`,
        `<circle cx="94" cy="${y + 18}" r="4" fill="${color}"/>`,
        text(105, y + 16, label, "item"),
        text(105, y + 28, meta, "meta"),
      ].join("");
    })
    .join("");
}

function renderChoiceItems(screen, startY = 145) {
  return (screen.items ?? [])
    .map(([label, meta], index) => {
      const y = startY + index * 37;
      const selected = /selected/i.test(meta ?? "");
      const color = selected ? COLORS[screen.tone] : "#4A5056";
      return [
        `<rect x="86" y="${y}" width="228" height="31" rx="15.5" fill="${selected ? "#202A2C" : "#171A1D"}" stroke="${color}"/>`,
        `<circle cx="103" cy="${y + 15.5}" r="5.5" fill="${selected ? COLORS[screen.tone] : "none"}" stroke="${color}" stroke-width="2"/>`,
        text(117, y + 19.5, label, "choice"),
        meta && !selected ? text(298, y + 19.5, meta, "meta", "end") : "",
      ].join("");
    })
    .join("");
}

function renderScreenContent(screen) {
  const tone = COLORS[screen.tone] ?? COLORS.muted;
  const header = text(200, 65, screen.eyebrow, "eyebrow", "middle");

  switch (screen.layout) {
    case "hero":
      return [
        header,
        `<circle cx="200" cy="106" r="23" fill="#17231D" stroke="${tone}"/><path d="M188 106h24m-12-12v24" stroke="${tone}" stroke-width="3" stroke-linecap="round"/>`,
        textLines(200, 149, screen.title, "hero-title", "middle", 24),
        textLines(200, 204, screen.body, "body"),
        actionRow(screen, 255),
      ].join("");
    case "pairing":
      return [
        header,
        textLines(200, 103, screen.title, "title"),
        `<rect x="93" y="125" width="214" height="54" rx="17" fill="#0B0D0F" stroke="${tone}"/>`,
        text(200, 160, screen.code, "code", "middle"),
        textLines(200, 202, screen.body, "meta", "middle"),
        actionRow(screen, 247),
      ].join("");
    case "identity":
      return [
        header,
        `<rect x="180" y="83" width="40" height="29" rx="5" fill="none" stroke="${tone}" stroke-width="3"/><path d="M174 118h52" stroke="${tone}" stroke-width="3" stroke-linecap="round"/>`,
        textLines(200, 143, screen.title, "title"),
        textLines(200, 172, screen.body, "body", "middle", 17),
        actionRow(screen, 246),
      ].join("");
    case "status":
      return [
        header,
        statusMark(screen.tone, screen.layout),
        textLines(200, 153, screen.title, "title"),
        textLines(200, 181, screen.body, "body", "middle", 17),
        actionRow(screen, 251),
      ].join("");
    case "home":
      return [
        header,
        textLines(86, 103, screen.title, "title", "start"),
        `<circle cx="286" cy="108" r="25" fill="#17251D" stroke="${tone}"/>`,
        text(286, 115, screen.metric, "metric", "middle"),
        text(286, 142, screen.metricLabel, "meta", "middle"),
        renderListItems(screen, 158, 43),
        pill(116, 257, 168, "New task", "green", true),
      ].join("");
    case "list":
      return [
        header,
        textLines(200, 104, screen.title, "title"),
        renderListItems(screen, 127, screen.items?.length > 2 ? 39 : 46),
      ].join("");
    case "approval":
      return [
        header,
        `<rect x="151" y="79" width="98" height="23" rx="11.5" fill="#301719" stroke="${tone}"/>`,
        text(200, 95, "REMOTE WRITE", "risk", "middle"),
        textLines(200, 125, screen.title, "title"),
        `<rect x="78" y="145" width="244" height="44" rx="10" fill="#080A0B" stroke="#444A50"/>`,
        text(93, 172, screen.code, "mono"),
        textLines(200, 211, screen.body, "body"),
        actionRow(screen, 251),
      ].join("");
    case "choice":
      return [
        header,
        textLines(200, 104, screen.title, "title"),
        renderChoiceItems(screen, 126),
        actionRow(screen, 253),
      ].join("");
    case "timeline":
      return [
        header,
        textLines(200, 104, screen.title, "title"),
        `<path d="M104 132v96" stroke="#3E464C" stroke-width="2"/>`,
        ...(screen.items ?? []).map(([time, item], index) => {
          const y = 139 + index * 43;
          const current = index === screen.items.length - 1;
          return [
            `<circle cx="104" cy="${y}" r="${current ? 6 : 4}" fill="${current ? tone : "#687078"}"/>`,
            text(120, y - 2, time, "meta"),
            text(120, y + 13, item, "item"),
          ].join("");
        }),
        actionRow(screen, 259),
      ].join("");
    case "composer":
      return [
        header,
        textLines(200, 101, screen.title, "title"),
        `<rect x="78" y="126" width="244" height="91" rx="15" fill="#101315" stroke="#40474D"/>`,
        textLines(94, 153, screen.body, "composer-text", "start", 20),
        `<path d="M294 194v10h-10" fill="none" stroke="${tone}" stroke-width="2"/>`,
        actionRow(screen, 242),
      ].join("");
    case "record":
      return [
        header,
        `<circle cx="200" cy="150" r="58" fill="#211416" stroke="${tone}" stroke-width="2"/>`,
        `<circle cx="200" cy="150" r="35" fill="${tone}" fill-opacity=".16" stroke="${tone}" stroke-width="5"/>`,
        `<rect x="192" y="135" width="16" height="25" rx="8" fill="${tone}"/><path d="M185 151a15 15 0 0 0 30 0m-15 15v12m-10 0h20" fill="none" stroke="#F5F7F8" stroke-width="3" stroke-linecap="round"/>`,
        textLines(200, 225, screen.title, "title"),
        textLines(200, 248, screen.body, "mono", "middle"),
        actionRow(screen, 272),
      ].join("");
    case "review":
      return [
        header,
        textLines(200, 103, screen.title, "title"),
        `<rect x="77" y="124" width="246" height="92" rx="15" fill="#101615" stroke="${tone}" stroke-opacity=".55"/>`,
        `<path d="M95 145h16v4H99v12h-4z" fill="${tone}"/>`,
        textLines(200, 164, screen.body, "composer-text", "middle", 20),
        actionRow(screen, 243),
      ].join("");
    case "controls":
      return [
        header,
        textLines(200, 104, screen.title, "title"),
        renderListItems(screen, 132, 52),
        actionRow(screen, 252),
      ].join("");
    case "folders":
      return [
        header,
        textLines(200, 97, screen.title, "title"),
        textLines(200, 116, screen.body, "meta"),
        ...(screen.items ?? []).map(([label], index) => {
          const x = 86 + index * 78;
          return [
            `<path d="M${x} 153h21l7 7h35v42h-59z" fill="#1B2023" stroke="#576068"/>`,
            text(x + 29.5, 220, label, "meta", "middle"),
          ].join("");
        }),
        actionRow(screen, 249),
      ].join("");
    case "summary":
      return [
        header,
        textLines(200, 102, screen.title, "title"),
        `<rect x="81" y="124" width="238" height="113" rx="14" fill="#111619" stroke="#374047"/>`,
        ...(screen.items ?? []).map(([key, value], index) => {
          const y = 145 + index * 24;
          return [
            text(96, y, key.toUpperCase(), "meta"),
            text(304, y, value, "item", "end"),
          ].join("");
        }),
        actionRow(screen, 253),
      ].join("");
    case "settings":
      return [
        header,
        textLines(200, 102, screen.title, "title"),
        ...(screen.items ?? []).map(([key, value], index) => {
          const y = 134 + index * 38;
          const enabled = value === "Live" || value === "On";
          return [
            text(86, y + 15, key, "item"),
            enabled
              ? `<rect x="265" y="${y}" width="47" height="24" rx="12" fill="#1D432B" stroke="${tone}"/><circle cx="299" cy="${y + 12}" r="8" fill="${tone}"/>`
              : text(309, y + 15, value, "meta", "end"),
          ].join("");
        }),
        actionRow(screen, 253),
      ].join("");
    case "about":
      return [
        header,
        `<circle cx="200" cy="116" r="31" fill="#152129" stroke="${tone}" stroke-width="2"/><path d="M185 116h30m-15-15v30" stroke="${tone}" stroke-width="3" stroke-linecap="round"/>`,
        textLines(200, 166, screen.title, "title"),
        textLines(200, 192, screen.body, "meta", "middle", 17),
        actionRow(screen, 260),
      ].join("");
    default:
      throw new Error(`Unknown screen layout: ${screen.layout}`);
  }
}

function renderCard(screen, screenIndex, x, y) {
  return [
    `<g data-screen="${escapeXml(screen.name)}" transform="translate(${x} ${y})">`,
    `<rect width="400" height="400" rx="28" fill="#101315" stroke="#2F353A"/>`,
    `<path d="M18 38V18h20M362 18h20v20M18 362v20h20M362 382h20v-20" fill="none" stroke="#454C52" stroke-width="1.5"/>`,
    `<circle cx="200" cy="176" r="148" fill="#030405" stroke="#464D53" stroke-width="2" filter="url(#watchShadow)"/>`,
    `<circle cx="200" cy="176" r="139" fill="url(#watchFace)" stroke="#23282D"/>`,
    renderScreenContent(screen),
    text(28, 359, String(screenIndex + 1).padStart(2, "0"), "card-index"),
    text(66, 359, screen.label, "card-title"),
    text(66, 379, screen.name, "card-meta"),
    `<circle cx="366" cy="359" r="5" fill="${COLORS[screen.tone]}"/>`,
    `</g>`,
  ].join("");
}

function renderBoard(group, offset) {
  const columns = 3;
  const cardWidth = 400;
  const cardHeight = 400;
  const gapX = 24;
  const gapY = 22;
  const marginX = 36;
  const headerHeight = 132;
  const rows = Math.ceil(group.screens.length / columns);
  const width = 1320;
  const height = headerHeight + rows * cardHeight + (rows - 1) * gapY + 48;
  const titleId = `${group.file}-title`;
  const descriptionId = `${group.file}-description`;
  const cards = group.screens
    .map((screen, index) => {
      const column = index % columns;
      const row = Math.floor(index / columns);
      return renderCard(
        screen,
        offset + index,
        marginX + column * (cardWidth + gapX),
        headerHeight + row * (cardHeight + gapY),
      );
    })
    .join("");

  return `<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="${titleId} ${descriptionId}" viewBox="0 0 ${width} ${height}">
  <title id="${titleId}">${escapeXml(group.title)}</title>
  <desc id="${descriptionId}">${escapeXml(group.description)}</desc>
  <defs>
    <linearGradient id="boardBg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#080A0B"/>
      <stop offset="1" stop-color="#111619"/>
    </linearGradient>
    <radialGradient id="watchFace" cx=".34" cy=".22" r=".86">
      <stop offset="0" stop-color="#161A1D"/>
      <stop offset=".62" stop-color="#090B0D"/>
      <stop offset="1" stop-color="#030405"/>
    </radialGradient>
    <pattern id="hatch" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <path d="M0 0v8" stroke="#FFFFFF" stroke-opacity=".018" stroke-width="2"/>
    </pattern>
    <filter id="watchShadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="14" stdDeviation="14" flood-color="#000000" flood-opacity=".58"/>
    </filter>
    <style>
      text { font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: #F5F7F8; }
      .board-index { font: 800 42px ui-monospace, SFMono-Regular, Menlo, monospace; fill: #62E790; letter-spacing: -.06em; }
      .board-eyebrow { font-size: 12px; font-weight: 800; letter-spacing: .16em; fill: #8C949B; }
      .board-title { font-size: 30px; font-weight: 780; letter-spacing: -.025em; }
      .board-description { font-size: 14px; fill: #A2A8B0; }
      .eyebrow { font-size: 9px; font-weight: 800; letter-spacing: .14em; fill: #8F979E; }
      .hero-title { font-size: 22px; font-weight: 780; letter-spacing: -.03em; }
      .title { font-size: 17px; font-weight: 760; letter-spacing: -.025em; }
      .body { font-size: 11px; fill: #B6BDC3; }
      .meta { font-size: 8.5px; fill: #8F979E; letter-spacing: .02em; }
      .item { font-size: 10.5px; font-weight: 680; }
      .choice { font-size: 10px; font-weight: 650; }
      .pill { font-size: 8.5px; font-weight: 800; letter-spacing: .025em; }
      .code { font: 800 26px ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .14em; }
      .mono { font: 9.5px ui-monospace, SFMono-Regular, Menlo, monospace; fill: #F5F7F8; }
      .risk { font-size: 8px; font-weight: 850; letter-spacing: .1em; fill: #FF6B6B; }
      .metric { font-size: 20px; font-weight: 800; fill: #62E790; }
      .composer-text { font-size: 11px; font-weight: 550; fill: #E6E9EB; }
      .card-index { font: 750 12px ui-monospace, SFMono-Regular, Menlo, monospace; fill: #737B82; }
      .card-title { font-size: 13px; font-weight: 760; }
      .card-meta { font: 9px ui-monospace, SFMono-Regular, Menlo, monospace; fill: #737B82; }
    </style>
  </defs>
  <rect width="${width}" height="${height}" rx="30" fill="url(#boardBg)"/>
  <rect width="${width}" height="${height}" rx="30" fill="url(#hatch)"/>
  ${text(38, 61, group.index, "board-index")}
  ${text(122, 40, group.eyebrow, "board-eyebrow")}
  ${text(122, 75, group.title, "board-title")}
  ${text(122, 101, group.description, "board-description")}
  <path d="M1010 51h271" stroke="#30373C"/><path d="M1224 41l57 10-57 10" fill="none" stroke="#62E790" stroke-width="2"/>
  ${cards}
</svg>
`;
}

export async function generateReadmeScreenGallery({
  repoRoot = DEFAULT_REPO_ROOT,
  outputDir = join(repoRoot, "docs", "assets"),
} = {}) {
  const kotlinPath = join(
    repoRoot,
    "wear",
    "src",
    "main",
    "java",
    "dev",
    "ungaaaabungaaa",
    "relay",
    "domain",
    "RelayState.kt",
  );
  const kotlinSource = await readFile(kotlinPath, "utf8");
  const nativeScreens = extractNativeScreens(kotlinSource);
  validateCatalog(nativeScreens);
  await mkdir(outputDir, { recursive: true });

  let offset = 0;
  const files = [];

  for (const group of SCREEN_GROUPS) {
    await writeFile(join(outputDir, group.file), renderBoard(group, offset), "utf8");
    files.push(group.file);
    offset += group.screens.length;
  }

  return {
    screenCount: offset,
    files,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await generateReadmeScreenGallery();
  process.stdout.write(
    `Generated ${result.screenCount} Relay screen previews across ${result.files.length} boards.\n`,
  );
}
