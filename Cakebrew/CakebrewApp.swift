import SwiftUI
import AppKit

/// SwiftUI owns the application lifecycle, scenes, navigation and commands.
@main
struct CakebrewApp: App {
    @NSApplicationDelegateAdaptor(BPAppDelegate.self) private var delegate
    @StateObject private var workspace = BPWorkspace()
    @AppStorage(BPPreferences.showMenuBarExtraKey) private var showMenuBar = false

    var body: some Scene {
        WindowGroup("Cakebrew", id: "main", for: String.self) { _ in
            BPWorkspaceView(workspace: workspace)
                .onAppear { workspace.connect(to: delegate) }
                .onOpenURL { delegate.application(NSApp, open: [$0]) }
                .preferredColorScheme(previewColorScheme)
        } defaultValue: {
            "workspace"
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About Cakebrew") { delegate.showAboutWindow(nil) }
                Button("Check for Updates…") { delegate.checkForAppUpdates(nil) }
                    .accessibilityIdentifier("menu.app.checkForUpdates")
            }
            CommandGroup(after: .newItem) {
                Button("Import Brewfile…") { workspace.controller.runHomebrewImport(nil) }
                    .keyboardShortcut("o")
                Button("Export Brewfile…") { workspace.controller.runHomebrewExport(nil) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("Packages") {
                Button("Install Selected Package…") { workspace.controller.installFormula(nil) }
                    .disabled(!workspace.canInstall)
                Button("Install with Options…") { workspace.controller.installFormulaWithOptions(nil) }
                    .disabled(!workspace.canInstall || workspace.controller.selectedFormula()?.cask == true)
                Button("Upgrade Selected Packages…") { workspace.controller.upgradeSelectedFormulae(nil) }
                    .disabled(!workspace.canUpgrade)
                Button("Uninstall Selected Packages…") { workspace.controller.uninstallFormula(nil) }
                    .disabled(!workspace.canUninstall)
                Divider()
                Button(NSLocalizedString(workspace.isPinned ? "Unpin Package" : "Pin Package", comment: "")) {
                    if workspace.controller.currentFormulaPinned { workspace.controller.unpinSelectedFormula(nil) }
                    else { workspace.controller.pinSelectedFormula(nil) }
                }
                .disabled(!workspace.canUninstall)
                Divider()
                Button("Upgrade All Outdated Packages…") { workspace.controller.upgradeAllOutdatedFormulae(nil) }
                    .keyboardShortcut("u", modifiers: [.command, .option])
                    .disabled(!workspace.hasUpdates)
            }
            CommandGroup(after: .textEditing) {
                Button("Search Packages") { workspace.focusToolbarSearch() }
                    .keyboardShortcut("f")
                Button("Command Palette…") { workspace.controller.showCommandPalette(nil) }
                    .keyboardShortcut("k")
            }
            CommandMenu("Homebrew") {
                Button("Refresh Packages") { BPHomebrewManager.sharedManager().reloadFromInterface(rebuildingCache: false) }
                    .keyboardShortcut("r")
                Button("Update Homebrew") { workspace.controller.updateHomebrew(nil) }
                    .keyboardShortcut("u")
                Button("Run Doctor") { workspace.select(.doctor) }
                Divider()
                Button("Add Repository…") { workspace.controller.tapRepository(nil) }
                Button("Remove Repository…") { workspace.controller.untapRepository(nil) }
                    .disabled(workspace.row != Int(FormulaeSideBarItem.repositories.rawValue) || workspace.controller.selectedFormula() == nil)
                Divider()
                Button("Clean Up…") { workspace.controller.runHomebrewCleanup(nil) }
                Button("Remove Unused Dependencies…") { workspace.controller.removeUnusedDependencies(nil) }
            }
            CommandGroup(replacing: .help) {
                Button("Cakebrew Documentation") { delegate.openDocumentation(nil) }
            }
            SidebarCommands()
            BPSceneCommands(workspace: workspace)
            #if DEBUG
            BPDebugCommands(workspace: workspace)
            #endif
        }
        Settings {
            BPSettingsView().preferredColorScheme(previewColorScheme)
        }
        MenuBarExtra(isInserted: $showMenuBar) {
            Button("Open Cakebrew") { delegate.showMainWindow() }
                .accessibilityIdentifier("menubar.openCakebrew")
            Button("Show Package Updates") {
                delegate.showMainWindow()
                workspace.select(.unifiedUpdates)
            }
            .accessibilityIdentifier("menubar.showUpdates")
            Divider()
            Button("Update Homebrew") { workspace.controller.updateHomebrew(nil) }
                .accessibilityIdentifier("menubar.updateHomebrew")
            Button("Upgrade All Outdated Packages…") { workspace.controller.upgradeAllOutdatedFormulae(nil) }
                .disabled(!workspace.hasUpdates)
                .accessibilityIdentifier("menubar.upgradeAll")
            Button("Command Palette…") {
                delegate.showMainWindow()
                workspace.controller.showCommandPalette(nil)
            }
        } label: {
            HStack {
                Image(systemName: "mug.fill")
                let snapshot = BPHomebrewManager.sharedManager().updatesSnapshot
                let count = (snapshot?.formulae.count ?? 0) + (snapshot?.casks.count ?? 0)
                if count > 0 { Text("\(count)") }
            }
            .accessibilityLabel("Cakebrew")
            .accessibilityIdentifier("menubar.statusItem")
        }
        .menuBarExtraStyle(.menu)
    }

    /// UI snapshots can select an appearance without changing macOS settings.
    private var previewColorScheme: ColorScheme? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-BPMockBrew"),
           let index = arguments.firstIndex(of: "-BPUITestAppearance"), index + 1 < arguments.count {
            return arguments[index + 1] == "Light" ? .light : .dark
        }
        #endif
        return nil
    }
}

/// Bridges the established operation layer to value-based SwiftUI presentation.
@MainActor
final class BPWorkspace: ObservableObject {
    lazy var controller = BPHomebrewViewController()
    lazy var sidebar = BPSideBarController()
    @Published private(set) var isPrepared = false
    @Published private(set) var row = Int(FormulaeSideBarItem.installed.rawValue)
    @Published var revision = 0
    @Published var search = ""
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var inspectorVisible = true
    #if DEBUG
    private var searchLayoutRecorder: BPToolbarSearchLayoutRecorder?
    #endif

    init() {
        // App scene declarations can evaluate command enablement before AppKit's
        // lifecycle is ready. Construct view hosts only after a scene appears.
        BPPreferences.registerDefaults()
    }

    private func prepare() {
        guard !isPrepared else { return }
        controller.usesSwiftUIComposition = true
        controller.view = NSView()
        controller.sidebarController = sidebar
        controller.formulaeDataSource = BPFormulaeDataSource(mode: BPListMode.installed.rawValue)
        let discovery = BPHomebrewManager.sharedManager().discoveryResult
        controller.homebrewInstalled = discovery == .unknown || discovery == .available
        controller.setUpInstalledPackageListHost()
        controller.setUpUnifiedUpdatesHost()
        controller.setUpStatusBarHost()
        let doctor = BPDoctorViewController()
        _ = doctor.view
        controller.doctorViewController = doctor
        let update = BPUpdateViewController()
        _ = update.view
        controller.updateViewController = update
        let services = BPServicesViewController()
        _ = services.view
        controller.servicesViewController = services
        sidebar.delegate = controller
        sidebar.sidebarHost.onSelectRow = { [weak self] row in
            guard let self else { return }
            self.search = ""
            self.row = row
            self.controller.sourceListSelectionDidChange()
        }
        controller.onPresentationChanged = { [weak self] in
            guard let self else { return }
            self.row = self.sidebar.sidebarHost.selectedRowIndex
            self.revision &+= 1
        }
        controller.onSearchTextChanged = { [weak self] query in self?.search = query }
        controller.onShowPackageInspector = { [weak self] in self?.inspectorVisible = true }
        sidebar.configureSidebarSettings()
        row = sidebar.sidebarHost.selectedRowIndex
        controller.sourceListSelectionDidChange()
        isPrepared = true
    }

    func connect(to delegate: BPAppDelegate) {
        prepare()
        #if DEBUG
        if searchLayoutRecorder == nil,
           let path = ProcessInfo.processInfo.environment["BPUITestSearchLayoutLog"] {
            searchLayoutRecorder = BPToolbarSearchLayoutRecorder(path: path)
        }
        #endif
        controller.appDelegate = delegate
        // Register queued file and notification navigation only once the scene's
        // window exists, so their sheets have a valid presentation parent.
        DispatchQueue.main.async {
            delegate.window = NSApp.windows.first { BPAppDelegate.isWorkspaceWindow($0, title: self.title) }
            delegate.dockActionTarget = self.controller
            delegate.brewfileImportTarget = self.controller
            delegate.notificationNavigationTarget = self.controller
        }
        sidebar.refreshSidebarBadges()
        controller.syncInstalledPackageListHostRows()
    }

    /// Toolbar-hosted SwiftUI text fields do not reliably participate in the
    /// content view's FocusState on macOS. Use the window's responder chain for
    /// Command-F while SwiftUI continues to own the field and its binding.
    func focusToolbarSearch() {
        guard let window = BPAppDelegate.current?.window,
              let field = window.toolbar?.items.compactMap(\.view)
                .compactMap({ BPToolbarSearchTextField(in: $0) }).first else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        field.selectText(nil)
    }

    func select(_ item: FormulaeSideBarItem) {
        sidebar.sidebarHost.selectRow(atIndex: Int(item.rawValue))
    }

    var title: String {
        guard isPrepared else { return "Cakebrew" }
        var index = 0
        for group in sidebar.rootSidebarCategory.children {
            index += 1
            for item in group.children {
                if index == row { return item.title ?? "Cakebrew" }
                index += 1
            }
        }
        return "Cakebrew"
    }
    var isTool: Bool {
        [FormulaeSideBarItem.doctor, .update, .services].contains { Int($0.rawValue) == row }
    }
    var selection: [BPFormula] { isPrepared ? (controller.selectedFormulae() ?? []) : [] }
    var isPinned: Bool { isPrepared && controller.currentFormulaPinned }
    var hasUpdates: Bool { isPrepared && controller.enableUpgradeAllMenu }
    var canInstall: Bool { selection.count == 1 && !selection[0].isInstalled() }
    var canUninstall: Bool { !selection.isEmpty && selection.allSatisfy { $0.isInstalled() } }
    var canUpgrade: Bool { selection.contains { BPHomebrewManager.sharedManager().status(forFormula: $0) == .outdated } }
}

@MainActor
private struct BPWorkspaceView: View {
    @ObservedObject var workspace: BPWorkspace

    var body: some View {
        NavigationSplitView(columnVisibility: $workspace.columnVisibility) {
            Group {
                if workspace.isPrepared { workspace.sidebar.sidebarHost.content }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 290)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            content
                .toolbar(removing: .sidebarToggle)
                .navigationTitle(workspace.title)
                .background {
                    BPWorkspaceToolbarChrome(workspace: workspace, isTool: workspace.isTool,
                        search: workspace.search,
                        refreshing: BPHomebrewManager.sharedManager().reloadInFlight)
                        .equatable()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if workspace.isPrepared, let host = workspace.controller.statusBarHost { host.content.frame(height: 32) }
                }
        }
        .inspector(isPresented: Binding(
            get: { showsInspector },
            set: { workspace.inspectorVisible = $0 }
        )) {
            VStack(spacing: 0) {
                if workspace.isPrepared, let host = workspace.controller.selectedFormulaeViewController?.inspectorHost {
                    host.content
                        .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
            .inspectorColumnWidth(min: 250, ideal: 320, max: 600)
        }
        .onChange(of: workspace.search) { _, query in
            workspace.controller.performSearch(with: query)
        }
        .frame(minWidth: 800, minHeight: 520)
        .onAppear { DispatchQueue.main.async { alignWindowMinimum() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in alignWindowMinimum() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in alignWindowMinimum() }
        .onChange(of: showsInspector) { _, _ in DispatchQueue.main.async { alignWindowMinimum() } }
    }

    private var showsInspector: Bool {
        workspace.isPrepared && !workspace.isTool && workspace.controller.homebrewInstalled && workspace.inspectorVisible
    }

    /// SwiftUI's full-height inspector is added beside the main hosting view.
    /// Keep the system window minimum consistent with both columns.
    private func alignWindowMinimum() {
        guard let window = BPAppDelegate.current?.window ?? NSApp.windows.first(where: {
            BPAppDelegate.isWorkspaceWindow($0, title: workspace.title)
        }) else { return }
        // Use the column's minimum, not its live width. Changing the window's
        // minimum during a divider drag interferes with native split-view tracking.
        let reservedWidth: CGFloat = showsInspector ? 250 : 0
        let minimumWidth = 800 + reservedWidth
        if abs(window.contentMinSize.width - minimumWidth) > 0.5 {
            var minimum = window.contentMinSize
            minimum.width = minimumWidth
            window.contentMinSize = minimum
        }
        if window.frame.width < minimumWidth - 0.5 {
            var frame = window.frame
            frame.size.width = minimumWidth
            frame = window.constrainFrameRect(frame, to: window.screen)
            window.setFrame(frame, display: true)
        }
    }

    private var recoveryTitle: String {
        let manager = BPHomebrewManager.sharedManager()
        if manager.checkingHomebrew { return NSLocalizedString("Checking for Homebrew…", comment: "") }
        switch manager.discoveryResult {
        case .missing: return NSLocalizedString("Homebrew wasn’t found", comment: "")
        case .invalidShell: return NSLocalizedString("Your login shell is unavailable", comment: "")
        default: return NSLocalizedString("Homebrew couldn’t be checked", comment: "")
        }
    }

    private var recoveryMessage: String {
        let manager = BPHomebrewManager.sharedManager()
        if manager.checkingHomebrew {
            return NSLocalizedString("Cakebrew is checking your login shell for Homebrew. This may take a moment.", comment: "")
        }
        switch manager.discoveryResult {
        case .missing:
            return NSLocalizedString("Cakebrew couldn’t find Homebrew in your login shell’s PATH. Open brew.sh for installation instructions, or fix your shell configuration, then choose Try Again.", comment: "")
        case .invalidShell:
            return NSLocalizedString("Cakebrew needs an executable login shell listed in /etc/shells. Check your shell configuration, then choose Try Again. Homebrew installation instructions are available at brew.sh.", comment: "")
        default:
            return NSLocalizedString("Your login shell didn’t return a usable Homebrew executable. Check its startup configuration and PATH, then choose Try Again. Installation instructions are available at brew.sh.", comment: "")
        }
    }

    @ViewBuilder private var content: some View {
        if !workspace.isPrepared {
            ProgressView("Loading Packages…")
        } else if !workspace.controller.homebrewInstalled {
            ContentUnavailableView {
                Label(recoveryTitle, systemImage: "shippingbox")
                    .accessibilityIdentifier("homebrew.recovery.title")
            } description: {
                Text(recoveryMessage)
                    .accessibilityIdentifier("homebrew.recovery.message")
            } actions: {
                Link("Get Homebrew", destination: URL(string: "https://brew.sh")!)
                    .accessibilityIdentifier("homebrew.install")
                Button("Try Again") { BPHomebrewManager.sharedManager().retryHomebrewDiscovery() }
                    .disabled(BPHomebrewManager.sharedManager().checkingHomebrew)
                    .accessibilityIdentifier("homebrew.retry")
            }
        } else if !workspace.controller.searching, workspace.row == Int(FormulaeSideBarItem.doctor.rawValue), let host = workspace.controller.doctorViewController?.consoleHost {
            host.content
        } else if !workspace.controller.searching, workspace.row == Int(FormulaeSideBarItem.update.rawValue), let host = workspace.controller.updateViewController?.consoleHost {
            host.content
        } else if !workspace.controller.searching, workspace.row == Int(FormulaeSideBarItem.services.rawValue), let host = workspace.controller.servicesViewController?.servicesHost {
            host.content
        } else if workspace.controller.isUsingUnifiedUpdatesHost, let host = workspace.controller.unifiedUpdatesHost {
            host.content
        } else {
            if let host = workspace.controller.installedPackageListHost {
                host.content
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if host.rowCount == 0 {
                            if BPHomebrewManager.sharedManager().reloadInFlight {
                                ProgressView("Loading Packages…")
                            } else {
                                let state = BPEmptyState.state(forSidebarRow: workspace.row, searching: !workspace.search.isEmpty)
                                ContentUnavailableView {
                                    Label(NSLocalizedString(state.titleKey, comment: ""), systemImage: state.symbolName)
                                        .accessibilityIdentifier("emptyState.title")
                                } description: {
                                    Text(NSLocalizedString(state.messageKey, comment: ""))
                                        .accessibilityIdentifier("emptyState.message")
                                }
                                .allowsHitTesting(false)
                            }
                        }
                    }
            }
        }
    }
}

/// Keep search and toolbar preferences independent of package selection. Action
/// views observe enablement separately. An explicitly sized search item avoids
/// automatic search placement migrating above the full-height inspector.
@MainActor
private struct BPWorkspaceToolbarChrome: View, Equatable {
    let workspace: BPWorkspace
    let isTool: Bool
    let search: String
    let refreshing: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workspace === rhs.workspace && lhs.isTool == rhs.isTool &&
        lhs.search == rhs.search &&
        lhs.refreshing == rhs.refreshing
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .toolbar {
                ToolbarItem(id: "workspaceSidebarToggle", placement: .navigation) {
                    BPSidebarToggle(workspace: workspace)
                }
                ToolbarItem(id: "packageSearch", placement: .principal) {
                    BPToolbarSearchField(workspace: workspace, search: search)
                }
                if !isTool {
                    ToolbarItem(id: "packageInstall", placement: .navigation) {
                        BPWorkspacePackageAction(workspace: workspace, action: .install)
                    }
                    ToolbarItem(id: "packageUpgrade", placement: .navigation) {
                        BPWorkspacePackageAction(workspace: workspace, action: .upgrade)
                    }
                    ToolbarItem(id: "packageUninstall", placement: .navigation) {
                        BPWorkspacePackageAction(workspace: workspace, action: .uninstall)
                    }
                }
                ToolbarItemGroup(placement: .navigation) {
                    if refreshing {
                        Button("Cancel Refresh", systemImage: "xmark") { workspace.controller.cancelReload(nil) }
                    }
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        BPHomebrewManager.sharedManager().reloadFromInterface(rebuildingCache: false)
                    }
                    .help("Refresh packages (⌘R)")
                    .disabled(refreshing)
                }
                if !isTool {
                    ToolbarItem(id: "workspaceInspectorToggle", placement: .primaryAction) {
                        BPInspectorToggle(workspace: workspace)
                    }
                }
            }
    }

}

@MainActor
private struct BPSidebarToggle: View {
    @ObservedObject var workspace: BPWorkspace

    private var isCollapsed: Bool { workspace.columnVisibility == .detailOnly }
    private var title: String {
        NSLocalizedString(isCollapsed ? "Show Sidebar" : "Hide Sidebar", comment: "Sidebar toolbar toggle")
    }

    var body: some View {
        Button {
            workspace.columnVisibility = isCollapsed ? .all : .detailOnly
        } label: {
            Label(title, systemImage: "sidebar.left")
        }
        .help(title)
        .accessibilityIdentifier("workspace.toggleSidebar")
    }
}

@MainActor
private struct BPToolbarSearchField: View {
    let workspace: BPWorkspace
    let search: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search packages", text: Binding(get: { workspace.search }, set: { workspace.search = $0 }))
                .textFieldStyle(.plain)
                .accessibilityIdentifier("workspace.search")
                .onExitCommand {
                    if !workspace.search.isEmpty { workspace.search = "" }
                    else { BPAppDelegate.current?.window?.makeFirstResponder(nil) }
                }
            Button {
                workspace.search = ""
                workspace.focusToolbarSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear search")
            .opacity(search.isEmpty ? 0 : 1)
            .disabled(search.isEmpty)
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 30)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

}

@MainActor
private struct BPInspectorToggle: View {
    let workspace: BPWorkspace

    var body: some View {
        Button("Package Inspector", systemImage: "sidebar.right") { workspace.inspectorVisible.toggle() }
            .help("Show or hide package details")
            .accessibilityIdentifier("workspace.toggleInspector")
    }
}

@MainActor
private struct BPWorkspacePackageAction: View {
    enum Action { case install, upgrade, uninstall }
    @ObservedObject var workspace: BPWorkspace
    let action: Action

    var body: some View {
        Group {
            switch action {
            case .install:
                Button("Install…", systemImage: "plus") { workspace.controller.installFormula(nil) }
                    .disabled(!workspace.canInstall)
            case .upgrade:
                Button("Upgrade…", systemImage: "arrow.up.circle") { workspace.controller.upgradeSelectedFormulae(nil) }
                    .disabled(!workspace.canUpgrade)
            case .uninstall:
                Button("Uninstall…", systemImage: "trash") { workspace.controller.uninstallFormula(nil) }
                    .disabled(!workspace.canUninstall)
            }
        }
        .labelStyle(.iconOnly)
    }
}

@MainActor
private struct BPSettingsView: View {
    @AppStorage(BPPreferences.backgroundCheckEnabledKey) private var backgroundCheck = true
    @AppStorage(BPPreferences.backgroundCheckIntervalKey) private var interval = 21600.0
    @AppStorage(BPPreferences.greedyCaskUpgradesKey) private var greedy = false
    @AppStorage(BPPreferences.automaticAppUpdateCheckEnabledKey) private var appUpdates = true
    @AppStorage(BPPreferences.showMenuBarExtraKey) private var menuBar = false
    @State private var helperState: BPHelperState = .notRequired
    @State private var helperError: String?

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Preferences_Background_Check", isOn: $backgroundCheck)
                    .accessibilityIdentifier("settings.backgroundChecks")
                    .accessibilityLabel(Text("Preferences_Background_Check"))
                Picker("Preferences_Check_Interval", selection: $interval) {
                    Text("Preferences_Interval_Hourly").tag(3600.0)
                    Text("Preferences_Interval_Six_Hours").tag(21600.0)
                    Text("Preferences_Interval_Daily").tag(86400.0)
                }.disabled(!backgroundCheck)
                Toggle("Preferences_Greedy_Casks", isOn: $greedy)
                    .accessibilityIdentifier("settings.greedyCasks")
                    .accessibilityLabel(Text("Preferences_Greedy_Casks"))
                Toggle("Check for Cakebrew updates automatically", isOn: $appUpdates)
                    .accessibilityIdentifier("settings.appUpdates")
                    .accessibilityLabel(Text("Check for Cakebrew updates automatically"))
                Button("Check for Updates…") { BPAppDelegate.current?.checkForAppUpdates(nil) }
            }
            Section("Menu Bar") {
                Toggle("Preferences_Menu_Bar_Extra", isOn: $menuBar)
                    .accessibilityIdentifier("settings.menuBar")
                    .accessibilityLabel(Text("Preferences_Menu_Bar_Extra"))
                    .onChange(of: menuBar) { _, _ in BPAppDelegate.current?.updateMenuBarExtra() }
            }
            Section("Preferences_Helper_Section") {
                Text(BPHelperRegistration.localizedDescription(forState: helperState))
                    .foregroundStyle(.secondary)
                if BPHelperRegistration.stateOffersLoginItemsShortcut(helperState) {
                    Button("Open Login Items Settings") { BPHelperRegistration.openLoginItemsSettings() }
                } else if helperState == .notRegistered {
                    Button("Install Helper…") {
                        do {
                            try BPHelperRegistration.sharedRegistration().register()
                            helperError = nil
                        } catch {
                            helperError = error.localizedDescription
                        }
                        helperState = BPHelperRegistration.sharedRegistration().currentState()
                    }
                }
                if let helperError { Text(helperError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 480)
        .onAppear { helperState = BPHelperRegistration.sharedRegistration().currentState() }
    }
}

@MainActor
private struct BPSceneCommands: Commands {
    let workspace: BPWorkspace
    @AppStorage(BPPreferences.compactPackageRowsKey) private var compactPackageRows = false
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        let _ = installSceneOpener()
        CommandGroup(after: .sidebar) {
            Toggle("Compact Package Rows", isOn: $compactPackageRows)
                .accessibilityIdentifier("menu.view.compactPackageRows")
        }
        CommandGroup(after: .windowArrangement) {
            Button("Show Cakebrew") { BPAppDelegate.current?.showMainWindow() }
                .keyboardShortcut("0")
        }
    }

    private func installSceneOpener() {
        let action = openWindow
        BPAppDelegate.current?.registerMainSceneOpener(
            { action(id: "main", value: "workspace") }, windowTitle: { workspace.title }
        )
    }
}


#if DEBUG
/// Test fixtures use the same scene commands as the shipping interface.
@MainActor
private struct BPDebugCommands: Commands {
    let workspace: BPWorkspace
    private var arguments: [String] { ProcessInfo.processInfo.arguments }
    private func argument(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    private func openNotification() {
        guard let target = argument("-BPMockWarmNotificationTarget") else { return }
        BPAppDelegate.current?.navigate(forNotificationUserInfo: [BPBackgroundUpdater.outdatedNotificationTargetKey: target])
    }
    var body: some Commands {
        if arguments.contains("-BPMockBrew") {
            if let file = argument("-BPMockBrewfileURL") {
                CommandMenu("Brewfile Test") {
                    Button("Review Mock Brewfile") {
                        workspace.controller.importBrewfile(at: URL(fileURLWithPath: file))
                    }
                }
            }
            if argument("-BPMockWarmNotificationTarget") != nil || arguments.contains("-BPMockHoldCatalogUntilReleased") {
                CommandMenu("Notification Test") {
                    if argument("-BPMockWarmNotificationTarget") != nil {
                        Button("Search Mock Packages") { workspace.controller.beginMockNotificationSearch(nil) }
                        Button("Open Mock Notification") { openNotification() }
                        Button("Search Then Open Mock Notification") {
                            workspace.controller.beginMockNotificationSearch(nil)
                            openNotification()
                        }
                        Button("Search Then Clear Mock Search") { workspace.controller.clearMockSearchBeforeDebounce(nil) }
                    }
                    if arguments.contains("-BPMockHoldCatalogUntilReleased") {
                        Button("Complete Mock Catalog") {
                            (BPHomebrewInterface.sharedInterface() as? BPMockHomebrewInterface)?.releaseHeldCatalogs(nil)
                        }
                        .accessibilityIdentifier("mock.catalog.complete")
                    }
                }
            }
        }
    }
}
#endif

@MainActor
private func BPToolbarSearchTextField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    return view.subviews.lazy.compactMap { BPToolbarSearchTextField(in: $0) }.first
}

#if DEBUG
/// UI tests sample during animations: XCTest's normal element queries wait for
/// idle and would miss a search field that moves away and then returns.
@MainActor
private final class BPToolbarSearchLayoutRecorder {
    private var timer: Timer?
    private let output: FileHandle?
    private var previous: CGRect?

    init(path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        output = FileHandle(forWritingAtPath: path)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sample() {
        guard let window = BPAppDelegate.current?.window,
              let field = window.toolbar?.items.compactMap(\.view).compactMap({ BPToolbarSearchTextField(in: $0) }).first,
              field.window != nil else { return }
        let frame = field.convert(field.bounds, to: nil)
        guard frame.width > 0, frame != previous else { return }
        previous = frame
        let line = "\(frame.minX),\(frame.width)\n"
        if let data = line.data(using: .utf8) { try? output?.write(contentsOf: data) }
    }
}
#endif
