import AppKit

@MainActor
final class RelayStatusItemController: NSObject, NSMenuDelegate {
    private let model: RelayAppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var actionTargets: [RelayMenuActionTarget] = []

    init(model: RelayAppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        super.init()

        configureStatusButton()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }

        guard let image = Bundle.main
            .url(forResource: "RelayMenuBarIcon", withExtension: "svg")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(
                systemSymbolName: "visionpro",
                accessibilityDescription: "Relay"
            )
        else { return }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        button.image = image
        button.imagePosition = .imageOnly
        button.setAccessibilityTitle("Relay")
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        actionTargets.removeAll()
        precondition(!RelayMenuStructure.root.isEmpty)

        for row in RelayMenuPresentation.statusRows(
            bridgeState: model.bridgeState,
            codexStatus: model.codexStatus,
            cloudPhase: model.cloudTunnelPhase,
            activeDeviceCount: model.activeDeviceCount
        ) {
            menu.addItem(disabledItem(row))
        }
        if let error = model.lastError {
            menu.addItem(disabledItem(error))
        }

        menu.addItem(.separator())
        menu.addItem(submenuItem("Pending Actions", menu: buildPendingActionsMenu()))
        menu.addItem(submenuItem("Apple Watch", menu: buildWatchMenu()))
        menu.addItem(submenuItem("Workspaces", menu: buildWorkspacesMenu()))
        menu.addItem(.separator())
        menu.addItem(submenuItem("Relay Cloud", menu: buildCloudMenu()))
        menu.addItem(submenuItem("Voice and Transcription", menu: buildVoiceMenu()))
        menu.addItem(actionItem(
            "Start Relay at Login",
            state: model.startAtLogin ? .on : .off
        ) {
            self.model.setStartAtLogin(!self.model.startAtLogin)
        })
        menu.addItem(.separator())
        menu.addItem(submenuItem("Diagnostics", menu: buildDiagnosticsMenu()))
        menu.addItem(submenuItem("Updates", menu: buildUpdatesMenu()))
        menu.addItem(submenuItem("About", menu: buildAboutMenu()))
        menu.addItem(.separator())
        menu.addItem(actionItem("Emergency Stop…") {
            guard RelayMenuDialogs.confirm(.emergencyStop) else { return }
            Task { await self.model.emergencyStop() }
        })
        menu.addItem(actionItem("Quit Relay", keyEquivalent: "q") {
            Task {
                await self.model.quit()
                NSApplication.shared.terminate(nil)
            }
        })
    }

    private func buildPendingActionsMenu() -> NSMenu {
        makeMenu([
            disabledItem("\(model.pendingActionCount) waiting actions"),
            disabledItem("Review on Apple Watch"),
        ])
    }

    private func buildWatchMenu() -> NSMenu {
        let watchMenu = makeMenu()
        watchMenu.addItem(actionItem(
            "Start Secure Pairing",
            enabled: RelayMenuPresentation.canStartSecurePairing(
                cloudConnected: model.cloudConnected,
                bridgeState: model.bridgeState
            )
        ) {
            Task { await self.model.createSecurePairingSession() }
        })
        watchMenu.addItem(disabledItem("Mac fingerprint \(pairingMacFingerprint)"))

        if let session = model.cloudPairingSession {
            watchMenu.addItem(disabledItem("Code \(session.code)"))
            watchMenu.addItem(disabledItem(
                RelayMenuPresentation.pairingExpiryLabel(expiresAt: session.expiresAt)
            ))
            watchMenu.addItem(actionItem("Copy Pairing Code") {
                RelayMenuDialogs.copyText(session.code)
            })
        }

        watchMenu.addItem(actionItem("Refresh Pending Requests") {
            Task { await self.model.refreshPendingPairings() }
        })

        if model.pendingPairings.isEmpty {
            watchMenu.addItem(disabledItem("No pending requests"))
        } else {
            let canResolve = RelayMenuPresentation.canResolvePairing(
                cloudPhase: model.cloudTunnelPhase,
                bridgeState: model.bridgeState
            )
            for pairing in model.pendingPairings {
                let pairingMenu = makeMenu([
                    disabledItem("Fingerprint \(pairing.fingerprint)"),
                    disabledItem(
                        RelayMenuPresentation.pairingExpiryLabel(expiresAt: pairing.expiresAt)
                    ),
                    actionItem("Approve", enabled: canResolve) {
                        Task { await self.model.approvePairing(pairing) }
                    },
                    actionItem("Deny", enabled: canResolve) {
                        guard RelayMenuDialogs.confirm(
                            title: "Deny \(pairing.name)?",
                            message: "This pending watch request will not receive Relay access.",
                            confirmationLabel: "Deny request"
                        ) else { return }
                        Task { await self.model.denyPairing(pairing) }
                    },
                ])
                watchMenu.addItem(submenuItem(pairing.name, menu: pairingMenu))
            }
        }

        let activeDevices = model.devices.filter { $0.revokedAt == nil }
        if activeDevices.isEmpty {
            watchMenu.addItem(disabledItem("No paired watches"))
        } else {
            watchMenu.addItem(.separator())
            for device in activeDevices {
                let deviceMenu = makeMenu([
                    disabledItem("Fingerprint \(device.fingerprint)"),
                    actionItem(
                        "Revoke…",
                        enabled: model.revocationDecision(for: device) != .blocked
                    ) {
                        guard RelayMenuDialogs.confirm(.revokeWatch(device)) else { return }
                        Task { await self.model.revoke(device) }
                    },
                ])
                watchMenu.addItem(submenuItem(device.name, menu: deviceMenu))
            }
        }
        return watchMenu
    }

    private func buildWorkspacesMenu() -> NSMenu {
        let workspacesMenu = makeMenu()
        if model.workspaces.isEmpty {
            workspacesMenu.addItem(disabledItem("No allowed folders"))
        } else {
            for root in model.workspaces {
                let workspaceMenu = makeMenu([
                    actionItem("Reveal in Finder") {
                        RelayMenuDialogs.revealInFinder(root)
                    },
                    actionItem("Copy Path") {
                        RelayMenuDialogs.copyText(root)
                    },
                    actionItem("Remove…") {
                        let name = RelayMenuPresentation.workspaceDisplayName(root)
                        guard RelayMenuDialogs.confirm(
                            title: "Remove \(name)?",
                            message: "Relay will no longer offer this folder for new work.",
                            confirmationLabel: "Remove folder"
                        ) else { return }
                        Task {
                            await self.model.replaceWorkspaces(
                                self.model.workspaces.filter { $0 != root }
                            )
                        }
                    },
                ])
                workspacesMenu.addItem(submenuItem(
                    RelayMenuPresentation.workspaceDisplayName(root),
                    menu: workspaceMenu
                ))
            }
        }
        workspacesMenu.addItem(.separator())
        workspacesMenu.addItem(actionItem("Add Folder…") {
            guard let root = RelayMenuDialogs.chooseWorkspace() else { return }
            Task {
                await self.model.replaceWorkspaces(
                    Array(Set(self.model.workspaces + [root])).sorted()
                )
            }
        })
        return workspacesMenu
    }

    private func buildCloudMenu() -> NSMenu {
        let cloudMenu = makeMenu([
            disabledItem(RelayMenuPresentation.cloudLabel(model.cloudTunnelPhase)),
            disabledItem("Environment \(model.cloudEnvironmentName)"),
        ])
        if model.cloudSignedIn {
            cloudMenu.addItem(actionItem("Reconnect") {
                Task { await self.model.reconnectRelay() }
            })
            cloudMenu.addItem(actionItem("Sign Out") {
                Task { await self.model.signOutOfRelayCloud() }
            })
            cloudMenu.addItem(actionItem("Delete Relay Cloud Account…") {
                guard RelayMenuDialogs.confirm(.deleteAccount) else { return }
                Task { await self.model.deleteRelayAccount() }
            })
        } else {
            cloudMenu.addItem(actionItem("Sign In…") {
                guard let email = RelayMenuDialogs.requestEmail() else { return }
                self.model.signInToRelayCloud(email: email)
            })
        }
        if model.cloudLoginInProgress {
            cloudMenu.addItem(actionItem("Cancel Sign-In") {
                self.model.cancelRelayCloudLogin()
            })
        }
        return cloudMenu
    }

    private func buildVoiceMenu() -> NSMenu {
        let voiceMenu = makeMenu([
            disabledItem(
                model.voiceConfigured
                    ? "OpenAI key configured in Keychain"
                    : "OpenAI key not configured"
            ),
        ])
        if model.voiceConfigured {
            voiceMenu.addItem(actionItem("Replace OpenAI API Key…") {
                guard let key = RelayMenuDialogs.requestOpenAIKey() else { return }
                Task { await self.model.saveOpenAIKey(key) }
            })
            voiceMenu.addItem(actionItem("Remove OpenAI API Key") {
                guard RelayMenuDialogs.confirm(
                    title: "Remove OpenAI API key?",
                    message: "Voice transcription will be unavailable until you set a new key.",
                    confirmationLabel: "Remove key"
                ) else { return }
                Task { await self.model.saveOpenAIKey("") }
            })
        } else {
            voiceMenu.addItem(actionItem("Set OpenAI API Key…") {
                guard let key = RelayMenuDialogs.requestOpenAIKey() else { return }
                Task { await self.model.saveOpenAIKey(key) }
            })
        }
        return voiceMenu
    }

    private func buildDiagnosticsMenu() -> NSMenu {
        makeMenu([
            disabledItem("Only allowlisted operational status is copied."),
            actionItem("Refresh") {
                Task {
                    await self.model.updateSupervisorSnapshot()
                    await self.model.refresh()
                }
            },
            actionItem("Copy Safe Diagnostics") {
                RelayMenuDialogs.copyText(
                    RelayMenuPresentation.safeDiagnostic(
                        bridgeState: self.model.bridgeState,
                        cloudPhase: self.model.cloudTunnelPhase,
                        activeDeviceCount: self.model.activeDeviceCount,
                        voiceConfigured: self.model.voiceConfigured
                    )
                )
            },
        ])
    }

    private func buildUpdatesMenu() -> NSMenu {
        makeMenu([
            disabledItem(RelayMenuPresentation.updateLabel(model.updateController.state)),
            actionItem("Check Again…") {
                self.model.updateController.checkForUpdates()
            },
        ])
    }

    private func buildAboutMenu() -> NSMenu {
        makeMenu([
            disabledItem("Relay for Apple Watch"),
            disabledItem("Relay Mac \(RelayMenuPresentation.appVersion())"),
            actionItem("Open Relay Website") {
                RelayMenuDialogs.openURL(URL(string: "https://relayforcodex.com")!)
            },
            actionItem("Privacy Policy") {
                RelayMenuDialogs.openURL(RelayMenuPresentation.privacyPolicyURL)
            },
            actionItem("Support") {
                RelayMenuDialogs.openURL(RelayMenuPresentation.supportURL)
            },
            actionItem("Licenses") {
                RelayMenuDialogs.openURL(RelayMenuPresentation.licensesURL)
            },
        ])
    }

    private var pairingMacFingerprint: String {
        RelayMenuPresentation.pairingMacFingerprint(
            sessionFingerprint: model.cloudPairingSession?.macFingerprint,
            hostFingerprint: model.hostFingerprint
        )
    }

    private func makeMenu(_ items: [NSMenuItem] = []) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        return menu
    }

    private func submenuItem(_ title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(
        _ title: String,
        enabled: Bool = true,
        state: NSControl.StateValue = .off,
        keyEquivalent: String = "",
        handler: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let target = RelayMenuActionTarget(handler)
        let item = NSMenuItem(
            title: title,
            action: #selector(RelayMenuActionTarget.invoke),
            keyEquivalent: keyEquivalent
        )
        item.target = target
        item.isEnabled = enabled
        item.state = state
        actionTargets.append(target)
        return item
    }
}

@MainActor
private final class RelayMenuActionTarget: NSObject {
    let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}
