import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPPreferencesWindowController)
public final class BPPreferencesWindowController: NSWindowController {
    @objc public var backgroundCheckCheckbox: NSButton?
    @objc public var intervalPopUp: NSPopUpButton?
    @objc public var greedyCheckbox: NSButton?
    @objc public var helperStatusLabel: NSTextField?
    @objc public var helperActionButton: NSButton?
    @objc public var preferencesHost: BPPreferencesHost?

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = NSLocalizedString("Preferences_Title", comment: "")
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildContentView()
    }

    private func buildContentView() {
        guard let content = window?.contentView else { return }

        let bgCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("Preferences_Background_Check", comment: ""),
            target: self,
            action: #selector(toggleBackgroundCheck(_:))
        )
        bgCheckbox.state = BPPreferences.backgroundCheckEnabled ? .on : .off
        self.backgroundCheckCheckbox = bgCheckbox

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        let intervals: [(String, Double)] = [
            (NSLocalizedString("Preferences_Interval_Hourly", comment: ""), 3600.0),
            (NSLocalizedString("Preferences_Interval_Six_Hours", comment: ""), 21600.0),
            (NSLocalizedString("Preferences_Interval_Daily", comment: ""), 86400.0)
        ]
        for (title, seconds) in intervals {
            popUp.addItem(withTitle: title)
            popUp.lastItem?.representedObject = NSNumber(value: seconds)
        }
        self.intervalPopUp = popUp
        selectIntervalItemMatchingPreference()
        popUp.target = self
        popUp.action = #selector(intervalChanged(_:))

        let greedy = NSButton(
            checkboxWithTitle: NSLocalizedString("Preferences_Greedy_Casks", comment: ""),
            target: self,
            action: #selector(toggleGreedy(_:))
        )
        greedy.state = BPPreferences.greedyCaskUpgrades ? .on : .off
        self.greedyCheckbox = greedy

        self.helperStatusLabel = NSTextField(wrappingLabelWithString: "")
        let actionBtn = NSButton(title: "", target: self, action: #selector(helperAction(_:)))
        actionBtn.bezelStyle = .rounded
        self.helperActionButton = actionBtn

        let host = BPPreferencesHost()
        host.onBackgroundCheckChanged = { [weak self] enabled in
            guard let self else { return }
            self.backgroundCheckCheckbox?.state = enabled ? .on : .off
            BPPreferences.backgroundCheckEnabled = enabled
            self.updateIntervalEnabled()
            self.syncSwiftUIHost()
        }
        host.onIntervalChanged = { [weak self] interval in
            guard let self else { return }
            BPPreferences.backgroundCheckInterval = interval
            self.selectIntervalItemMatchingPreference()
            self.syncSwiftUIHost()
        }
        host.onGreedyChanged = { [weak self] greedy in
            guard let self else { return }
            self.greedyCheckbox?.state = greedy ? .on : .off
            BPPreferences.greedyCaskUpgrades = greedy
            self.syncSwiftUIHost()
        }
        host.onAutomaticAppUpdateCheckChanged = { [weak self] enabled in
            guard let self else { return }
            BPPreferences.automaticAppUpdateCheckEnabled = enabled
            self.syncSwiftUIHost()
        }
        host.onShowMenuBarExtraChanged = { [weak self] enabled in
            guard let self else { return }
            BPPreferences.showMenuBarExtra = enabled
            bpSharedAppDelegate()?.updateMenuBarExtra()
            self.syncSwiftUIHost()
        }
        host.onCheckForAppUpdates = {
            bpSharedAppDelegate()?.checkForAppUpdates(nil)
        }
        host.onHelperAction = { [weak self] in
            self?.helperAction(nil)
        }
        self.preferencesHost = host

        let hostView = host.viewController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hostView)
        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: content.topAnchor),
            hostView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hostView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        updateIntervalEnabled()
        refreshHelperStatus()
    }

    @objc public func syncSwiftUIHost() {
        guard let host = preferencesHost else { return }
        let actionTitle = (helperActionButton?.isHidden == true) ? nil : helperActionButton?.title
        host.showMenuBarExtra = BPPreferences.showMenuBarExtra
        host.sync(
            backgroundCheckEnabled: BPPreferences.backgroundCheckEnabled,
            interval: BPPreferences.backgroundCheckInterval,
            greedy: BPPreferences.greedyCaskUpgrades,
            automaticAppUpdates: BPPreferences.automaticAppUpdateCheckEnabled,
            helperStatus: helperStatusLabel?.stringValue ?? "",
            helperActionTitle: actionTitle
        )
    }

    private func selectIntervalItemMatchingPreference() {
        guard let popUp = intervalPopUp else { return }
        let current = BPPreferences.backgroundCheckInterval
        for item in popUp.itemArray {
            if (item.representedObject as? NSNumber)?.doubleValue == current {
                popUp.select(item)
                return
            }
        }
        if popUp.numberOfItems > 1 {
            popUp.selectItem(at: 1)
        }
    }

    private func updateIntervalEnabled() {
        intervalPopUp?.isEnabled = (backgroundCheckCheckbox?.state == .on)
    }

    @objc public func refreshHelperStatus() {
        let state = bpSharedHelperRegistration()?.currentState() ?? 0
        helperStatusLabel?.stringValue = bpHelperRegistrationClass()?.localizedDescription(forState: state) ?? ""
        let offersLoginItems = bpHelperRegistrationClass()?.stateOffersLoginItemsShortcut(state) ?? false
        let offersInstall = (state == 0) // kBPHelperStateNotRegistered
        helperActionButton?.isHidden = !(offersLoginItems || offersInstall)
        helperActionButton?.title = offersLoginItems
            ? NSLocalizedString("Helper_Action_Open_Login_Items", comment: "")
            : NSLocalizedString("Helper_Action_Install", comment: "")
        syncSwiftUIHost()
    }

    @objc(helperAction:)
    public func helperAction(_ sender: Any?) {
        let state = bpSharedHelperRegistration()?.currentState() ?? 0
        if bpHelperRegistrationClass()?.stateOffersLoginItemsShortcut(state) == true {
            bpHelperRegistrationClass()?.openLoginItemsSettings()
        } else {
            var error: NSError?
            _ = bpSharedHelperRegistration()?.registerReturningError(&error)
        }
        refreshHelperStatus()
    }

    @objc(toggleBackgroundCheck:)
    public func toggleBackgroundCheck(_ sender: Any?) {
        BPPreferences.backgroundCheckEnabled = (backgroundCheckCheckbox?.state == .on)
        updateIntervalEnabled()
        syncSwiftUIHost()
    }

    @objc(intervalChanged:)
    public func intervalChanged(_ sender: Any?) {
        if let interval = intervalPopUp?.selectedItem?.representedObject as? NSNumber {
            BPPreferences.backgroundCheckInterval = interval.doubleValue
        }
        syncSwiftUIHost()
    }

    override public func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshHelperStatus()
    }

    @objc(toggleGreedy:)
    public func toggleGreedy(_ sender: Any?) {
        BPPreferences.greedyCaskUpgrades = (greedyCheckbox?.state == .on)
        syncSwiftUIHost()
    }
}

