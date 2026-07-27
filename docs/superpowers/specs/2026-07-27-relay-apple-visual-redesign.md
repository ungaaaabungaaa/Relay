# Relay Apple Visual Redesign

**Date:** 2026-07-27
**Status:** Approved direction; implementation contract

## Goal

Give Relay one calm, native Apple identity across the macOS app, macOS menu bar,
and Apple Watch app without changing pairing, cloud transport, security, or Codex
control behavior.

## Approved identity

Relay uses a white and brushed-silver UFO on a graphite-black field. The mark is
original and contains no OpenAI or Codex logo geometry. The production app icon
uses the approved dimensional artwork. Small controls and the menu bar use a
simplified monochrome UFO glyph so they remain legible at 16 to 24 points.

The UFO has no colored beam. System blue is reserved for the current primary
action, selection, focus, and links. Green and mint are not brand colors. Health
is communicated with text, shape, and system status semantics rather than a
persistent green identity.

## Design language

- Use standard SwiftUI navigation, buttons, lists, labels, forms, materials, and
  typography before custom containers.
- Prefer graphite, system backgrounds, separators, and restrained materials.
- Use system blue sparingly for interactive emphasis.
- Use yellow or orange only for attention and red only for destructive states.
- Keep copy short, literal, and operational.
- Avoid decorative gradients, oversized rounded cards, uppercase eyebrows, and
  dense status-pill decoration.
- Preserve Dynamic Type, VoiceOver labels, keyboard navigation on Mac, and
  44-point Watch targets.

## macOS app

The dashboard remains a native `NavigationSplitView`. Its sidebar header shows
the UFO glyph and Relay name. The bottom status area presents one compact bridge
state with a symbol and text. Detail pages use a consistent title, one-sentence
description, native grouped sections, and system spacing.

Reusable panels become subtle system-material groups with 12-point corners and
light separators. Setup states use numbered or checkmarked circles without
mint fills. Ready states use neutral checkmarks and clear text. Primary actions
use system-blue bordered-prominent buttons.

The macOS app icon is the approved white/silver UFO artwork on graphite. The
menu-bar item uses the simplified monochrome UFO silhouette as a template-style
glyph, not the full shaded app artwork. Status changes do not replace the UFO;
they appear in the menu content so the product remains recognizable.

## Apple Watch app

The Watch app stays shallow and glanceable. Pairing opens with the monochrome UFO
glyph, `Pair with Mac`, one short instruction, the six-character field, and one
primary action. Fingerprint confirmation uses a shield and monospaced values.

Inbox and task screens retain their existing information architecture and real
model data. Styling changes to native black backgrounds, system typography,
blue primary actions, neutral dividers, and concise offline or error treatments.
Dangerous approvals remain red and require the existing confirmation flow.

The Watch app icon uses the same approved artwork as the Mac app. The internal
glyph omits shading so it stays readable on the smallest supported display.

## Scope boundary

This pass does not alter cloud protocols, authentication, encryption, pairing
state, Codex routing, permissions, offline behavior, task semantics, or release
signing. It does not add an iPhone app or Codex plugin.

## Verification

- Mac and Watch unit suites pass.
- The Watch Xcode project builds for the installed simulator and generic watchOS
  destination without signing where supported.
- Asset catalogs contain valid 1024-point app icon sources.
- Source checks find no remaining mint brand styling.
- The Mac app launches with the UFO menu-bar label.
- The Watch pairing screen renders in the simulator without clipping.
- Existing local Xcode scheme and workspace state remains untouched.
