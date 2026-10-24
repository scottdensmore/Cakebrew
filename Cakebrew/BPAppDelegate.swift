import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@objc(BPBrewfileImporting)
public protocol BPBrewfileImporting: NSObjectProtocol {
    @objc(importBrewfileAtURL:)
    func importBrewfile(at url: URL)
}

@objc(BPNotificationNavigationAction)
public enum BPNotificationNavigationAction: UInt, Sendable {
    case none = 0
    case outdatedFormulae = 1
    case outdatedCasks = 2
    case unifiedUpdates = 3
}

@objc(BPNotificationNavigation)
public protocol BPNotificationNavigation: NSObjectProtocol {
    @objc(showOutdatedFormulae:)
    func showOutdatedFormulae(_ sender: Any?)
    @objc(showOutdatedCasks:)
    func showOutdatedCasks(_ sender: Any?)
    @objc(showUnifiedUpdates:)
    func showUnifiedUpdates(_ sender: Any?)
}

@objc(BPNotificationPresenting)
public protocol BPNotificationPresenting: NSObjectProtocol {
    @objc func cleanupNotificationAlerts()
    @objc func activateCakebrewIgnoringOtherApps()
    @objc func showMainWindow()
}

@objc private protocol BPNotificationResponseMessaging: NSObjectProtocol {
    @objc optional func notification() -> AnyObject?
    @objc optional func request() -> AnyObject?
    @objc optional func content() -> AnyObject?
    @objc optional func userInfo() -> NSDictionary?
}

@objc private protocol BPTaggedSenderMessaging: NSObjectProtocol {
    @objc optional var tag: Int { get }
}

private func bpExtractNotificationUserInfo(from response: Any?) -> [AnyHashable: Any]? {
    guard let obj = response as AnyObject? else { return nil }
    let r1 = unsafeBitCast(obj, to: BPNotificationResponseMessaging.self)
    guard let notif = r1.notification?() else { return nil }
    let r2 = unsafeBitCast(notif, to: BPNotificationResponseMessaging.self)
    guard let req = r2.request?() else { return nil }
    let r3 = unsafeBitCast(req, to: BPNotificationResponseMessaging.self)
    guard let cont = r3.content?() else { return nil }
    let r4 = unsafeBitCast(cont, to: BPNotificationResponseMessaging.self)
    return r4.userInfo?() as? [AnyHashable: Any]
}

private let bpSIGTERMHandler: @convention(c) (Int32) -> Void = { sig in
    if sig == SIGTERM {
        bpSharedHomebrewManager()?.cleanUp()
    }
    Darwin.signal(sig, SIG_DFL)
}

@objc(BPAppDelegate)
public final class BPAppDelegate: NSObject, NSApplicationDelegate, BPNotificationPresenting, @unchecked Sendable {
    public static let homebrewWebsiteURLString = "https://www.cakebrew.com"
    public static let cakebrewDocumentationURLString = "https://github.com/scottdensmore/Cakebrew#readme"
    public static let cakebrewReleasesURLString = "https://github.com/scottdensmore/Cakebrew/releases"

    @IBOutlet @objc public var window: NSWindow?
    @objc public weak var dockActionTarget: (any BPDockMenuTarget)?

    private weak var _brewfileImportTarget: (any BPBrewfileImporting)?
    @objc public var brewfileImportTarget: (any BPBrewfileImporting)? {
        get { _brewfileImportTarget }
        set {
            _brewfileImportTarget = newValue
            if let target = newValue, let pending = pendingBrewfileURL {
                pendingBrewfileURL = nil
                target.importBrewfile(at: pending)
            }
        }
    }

    private weak var _notificationNavigationTarget: (any BPNotificationNavigation)?
    @objc public var notificationNavigationTarget: (any BPNotificationNavigation)? {
        get { _notificationNavigationTarget }
        set {
            #if DEBUG
            if newValue != nil && _notificationNavigationTarget == nil {
                queueMockNotificationBeforeTargetRegistration()
            }
            #endif
            _notificationNavigationTarget = newValue
            let pending = pendingNotificationNavigationAction
            if newValue != nil && pending != .none {
                pendingNotificationNavigationAction = .none
                navigate(forNotificationAction: pending)
            }
        }
    }

    private var _notificationPresenter: (any BPNotificationPresenting)?
    @objc public var notificationPresenter: any BPNotificationPresenting {
        get { _notificationPresenter ?? self }
        set { _notificationPresenter = newValue }
    }

    private var _runningBackgroundTask: Bool = false
    @objc public var runningBackgroundTask: Bool {
        @objc(isRunningBackgroundTask) get { _runningBackgroundTask }
        @objc(setRunningBackgroundTask:) set { _runningBackgroundTask = newValue }
    }

    @objc public private(set) var statusItem: NSStatusItem?

    private var preferencesWindowController: BPPreferencesWindowController?
    private var backgroundUpdater: BPBackgroundUpdater?
    private var appUpdateHost: BPAppUpdateHost?
    private var _aboutWindowController: DCOAboutWindowController?
    private var pendingBrewfileURL: URL?
    private var pendingNotificationNavigationAction: BPNotificationNavigationAction = .none
    #if DEBUG
    private var didQueueMockNotification: Bool = false
    #endif

    public override init() {
        super.init()
        if let proto = NSProtocolFromString("UNUserNotificationCenterDelegate") {
            class_addProtocol(BPAppDelegate.self, proto)
        }
    }

    @MainActor
    private var aboutWindowController: DCOAboutWindowController {
        if let existing = _aboutWindowController {
            return existing
        }
        let controller = DCOAboutWindowController()
        controller.appWebsiteURL = URL(string: Self.homebrewWebsiteURLString)
        _aboutWindowController = controller
        return controller
    }

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        BPPreferences.registerDefaults()
        setupSignalHandler()

        MainActor.assumeIsolated {
            if let appMenu = NSApp.mainMenu?.items.first?.submenu {
                _ = BPAppDelegate.installCheckForUpdatesMenuItem(inApplicationMenu: appMenu, target: self)
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updatesSnapshotDidChangeForMenuBar(_:)),
                name: Notification.Name("BPHomebrewManagerUpdatesSnapshotDidChangeNotification"),
                object: nil
            )
            self.updateMenuBarExtra()
        }

        let updater = BPBackgroundUpdater()
        self.backgroundUpdater = updater
        updater.start()

        bpSharedHomebrewManager()?.reloadFromInterface(rebuildingCache: false)
        UNUserNotificationCenter.current().delegate = unsafeBitCast(self, to: UNUserNotificationCenterDelegate.self)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated {
                self.window?.makeKeyAndOrderFront(self)
            }
        }
        cleanupTaskAlerts()
        return true
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let brewfile = BPBrewfile.brewfileURLs(from: urls).first else {
            MainActor.assumeIsolated {
                self.displayBrewfileNotRecognized(forURLs: urls)
            }
            return
        }
        guard let target = brewfileImportTarget else {
            pendingBrewfileURL = brewfile
            return
        }
        target.importBrewfile(at: brewfile)
    }

    @objc(notificationNavigationActionForUserInfo:)
    public static func notificationNavigationAction(forUserInfo userInfo: [AnyHashable: Any]?) -> BPNotificationNavigationAction {
        guard let target = userInfo?[BPBackgroundUpdater.outdatedNotificationTargetKey] as? String else {
            return .none
        }
        if target == BPBackgroundUpdater.outdatedNotificationTargetFormulae {
            return .outdatedFormulae
        }
        if target == BPBackgroundUpdater.outdatedNotificationTargetCasks {
            return .outdatedCasks
        }
        if target == BPBackgroundUpdater.outdatedNotificationTargetMixed {
            return .unifiedUpdates
        }
        return .none
    }

    @objc(navigateForNotificationUserInfo:)
    public func navigate(forNotificationUserInfo userInfo: [AnyHashable: Any]?) {
        let action = Self.notificationNavigationAction(forUserInfo: userInfo)
        guard action != .none else { return }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.navigate(forNotificationAction: action)
            }
            return
        }
        navigate(forNotificationAction: action)
    }

    #if DEBUG
    private func queueMockNotificationBeforeTargetRegistration() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !didQueueMockNotification,
              arguments.contains("-BPMockBrew"),
              let targetIndex = arguments.firstIndex(of: "-BPMockNotificationTarget"),
              targetIndex + 1 < arguments.count else {
            return
        }
        didQueueMockNotification = true
        navigate(forNotificationUserInfo: [
            BPBackgroundUpdater.outdatedNotificationTargetKey: arguments[targetIndex + 1]
        ])
    }
    #endif

    private func navigate(forNotificationAction action: BPNotificationNavigationAction) {
        guard let target = notificationNavigationTarget else {
            pendingNotificationNavigationAction = action
            return
        }
        switch action {
        case .outdatedFormulae:
            target.showOutdatedFormulae(self)
        case .outdatedCasks:
            target.showOutdatedCasks(self)
        case .unifiedUpdates:
            target.showUnifiedUpdates(self)
        case .none:
            break
        @unknown default:
            break
        }
    }

    public func cleanupNotificationAlerts() {
        cleanupTaskAlerts()
    }

    public func activateCakebrewIgnoringOtherApps() {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func showMainWindow() {
        MainActor.assumeIsolated {
            self.window?.makeKeyAndOrderFront(self)
        }
    }

    @MainActor
    private func displayBrewfileNotRecognized(forURLs urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Brewfile_Not_Recognized_Title", comment: "")
        alert.informativeText = String.localizedStringWithFormat(
            NSLocalizedString("Brewfile_Not_Recognized_Body", comment: ""),
            urls.first?.lastPathComponent ?? ""
        )
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let target = self.dockActionTarget
        let enabled = (target?.isHomebrewInstalled() == true)
            && !Self.shouldBlockOperation(whileRunningBackgroundTask: self.runningBackgroundTask)
        return BPDockMenu.dockMenu(withTarget: self, enabled: enabled)
    }

    @objc(performDockMenuAction:)
    public func performDockMenuAction(_ sender: Any?) {
        let tag = (sender as AnyObject?).flatMap { unsafeBitCast($0, to: BPTaggedSenderMessaging.self).tag } ?? 0
        guard let item = BPDockMenuItem(rawValue: tag),
              let action = BPDockMenu.controllerAction(for: item),
              let target = dockActionTarget as AnyObject?,
              target.responds(to: action) else {
            return
        }
        MainActor.assumeIsolated {
            NSApp.activate()
            self.window?.makeKeyAndOrderFront(self)
        }
        _ = target.perform(action, with: sender)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        bpSharedHomebrewManager()?.cleanUp()
        return .terminateNow
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func cleanupTaskAlerts() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        MainActor.assumeIsolated {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    @objc public static func urlForApplicationSupportFolder() -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let path = base.appendingPathComponent("Cakebrew/")
            try FileManager.default.createDirectory(
                atPath: path.relativePath,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return path
        } catch {
            return nil
        }
    }

    @objc public static func urlForApplicationCachesFolder() -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let path = base.appendingPathComponent("com.brunophilipe.Cakebrew/")
            try FileManager.default.createDirectory(
                atPath: path.relativePath,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return path
        } catch {
            NSLog("Error creating Cakebrew cache directory: %@", "\(error)")
            return nil
        }
    }

    @objc public func displayBackgroundWarning() {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Message_BGTask_Title", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
            alert.informativeText = NSLocalizedString("Message_BGTask_Body", comment: "")
            if let window = self.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    @objc(requestUserAttentionWithMessageTitle:andDescription:)
    public func requestUserAttention(withMessageTitle title: String, andDescription desc: String) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared.requestUserAttention(.informationalRequest)
            if !NSApplication.shared.isActive {
                NSApplication.shared.dockTile.badgeLabel = "●"
            }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = desc
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Error scheduling notification: %@", error as NSError)
            }
        }
    }

    @objc(showAboutWindow:)
    public func showAboutWindow(_ sender: Any?) {
        nonisolated(unsafe) let senderObj = sender
        MainActor.assumeIsolated {
            let about = self.aboutWindowController
            about.showWindow(senderObj)
            about.window?.becomeFirstResponder()
        }
    }

    @objc(openPreferences:)
    public func openPreferences(_ sender: Any?) {
        nonisolated(unsafe) let senderObj = sender
        MainActor.assumeIsolated {
            if self.preferencesWindowController == nil {
                let prefs = BPPreferencesWindowController()
                prefs.window?.center()
                self.preferencesWindowController = prefs
            }
            self.preferencesWindowController?.showWindow(senderObj)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @discardableResult
    @objc(installCheckForUpdatesMenuItemInApplicationMenu:target:)
    public static func installCheckForUpdatesMenuItem(inApplicationMenu appMenu: NSMenu?, target: AnyObject?) -> NSMenuItem? {
        guard let appMenu else { return nil }
        let action = #selector(BPAppDelegate.checkForAppUpdates(_:))
        let existingIndex = appMenu.indexOfItem(withTarget: target, andAction: action)
        if existingIndex >= 0 {
            return appMenu.item(at: existingIndex)
        }
        let title = Bundle.main.localizedString(
            forKey: "App_Update_Menu_Item",
            value: "Check for Updates…",
            table: nil
        )
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.setAccessibilityIdentifier("menu.app.checkForUpdates")
        let insertIndex = appMenu.numberOfItems > 1 ? 1 : appMenu.numberOfItems
        appMenu.insertItem(item, at: insertIndex)
        return item
    }

    @discardableResult
    @objc(installCommandPaletteMenuItemInToolsMenu:target:)
    public static func installCommandPaletteMenuItem(inToolsMenu toolsMenu: NSMenu?, target: AnyObject?) -> NSMenuItem? {
        guard let toolsMenu else { return nil }
        let action = NSSelectorFromString("showCommandPalette:")
        let existingIndex = toolsMenu.indexOfItem(withTarget: target, andAction: action)
        if existingIndex >= 0 {
            return toolsMenu.item(at: existingIndex)
        }
        let title = Bundle.main.localizedString(
            forKey: "Command_Palette_Menu_Item",
            value: "Command Palette…",
            table: nil
        )
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "k")
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        item.setAccessibilityIdentifier("menu.tools.commandPalette")
        toolsMenu.insertItem(item, at: 0)
        if toolsMenu.numberOfItems > 1, toolsMenu.item(at: 1)?.isSeparatorItem == false {
            toolsMenu.insertItem(NSMenuItem.separator(), at: 1)
        }
        return item
    }

    @objc(updatesSnapshotDidChangeForMenuBar:)
    public func updatesSnapshotDidChangeForMenuBar(_ notification: Notification) {
        if statusItem != nil {
            updateMenuBarExtra()
        }
    }

    @objc public func updateMenuBarExtra() {
        MainActor.assumeIsolated {
            if !BPPreferences.showMenuBarExtra {
                if let item = self.statusItem {
                    NSStatusBar.system.removeStatusItem(item)
                    self.statusItem = nil
                }
                return
            }

            if self.statusItem == nil {
                self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            }

            let snapshot = bpSharedHomebrewManager()?.updatesSnapshot
            let outdatedCount = (snapshot?.formulae.count ?? 0) + (snapshot?.casks.count ?? 0)

            if let button = self.statusItem?.button {
                if let icon = NSImage(systemSymbolName: "mug.fill", accessibilityDescription: NSLocalizedString("Cakebrew", comment: "")) {
                    icon.isTemplate = true
                    button.image = icon
                }
                button.imagePosition = .imageLeading
                button.title = outdatedCount > 0 ? " \(outdatedCount)" : ""
                button.setAccessibilityIdentifier("menubar.statusItem")
            }

            let menu = NSMenu(title: NSLocalizedString("Cakebrew", comment: ""))
            let openTitle = Bundle.main.localizedString(forKey: "MenuBar_Open_Cakebrew", value: "Open Cakebrew", table: nil)
            let openItem = NSMenuItem(title: openTitle, action: #selector(openMainWindowFromMenuBar(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.setAccessibilityIdentifier("menubar.openCakebrew")
            menu.addItem(openItem)

            menu.addItem(NSMenuItem.separator())

            let updatesTitle = Bundle.main.localizedString(forKey: "Sidebar_Item_Unified_Updates", value: "Updates", table: nil)
            let updatesItem = NSMenuItem(title: updatesTitle, action: #selector(openUnifiedUpdatesFromMenuBar(_:)), keyEquivalent: "")
            updatesItem.target = self
            updatesItem.setAccessibilityIdentifier("menubar.unifiedUpdates")
            menu.addItem(updatesItem)

            let upgradeAllTitle = Bundle.main.localizedString(forKey: "Dock_Upgrade_All_Outdated", value: "Upgrade All Outdated", table: nil)
            let upgradeAllItem = NSMenuItem(title: upgradeAllTitle, action: #selector(upgradeAllFromMenuBar(_:)), keyEquivalent: "")
            upgradeAllItem.target = self
            upgradeAllItem.isEnabled = snapshot?.hasEligibleUpdates == true
            upgradeAllItem.setAccessibilityIdentifier("menubar.upgradeAll")
            menu.addItem(upgradeAllItem)

            let refreshTitle = Bundle.main.localizedString(forKey: "Dock_Check_For_Updates", value: "Check for Updates", table: nil)
            let refreshItem = NSMenuItem(title: refreshTitle, action: #selector(updateHomebrewFromMenuBar(_:)), keyEquivalent: "")
            refreshItem.target = self
            refreshItem.setAccessibilityIdentifier("menubar.checkUpdates")
            menu.addItem(refreshItem)

            self.statusItem?.menu = menu
        }
    }

    @objc(openMainWindowFromMenuBar:)
    public func openMainWindowFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
    }

    @objc(openUnifiedUpdatesFromMenuBar:)
    public func openUnifiedUpdatesFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
        notificationNavigationTarget?.showUnifiedUpdates(sender)
    }

    @objc(upgradeAllFromMenuBar:)
    public func upgradeAllFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
        dockActionTarget?.upgradeAllOutdatedFormulae(sender)
    }

    @objc(updateHomebrewFromMenuBar:)
    public func updateHomebrewFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
        dockActionTarget?.updateHomebrew(sender)
    }

    @MainActor
    private func ensureAppUpdateHost() -> BPAppUpdateHost {
        if let existing = appUpdateHost {
            existing.automaticCheckEnabled = BPPreferences.automaticAppUpdateCheckEnabled
            return existing
        }
        var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        if version.isEmpty {
            version = "1.0.0"
        }
        let host = BPAppUpdateHost(
            currentVersion: version,
            automaticCheckEnabled: BPPreferences.automaticAppUpdateCheckEnabled
        )
        host.onToggleAutomaticCheck = { (enabled: Bool) in
            BPPreferences.automaticAppUpdateCheckEnabled = enabled
        }
        self.appUpdateHost = host
        return host
    }

    @objc(checkForAppUpdates:)
    public func checkForAppUpdates(_ sender: Any?) {
        MainActor.assumeIsolated {
            let host = self.ensureAppUpdateHost()
            host.performConfiguredCheck()
            host.showWindow()
        }
    }

    @objc(shouldBlockOperationWhileRunningBackgroundTask:)
    public static func shouldBlockOperation(whileRunningBackgroundTask isRunningBackgroundTask: Bool) -> Bool {
        return isRunningBackgroundTask
    }

    @objc(openWebsite:)
    public func openWebsite(_ sender: Any?) {
        if let url = URL(string: Self.homebrewWebsiteURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc(openDocumentation:)
    public func openDocumentation(_ sender: Any?) {
        if let url = URL(string: Self.cakebrewDocumentationURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc public func setupSignalHandler() {
        Darwin.signal(SIGTERM, bpSIGTERMHandler)
    }

    @objc(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)
    public func handleNotificationCenter(
        _ center: Any?,
        didReceiveNotificationResponse response: Any?,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        nonisolated(unsafe) let userInfo = bpExtractNotificationUserInfo(from: response)
        let handleResponse: @Sendable () -> Void = { [weak self] in
            guard let self else {
                completionHandler()
                return
            }
            let presenter = self.notificationPresenter
            presenter.cleanupNotificationAlerts()
            presenter.activateCakebrewIgnoringOtherApps()
            presenter.showMainWindow()
            self.navigate(forNotificationUserInfo: userInfo)
            completionHandler()
        }

        if Thread.isMainThread {
            handleResponse()
        } else {
            DispatchQueue.main.async(execute: handleResponse)
        }
    }

    @objc(userNotificationCenter:willPresentNotification:withCompletionHandler:)
    public func handleNotificationCenter(
        _ center: Any?,
        willPresentNotification notification: Any?,
        withCompletionHandler completionHandler: @escaping @Sendable (UInt) -> Void
    ) {
        let options: UNNotificationPresentationOptions = [.banner, .sound]
        completionHandler(options.rawValue)
    }
}

