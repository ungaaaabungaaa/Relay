# Relay Native Menu-Bar UI Design

**Date:** 2026-07-27
**Status:** Approved visual direction

## Goal

Replace Relay's dashboard window with a compact macOS menu-bar app. The UFO icon
sits beside the user's other menu-bar items. Selecting it opens a standard macOS
menu like ChatGPT or Amphetamine.

## Product boundary

Relay has no dashboard, settings, or utility window. Every Relay screen uses a
native menu, submenu, system picker, or macOS confirmation alert. System folder
and credential pickers may appear when macOS requires them.

This change affects presentation and navigation. It does not change Relay's
bridge, cloud connection, encryption, pairing rules, Codex controls, workspace
permissions, voice processing, or destructive-action safeguards.

## Apple components

Use `MenuBarExtra` with `.menu` style. Compose the interface from `Menu`,
`Button`, `Toggle`, `Divider`, `Label`, keyboard shortcuts, SF Symbols, and
system confirmation alerts. Use macOS menu spacing, typography, selection,
material, disabled states, and submenu arrows.

Do not draw custom popover cards, headers, glass panels, buttons, row backgrounds,
or navigation controls. The UFO remains the menu-bar label. Menu items use plain
text unless an SF Symbol improves recognition.

## Root menu

The root menu contains these groups:

1. Relay status with a short Codex connection detail.
2. Pending Actions, Apple Watch, and Workspaces submenus.
3. Relay Cloud, Voice and Transcription, and Start Relay at Login.
4. Diagnostics, Check for Updates, and About Relay.
5. Emergency Stop and Quit Relay.

The status row does not act as a button. `Pending Actions` shows its count and
appears disabled when no action needs attention. `Quit Relay` uses Command-Q.

## Pending Actions

The submenu lists approvals and questions with one line of context. Selecting an
item opens its decision submenu. Relay shows Approve, Deny, or the exact options
provided by Codex. Dangerous approvals retain their second confirmation.

The submenu may offer `Open on Apple Watch` when a paired Watch is online.

## Apple Watch

An unpaired Watch submenu shows `Start Pairing`. During pairing it shows the
six-character code, expiry time, Copy Pairing Code, and Cancel Pairing.

When the Watch submits a request, Relay shows both fingerprints and Approve and
Deny actions. A paired Watch submenu shows its name, connection state, last-seen
time, and Revoke Watch. Revocation keeps its confirmation.

## Workspaces

The submenu lists allowed folders with the active folder checked. It provides
Add Workspace through the standard macOS folder picker, Reveal in Finder, and a
confirmed Remove action. Relay never displays folders outside the allowlist.

## Relay Cloud

The submenu shows connection state and the signed-in account. It provides
Connect Automatically, Reconnect Now, Sign Out, and Delete Relay Account.
Account deletion keeps its destructive confirmation and consequence copy.

## Voice and Transcription

The submenu provides Enable Voice from Watch, provider selection, API-key state,
Update API Key, and Remove API Key. macOS stores the key in Keychain. The menu
does not display any part of the secret.

## Settings and maintenance

Start Relay at Login remains available from the root menu. Diagnostics shows the
local bridge, Codex, Relay Cloud, and Apple Watch states. It provides Refresh and
Copy Safe Diagnostics. Copied diagnostics exclude secrets, identifiers, paths,
and task content.

Updates and About show the installed version, update state, Check Again, Privacy
Policy, Support, and Licenses.

## Emergency Stop

Emergency Stop opens a standard macOS alert. The alert explains that Relay will
disconnect the Watch and stop remote Codex control while leaving local Codex work
open. The user chooses Cancel or Emergency Stop.

## Accessibility

The UFO announces `Relay`. Menu items use native keyboard navigation and system
focus. Each status pairs text with any symbol or color. Dynamic text and system
contrast remain under macOS control.

## Acceptance criteria

- Relay opens no dashboard or settings window.
- The UFO opens a standard anchored macOS menu.
- Every existing Mac control remains reachable from the root or one submenu.
- Pairing, approval, account deletion, revocation, and Emergency Stop retain
  their security confirmations.
- The menu works with keyboard navigation, VoiceOver, light appearance, and dark
  appearance.
- Existing Mac tests pass, with new navigation tests covering the menu structure.
