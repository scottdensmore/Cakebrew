import AppKit
import XCTest

// Model loads and AppKit animations are replaced at the boundary. The production
// controller still registers and receives real NSNotificationCenter events.
@MainActor
@objc(BPInformationTestPopover)
final class BPInformationTestPopover: NSPopover {}

@MainActor
@objc(BPInformationTestHost)
final class BPInformationTestHost: NSObject {
    @objc var viewController: NSViewController
    @objc var name: String?
    @objc var cask: Bool = false
    @objc var infoType: BPFormulaInfoType = .general
    @objc var information: String?
    @objc var generation: UInt64 = 0
    @objc var open: Bool = false

    override init() {
        self.viewController = NSViewController()
        super.init()
    }

    @objc(beginWithName:cask:)
    func begin(withName name: String?, cask: Bool) -> UInt64 {
        begin(withName: name, cask: cask, infoType: BPFormulaInfoType.general.rawValue)
    }

    @objc(beginWithName:cask:infoType:)
    func begin(withName name: String?, cask: Bool, infoType: Int) -> UInt64 {
        self.name = name
        self.cask = cask
        self.infoType = BPFormulaInfoType(rawValue: infoType) ?? .general
        self.information = nil
        self.open = true
        generation += 1
        return generation
    }

    @objc(receiveInformation:website:name:cask:generation:)
    func receiveInformation(
        _ information: String?,
        website: URL?,
        name: String?,
        cask: Bool,
        generation: UInt64
    ) {
        receiveInformation(
            information,
            website: website,
            name: name,
            cask: cask,
            infoType: BPFormulaInfoType.general.rawValue,
            generation: generation
        )
    }

    @objc(receiveInformation:website:name:cask:infoType:generation:)
    func receiveInformation(
        _ information: String?,
        website: URL?,
        name: String?,
        cask: Bool,
        infoType: Int,
        generation: UInt64
    ) {
        let resolvedType = BPFormulaInfoType(rawValue: infoType) ?? .general
        if open && generation == self.generation && self.infoType == resolvedType
            && self.cask == cask && self.name == name {
            self.information = information
        }
    }

    @objc(close)
    func close() {
        open = false
        name = nil
        information = nil
    }
}

@MainActor
@objc(BPSelectedFormulaTestHost)
final class BPSelectedFormulaTestHost: NSObject {
    @objc var viewController: NSViewController
    @objc var name: String?
    @objc var cask: Bool = false
    @objc var installed: Bool = false
    @objc var pinned: Bool = false
    @objc var shortDescription: String?
    @objc var dependents: [String]?
    @objc var isMultiple: Bool = false
    @objc var isEmpty: Bool = true
    @objc var generation: UInt64 = 0

    override init() {
        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        self.viewController = vc
        super.init()
    }

    @objc func clearSelection() {
        isEmpty = true
        isMultiple = false
        name = nil
        dependents = nil
        generation += 1
    }

    @objc func showMultipleSelection() {
        isEmpty = false
        isMultiple = true
        name = nil
        dependents = nil
        generation += 1
    }

    @objc(beginSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    func beginSelection(
        withName name: String,
        cask: Bool,
        installed: Bool,
        pinned: Bool,
        installPath: String?,
        latestVersion: String?,
        dependencies: String?,
        conflicts: String?,
        shortDescription: String?
    ) -> UInt64 {
        isEmpty = false
        isMultiple = false
        self.name = name
        self.cask = cask
        self.installed = installed
        self.pinned = pinned
        self.shortDescription = shortDescription
        self.dependents = nil
        generation += 1
        return generation
    }

    @objc(updateSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    func updateSelection(
        withName name: String,
        cask: Bool,
        installed: Bool,
        pinned: Bool,
        installPath: String?,
        latestVersion: String?,
        dependencies: String?,
        conflicts: String?,
        shortDescription: String?
    ) {
        if !isEmpty && !isMultiple && self.cask == cask && self.name == name {
            self.installed = installed
            self.pinned = pinned
            self.shortDescription = shortDescription
        }
    }

    @objc(receiveDependents:name:cask:generation:)
    func receiveDependents(
        _ dependents: [String],
        name: String,
        cask: Bool,
        generation: UInt64
    ) {
        if !isEmpty && !isMultiple && generation == self.generation
            && self.cask == cask && self.name == name {
            self.dependents = dependents
        }
    }
}

@MainActor
final class BPFormulaInformationLifecycleTests: XCTestCase, @unchecked Sendable {
    var controller: BPFormulaPopoverViewController!
    var popover: BPInformationTestPopover!
    var host: BPInformationTestHost!
    var formula: BPFormula!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
        controller = BPFormulaPopoverViewController()
        popover = BPInformationTestPopover()
        popover.behavior = .semitransient
        host = BPInformationTestHost()
        formula = BPInformationCachedFormula.formula(withName: "mockwget")
        controller.formulaPopover = popover
        controller.awakeFromNib()
        controller.setValue(host, forKey: "informationHost")
        controller.formula = formula
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
        // Release the fake popover's retained controller before releasing our owner.
        popover.contentViewController = nil
        controller = nil
        popover = nil
        host = nil
        formula = nil
        }
        super.tearDown()
    }

    private func postCloseNotification(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: popover)
    }

    private func finishOldCloseOnNextRunLoop() {
        let finished = expectation(description: "old close animation finished")
        DispatchQueue.main.async {
            self.postCloseNotification(NSPopover.didCloseNotification)
            finished.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    func testGeneralInformationUsesTransientBehaviorAndDependentsRestoreSemitransient() {
        XCTAssertEqual(popover.behavior, .transient)
        controller.infoType = .installedDependents
        XCTAssertEqual(popover.behavior, .semitransient)
        controller.infoType = .general
        XCTAssertEqual(popover.behavior, .transient)
        controller.infoType = .allDependents
        XCTAssertEqual(popover.behavior, .semitransient)
        controller.infoType = .general
        XCTAssertEqual(popover.behavior, .transient)
    }

    func testOldAnimatedCloseCannotClearReopenedInformation() {
        postCloseNotification(NSPopover.willCloseNotification)
        controller.formula = formula
        XCTAssertEqual(host.information, "cached mock information")
        // The old animation completes after the next presentation has begun.
        finishOldCloseOnNextRunLoop()
        XCTAssertTrue(host.open)
        XCTAssertEqual(host.name, "mockwget")
        XCTAssertEqual(host.information, "cached mock information")
    }

    func testDependentModeCloseCannotClearReturningInformation() {
        postCloseNotification(NSPopover.willCloseNotification)
        controller.infoType = .installedDependents
        XCTAssertFalse(host.open)
        // Close the dependent view, then begin information before its animation ends.
        postCloseNotification(NSPopover.willCloseNotification)
        controller.infoType = .general
        controller.formula = formula
        finishOldCloseOnNextRunLoop()
        XCTAssertTrue(host.open)
        XCTAssertEqual(host.information, "cached mock information")
    }

    func testCurrentPresentationIsInvalidatedWhenClosingBegins() {
        XCTAssertTrue(host.open)
        postCloseNotification(NSPopover.willCloseNotification)
        XCTAssertFalse(host.open, "Late provider responses must be rejected during closing animation")
        XCTAssertNil(host.information)
    }

    func testUnrelatedPopoverCloseDoesNotInvalidateInformation() {
        let other = BPInformationTestPopover()
        NotificationCenter.default.post(name: NSPopover.willCloseNotification, object: other)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: other)
        XCTAssertTrue(host.open)
        XCTAssertEqual(host.information, "cached mock information")
    }

    func testDependentsModesHostSwiftViewControllerAndRejectStaleResponses() {
        let delivered = expectation(description: "dependents delivered")
        controller.dependentsProvider = { name, onlyInstalled in
            onlyInstalled ? "\(name)-installed-dep" : "\(name)-all-dep"
        }
        controller.infoType = .installedDependents
        controller.formula = BPFormula.formula(withName: "mockwget")
        XCTAssertEqual(popover.contentViewController, host.viewController)
        XCTAssertEqual(host.infoType, .installedDependents)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            delivered.fulfill()
        }
        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(host.information, "mockwget-installed-dep")

        let allDelivered = expectation(description: "all dependents delivered")
        controller.infoType = .allDependents
        controller.formula = BPFormula.formula(withName: "mockwget")
        XCTAssertEqual(host.infoType, .allDependents)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            allDelivered.fulfill()
        }
        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(host.information, "mockwget-all-dep")
    }

    func testSelectedFormulaControllerRoutesSingleMultipleEmptyAndNotificationUpdates() {
        let selected = BPSelectedFormulaViewController()
        let inspectorHost = BPSelectedFormulaTestHost()
        selected.setValue(inspectorHost, forKey: "inspectorHost")
        _ = selected.view

        let formula = BPFormula.formula(withName: "shared")
        formula.setValue("Initial description", forKey: "shortDescription")
        let sameNamedCask = BPFormula.formula(withName: "shared")
        sameNamedCask.cask = true
        sameNamedCask.setValue("Cask description", forKey: "shortDescription")

        selected.formulae = [formula]
        XCTAssertFalse(inspectorHost.isEmpty)
        XCTAssertFalse(inspectorHost.isMultiple)
        XCTAssertEqual(inspectorHost.name, "shared")
        XCTAssertFalse(inspectorHost.cask)
        XCTAssertEqual(inspectorHost.shortDescription, "Initial description")

        // Notification from a same-named cask must not overwrite the selected formula.
        formula.setValue("Updated formula description", forKey: "shortDescription")
        NotificationCenter.default.post(
            name: BPFormula.didUpdateNotification,
            object: sameNamedCask
        )
        NotificationCenter.default.post(
            name: BPFormula.didUpdateNotification,
            object: formula
        )
        let notified = expectation(description: "main queue notification processed")
        DispatchQueue.main.async {
            notified.fulfill()
        }
        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(inspectorHost.shortDescription, "Updated formula description")

        selected.formulae = [formula, sameNamedCask]
        XCTAssertTrue(inspectorHost.isMultiple)

        selected.formulae = []
        XCTAssertTrue(inspectorHost.isEmpty)
    }

    func testInstalledPackageListHostSyncsSelectionSortAndActionCallbacks() {
        let listHost = BPInstalledPackageListHost()
        var selectionEvents: [String] = []
        var sortEvents: [String] = []
        var actionEvents: [Int] = []

        listHost.onSelectionChanged = { name, cask in
            if let name {
                selectionEvents.append("\(name):\(cask ? 1 : 0)")
            } else {
                selectionEvents.append("none")
            }
        }
        listHost.onSortChanged = { key, ascending in
            sortEvents.append("\(key ?? ""):\(ascending ? 1 : 0)")
        }
        listHost.onTableAction = { request in
            actionEvents.append(request)
        }

        listHost.updateRows(
            names: ["wget", "ack"],
            versions: ["1.24", "3.7"],
            latestVersions: ["1.24", "3.7"],
            statusRanks: [1, 1],
            pinnedFlags: [false, true],
            cask: false
        )

        XCTAssertEqual(listHost.rowCount, 2)
        XCTAssertEqual(listHost.index(ofPackageNamed: "ack", cask: false), 1)
        XCTAssertEqual(listHost.index(ofPackageNamed: "ack", cask: true), -1)

        listHost.applySort(columnIdentifier: "Name", ascending: true)
        XCTAssertEqual(listHost.index(ofPackageNamed: "ack", cask: false), 0)
        XCTAssertEqual(listHost.index(ofPackageNamed: "wget", cask: false), 1)

        XCTAssertTrue(listHost.selectPackage(named: "wget", cask: false))
        XCTAssertEqual(listHost.selectedRow, 1)
        XCTAssertEqual(listHost.selectedPackageName, "wget")
        XCTAssertFalse(listHost.selectedPackageCask)
        XCTAssertEqual(selectionEvents.last, "wget:0")

        listHost.deselectAll()
        XCTAssertEqual(listHost.selectedRow, -1)
        XCTAssertNil(listHost.selectedPackageName)
        XCTAssertEqual(selectionEvents.last, "none")
    }

    func testInstalledPackageListHostKeyboardRoutingAndPopoverAnchorFallback() {
        let listHost = BPInstalledPackageListHost()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(listHost.viewController.view)
        if let bounds = window.contentView?.bounds {
            listHost.viewController.view.frame = bounds
        }
        window.makeFirstResponder(listHost.viewController.view)

        var spacePresses = 0
        var actions: [Int] = []
        listHost.onSpacePressed = {
            spacePresses += 1
        }
        listHost.onTableAction = { request in
            actions.append(request)
        }

        listHost.updateRows(
            names: ["wget"],
            versions: ["1.24"],
            latestVersions: ["1.24"],
            statusRanks: [1],
            pinnedFlags: [false],
            cask: false
        )
        XCTAssertTrue(listHost.selectPackage(named: "wget", cask: false))

        let makeKey: (Int, NSEvent.ModifierFlags, Bool) -> NSEvent = { ch, flags, isRepeat in
            let chars = String(UnicodeScalar(UInt16(ch))!)
            return NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: chars,
                charactersIgnoringModifiers: chars,
                isARepeat: isRepeat,
                keyCode: 0
            )!
        }

        XCTAssertTrue(listHost.handleKeyDown(makeKey(Int((" " as UnicodeScalar).value), [], false)))
        XCTAssertEqual(spacePresses, 1)

        XCTAssertTrue(listHost.handleKeyDown(makeKey(NSCarriageReturnCharacter, [], false)))
        XCTAssertTrue(listHost.handleKeyDown(makeKey(NSEnterCharacter, [], false)))
        XCTAssertTrue(listHost.handleKeyDown(makeKey(NSDeleteCharacter, [], false)))
        XCTAssertTrue(listHost.handleKeyDown(makeKey(NSDeleteFunctionKey, [], false)))
        XCTAssertEqual(actions, [0, 0, 1, 1])

        // Modifiers and repeats are rejected for Return/Delete
        XCTAssertFalse(listHost.handleKeyDown(makeKey(NSCarriageReturnCharacter, [.command], false)))
        XCTAssertFalse(listHost.handleKeyDown(makeKey(NSDeleteCharacter, [], true)))
        XCTAssertEqual(actions.count, 4)

        let anchor = listHost.rectOfSelectedRow(in: listHost.viewController.view)
        XCTAssertFalse(anchor.isEmpty)
    }

    func testSwiftUITableSelectionSurvivesRowReplacementWithoutAppKitIntrospection() {
        let host = BPInstalledPackageListHost()
        host.listMode = BPListMode.installed.rawValue
        host.updateRows(names: ["ack", "wget"], versions: ["3.7", "1.24"],
                        latestVersions: ["3.7", "1.24"], statusRanks: [1, 1],
                        pinnedFlags: [true, false], cask: false)
        XCTAssertTrue(host.selectPackage(named: "wget", cask: false))
        XCTAssertEqual(host.selectedPackageName, "wget")
        host.updateRows(names: ["wget", "ack"], versions: ["1.25", "3.7"],
                        latestVersions: ["1.25", "3.7"], statusRanks: [1, 1],
                        pinnedFlags: [false, true], cask: false)
        XCTAssertEqual(host.selectedPackageName, "wget", "Selection follows package identity, not its former row")
        host.deselectAll()
        XCTAssertEqual(host.selectedCount, 0)
    }

}

// MARK: - End-to-End In-Process Feature Journey Suite

@MainActor
final class BPEndToEndFeatureJourneyTests: XCTestCase, @unchecked Sendable {
    var mockInterface: BPMockHomebrewInterface!
    var retainedSidebarController: BPSideBarController?
    var retainedFormulaMenu: NSMenu?
    var savedSortColumn: String?
    var savedSortAscending: Bool = true
    var savedSidebarRow: Int = 1
    var savedBackgroundCheck: Bool = false
    var savedBackgroundInterval: TimeInterval = 21600
    var savedGreedy: Bool = false
    var savedAutoAppUpdates: Bool = false
    var savedShowMenuBarExtra: Bool = false

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
        _ = NSApplication.shared
        BPPreferences.registerDefaults()
        savedSortColumn = BPPreferences.sortColumnIdentifier
        savedSortAscending = BPPreferences.sortAscending
        savedSidebarRow = BPPreferences.lastSelectedSidebarRow
        savedBackgroundCheck = BPPreferences.backgroundCheckEnabled
        savedBackgroundInterval = BPPreferences.backgroundCheckInterval
        savedGreedy = BPPreferences.greedyCaskUpgrades
        savedAutoAppUpdates = BPPreferences.automaticAppUpdateCheckEnabled
        savedShowMenuBarExtra = BPPreferences.showMenuBarExtra

        BPPreferences.sortColumnIdentifier = nil
        BPPreferences.sortAscending = true
        BPPreferences.lastSelectedSidebarRow = Int(FormulaeSideBarItem.installed.rawValue)
        BPPreferences.showMenuBarExtra = false

        mockInterface = BPMockHomebrewInterface(uniqueInstance: ())
        BPHomebrewInterface.setSharedInterfaceForTesting(mockInterface)
        (NSApp.delegate as? BPAppDelegate)?.runningBackgroundTask = false
        BPHomebrewManager.sharedManager().setValue(false, forKey: "reloadInFlight")
        BPHomebrewManager.sharedManager().setValue(false, forKey: "discoveryInFlight")
        populateMockHomebrewCatalog()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
        (NSApp.delegate as? BPAppDelegate)?.runningBackgroundTask = false
        BPHomebrewInterface.setSharedInterfaceForTesting(nil)
        mockInterface = nil
        retainedSidebarController = nil
        retainedFormulaMenu = nil

        BPPreferences.sortColumnIdentifier = savedSortColumn
        BPPreferences.sortAscending = savedSortAscending
        BPPreferences.lastSelectedSidebarRow = savedSidebarRow
        BPPreferences.backgroundCheckEnabled = savedBackgroundCheck
        BPPreferences.backgroundCheckInterval = savedBackgroundInterval
        BPPreferences.greedyCaskUpgrades = savedGreedy
        BPPreferences.automaticAppUpdateCheckEnabled = savedAutoAppUpdates
        BPPreferences.showMenuBarExtra = savedShowMenuBarExtra
        (NSApp.delegate as? BPAppDelegate)?.updateMenuBarExtra()
        }
        super.tearDown()
    }

    private func populateMockHomebrewCatalog() {
        let manager = BPHomebrewManager.sharedManager()
        let installed = mockInterface.listMode(.installed) ?? []
        let installedCasks = mockInterface.listMode(.installedCasks) ?? []
        let leaves = mockInterface.listMode(.leaves) ?? []
        let pinned = mockInterface.listMode(.pinned) ?? []
        let outdated = mockInterface.listMode(.outdated) ?? []
        let outdatedCasks = mockInterface.listMode(.outdatedCasks) ?? []
        let allFormulae = mockInterface.listMode(.all) ?? []
        let allCasks = mockInterface.listMode(.allCasks) ?? []
        let repos = mockInterface.listMode(.repositories) ?? []

        manager.setValue(installed, forKey: "installedFormulae")
        manager.setValue(installedCasks, forKey: "installedCasks")
        manager.setValue(leaves, forKey: "leavesFormulae")
        manager.setValue(pinned, forKey: "pinnedFormulae")
        manager.setValue(outdated, forKey: "outdatedFormulae")
        manager.setValue(outdatedCasks, forKey: "outdatedCasks")
        manager.setValue(allFormulae, forKey: "allFormulae")
        manager.setValue(allCasks, forKey: "allCasks")
        manager.setValue(repos, forKey: "repositoriesFormulae")
        manager.setValue([BPFormula](), forKey: "searchFormulae")
    }

    private func makeWiredHomebrewViewController(outWindow: inout NSWindow?) -> BPHomebrewViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let vc = BPHomebrewViewController()
        let rootView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1000, height: 680))
        vc.view = rootView
        window.contentView?.addSubview(rootView)

        let formulaeSplitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 120, width: 800, height: 480))
        let tableView = BPFormulaeTableView(frame: scrollView.bounds)
        scrollView.documentView = tableView
        let selectedFormulaContainer = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 120))
        formulaeSplitView.addSubview(scrollView)
        formulaeSplitView.addSubview(selectedFormulaContainer)

        let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        for idx in 0..<4 {
            let item = NSTabViewItem(identifier: NSNumber(value: idx))
            tabView.addTabViewItem(item)
        }
        rootView.addSubview(tabView)

        let infoLabel = NSTextField(labelWithString: "")
        rootView.addSubview(infoLabel)
        let formulaMenu = NSMenu(title: "Formula")
        for title in [
            "Install Formula",
            "Uninstall Formula",
            "Update Formula",
            "More Information",
            "Formula Website",
            "Pin Formula",
            "Unpin Formula",
            "Install Formula with Options..."
        ] {
            formulaMenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        }
        retainedFormulaMenu = formulaMenu

        let sidebarController = BPSideBarController()
        retainedSidebarController = sidebarController
        let outline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        rootView.addSubview(outline)
        sidebarController.sidebar = outline
        outline.dataSource = sidebarController
        outline.delegate = sidebarController
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)

        vc.setValue(formulaeSplitView, forKey: "formulaeSplitView")
        vc.scrollView_formulae = scrollView
        vc.formulaeTableView = tableView
        vc.setValue(selectedFormulaContainer, forKey: "selectedFormulaView")
        vc.tabView = tabView
        vc.label_information = infoLabel
        vc.menu_formula = formulaMenu
        vc.sidebarController = sidebarController

        vc.viewDidLoad()
        vc.homebrewManagerFinishedUpdating(BPHomebrewManager.sharedManager())

        outWindow = window
        return vc
    }

    func testEndToEndAllTenPackageListModesAndSearchThroughHomebrewViewController() {
        var window: NSWindow?
        let vc = makeWiredHomebrewViewController(outWindow: &window)
        guard let listHost = vc.installedPackageListHost,
              let toolbar = vc.toolbar else {
            XCTFail("Expected installedPackageListHost and toolbar")
            return
        }
        XCTAssertNil(vc.loadingView, "Loading overlay must be dismissed when catalog finishes updating")

        struct ModeSpec {
            let row: FormulaeSideBarItem
            let expectedCount: Int
            let sampleName: String
            let isCask: Bool
            let expectedToolbarModeWhenSelected: BPToolbarMode
        }

        let modes: [ModeSpec] = [
            ModeSpec(row: .installed, expectedCount: 3, sampleName: "mockwget", isCask: false, expectedToolbarModeWhenSelected: .uninstall),
            ModeSpec(row: .installedCasks, expectedCount: 2, sampleName: "mockchrome", isCask: true, expectedToolbarModeWhenSelected: .uninstall),
            ModeSpec(row: .outdated, expectedCount: 1, sampleName: "mockgit", isCask: false, expectedToolbarModeWhenSelected: .updateSingle),
            ModeSpec(row: .outdatedCasks, expectedCount: 1, sampleName: "mockchrome", isCask: true, expectedToolbarModeWhenSelected: .updateSingle),
            ModeSpec(row: .all, expectedCount: 4, sampleName: "mockhtop", isCask: false, expectedToolbarModeWhenSelected: .install),
            ModeSpec(row: .allCasks, expectedCount: 3, sampleName: "mockfirefox", isCask: true, expectedToolbarModeWhenSelected: .install),
            ModeSpec(row: .leaves, expectedCount: 1, sampleName: "mockwget", isCask: false, expectedToolbarModeWhenSelected: .uninstall),
            ModeSpec(row: .pinned, expectedCount: 1, sampleName: "mockgit", isCask: false, expectedToolbarModeWhenSelected: .uninstall),
            ModeSpec(row: .repositories, expectedCount: 2, sampleName: "homebrew/core", isCask: false, expectedToolbarModeWhenSelected: .untap)
        ]

        for mode in modes {
            let sidebarRow = Int(mode.row.rawValue)
            vc.sidebarController?.sidebar?.selectRowIndexes(IndexSet(integer: sidebarRow), byExtendingSelection: false)
            vc.sourceListSelectionDidChange()

            XCTAssertEqual(listHost.rowCount, mode.expectedCount, "Row count mismatch for sidebar row \(sidebarRow)")
            XCTAssertGreaterThan(vc.label_information?.stringValue.count ?? 0, 0)

            if mode.row == .repositories {
                listHost.deselectAll()
                XCTAssertEqual(toolbar.currentMode, .tap)
            }

            XCTAssertTrue(
                listHost.selectPackage(named: mode.sampleName, cask: mode.isCask),
                "Expected package \(mode.sampleName) in sidebar row \(sidebarRow)"
            )
            if mode.row == .repositories {
                let selectedRepo = vc.selectedFormula()
                XCTAssertEqual(selectedRepo?.name, mode.sampleName)
            } else {
                XCTAssertEqual(vc.currentFormula?.name, mode.sampleName)
            }
            XCTAssertEqual(
                toolbar.currentMode,
                mode.expectedToolbarModeWhenSelected,
                "Unexpected toolbar mode for sidebar row \(sidebarRow)"
            )
        }

        // 10th mode: Search across formulae and casks
        BPHomebrewManager.sharedManager().setValue(nil, forKey: "searchFormulae")
        vc.performSearch(with: "mock")
        let searchDeadline = Date(timeIntervalSinceNow: 1.5)
        while (BPHomebrewManager.sharedManager().searchFormulae ?? []).isEmpty && searchDeadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        vc.homebrewManager(
            BPHomebrewManager.sharedManager(),
            didUpdateSearchResults: BPHomebrewManager.sharedManager().searchFormulae
        )
        XCTAssertGreaterThan(listHost.rowCount, 0, "Search mode must populate BPInstalledPackageListHost")
        XCTAssertTrue(listHost.selectPackage(named: "mockwget", cask: false))
        XCTAssertEqual(vc.currentFormula?.name, "mockwget")

        // Information commands reveal the inspector without creating a popover.
        var inspectorRequests = 0
        vc.onShowPackageInspector = { inspectorRequests += 1 }
        vc.showFormulaInfo(nil)
        XCTAssertEqual(inspectorRequests, 1)

        // Clear search and verify restoration of previous sidebar row
        vc.performSearch(with: "")
        XCTAssertFalse(vc.searching)
    }

    func testEndToEndPinAndUnpinFormulaThroughHomebrewViewController() {
        var window: NSWindow?
        let vc = makeWiredHomebrewViewController(outWindow: &window)
        guard let listHost = vc.installedPackageListHost else {
            XCTFail("Expected installedPackageListHost")
            return
        }

        vc.sidebarController?.sidebar?.selectRowIndexes(
            IndexSet(integer: Int(FormulaeSideBarItem.installed.rawValue)),
            byExtendingSelection: false
        )
        vc.sourceListSelectionDidChange()
        XCTAssertTrue(listHost.selectPackage(named: "mockwget", cask: false))
        XCTAssertFalse(vc.currentFormulaPinned)

        vc.pinSelectedFormula(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        XCTAssertFalse((NSApp.delegate as? BPAppDelegate)?.runningBackgroundTask ?? false)

        XCTAssertTrue(listHost.selectPackage(named: "mockgit", cask: false))
        XCTAssertTrue(vc.currentFormulaPinned)
        vc.unpinSelectedFormula(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        XCTAssertFalse((NSApp.delegate as? BPAppDelegate)?.runningBackgroundTask ?? false)
    }

    func testEndToEndUnifiedUpdatesDashboardFilteringSelectionAndActions() {
        // Add an unpinned outdated formula alongside pinned mockgit and outdated cask mockchrome
        let manager = BPHomebrewManager.sharedManager()
        let outdatedGit = BPFormula.formula(withName: "mockgit", version: "2.43.0", andLatestVersion: "2.44.0")
        let outdatedNode = BPFormula.formula(withName: "mocknode", version: "20.0.0", andLatestVersion: "21.0.0")
        let outdatedChrome = BPFormula.formula(withName: "mockchrome", version: "120.0", andLatestVersion: "121.0")
        outdatedChrome.cask = true
        manager.setValue([outdatedGit, outdatedNode], forKey: "outdatedFormulae")
        manager.setValue([outdatedChrome], forKey: "outdatedCasks")

        var window: NSWindow?
        let vc = makeWiredHomebrewViewController(outWindow: &window)
        guard let updatesHost = vc.unifiedUpdatesHost,
              let toolbar = vc.toolbar else {
            XCTFail("Expected unifiedUpdatesHost and toolbar")
            return
        }

        vc.showUnifiedUpdates(nil)
        XCTAssertEqual(vc.sidebarController?.sidebar?.selectedRow, Int(FormulaeSideBarItem.unifiedUpdates.rawValue))
        XCTAssertFalse(updatesHost.isEmpty)
        XCTAssertTrue(updatesHost.hasEligibleUpdates)
        XCTAssertTrue(updatesHost.hasFormulaUpdates)
        XCTAssertTrue(updatesHost.hasCaskUpdates)
        XCTAssertEqual(updatesHost.rowCount, 3)

        // Select All Eligible skips pinned mockgit and selects mocknode + mockchrome
        updatesHost.selectAllEligible()
        XCTAssertEqual(updatesHost.selectedCount, 2)
        XCTAssertEqual(updatesHost.selectedFormulaNames, ["mocknode"])
        XCTAssertEqual(updatesHost.selectedCaskNames, ["mockchrome"])
        XCTAssertEqual(toolbar.currentMode, .updateMany)

        // Group selection buttons
        updatesHost.selectFormulaGroup()
        XCTAssertEqual(updatesHost.selectedFormulaNames, ["mocknode"])
        XCTAssertEqual(updatesHost.selectedCaskNames.count, 0)
        XCTAssertEqual(toolbar.currentMode, .updateSingle)

        updatesHost.selectCaskGroup()
        XCTAssertEqual(updatesHost.selectedFormulaNames.count, 0)
        XCTAssertEqual(updatesHost.selectedCaskNames, ["mockchrome"])
        XCTAssertEqual(toolbar.currentMode, .updateSingle)

        // Filter query
        updatesHost.filterQuery = "chrome"
        XCTAssertEqual(updatesHost.filterQuery, "chrome")
        updatesHost.filterQuery = ""

        // Clear selection
        updatesHost.clearSelection()
        XCTAssertEqual(updatesHost.selectedCount, 0)
        XCTAssertEqual(toolbar.currentMode, .default)
    }

    func testEndToEndDoctorAndUpdateConsoleToolsRunStreamAndClear() {
        let doctorVC = BPDoctorViewController(nibName: nil, bundle: nil)
        _ = doctorVC.view
        guard let doctorHost = doctorVC.consoleHost,
              let doctorTextView = doctorVC.doctorTextView else {
            XCTFail("Expected doctor consoleHost and doctorTextView")
            return
        }

        doctorHost.onRun?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        doctorTextView.flushPendingOutput()
        XCTAssertFalse(doctorHost.isRunning)
        XCTAssertTrue(doctorTextView.string.contains("MOCK_DOCTOR_OK"))
        XCTAssertTrue(doctorTextView.string.contains("Checking for common problems..."))
        XCTAssertTrue(doctorTextView.string.contains("MOCK_DOCTOR_DONE"))

        doctorHost.onClear?()
        XCTAssertEqual(doctorTextView.string, "")

        let updateVC = BPUpdateViewController(nibName: nil, bundle: nil)
        _ = updateVC.view
        guard let updateHost = updateVC.consoleHost,
              let updateTextView = updateVC.updateTextView else {
            XCTFail("Expected update consoleHost and updateTextView")
            return
        }

        updateHost.onRun?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        updateTextView.flushPendingOutput()
        XCTAssertFalse(updateHost.isRunning)
        XCTAssertTrue(updateTextView.string.contains("MOCK_UPDATE_OK"))

        updateHost.onClear?()
        XCTAssertEqual(updateTextView.string, "")
    }

    func testEndToEndServicesControllerStartStopRestartDetailsAndCopyOutput() {
        let servicesVC = BPServicesViewController(nibName: nil, bundle: nil)
        _ = servicesVC.view
        guard let servicesHost = servicesVC.servicesHost,
              let tableView = servicesVC.tableView,
              let detailsText = servicesVC.detailsText else {
            XCTFail("Expected servicesHost, tableView, and detailsText")
            return
        }

        servicesVC.refreshServices()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        XCTAssertEqual(tableView.numberOfRows, 2)

        // Select running service mockpostgres (row 0)
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        NotificationCenter.default.post(name: NSTableView.selectionDidChangeNotification, object: tableView)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))

        XCTAssertTrue(detailsText.string.contains("mockpostgres"))
        XCTAssertTrue(detailsText.string.contains("/cakebrew-mock-missing/service.plist"))

        // Copy raw output to pasteboard
        NSPasteboard.general.clearContents()
        servicesHost.onCopyOutput?()
        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(copied.contains("\"name\":\"mockpostgres\""))

        // Stop, Restart, and Start operations through SwiftUI host callbacks
        servicesHost.onStop?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertFalse(servicesVC.operationInFlight)

        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        NotificationCenter.default.post(name: NSTableView.selectionDidChangeNotification, object: tableView)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

        servicesHost.onRestart?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertFalse(servicesVC.operationInFlight)

        // Select stopped service mockredis (row 1) and start it
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        NotificationCenter.default.post(name: NSTableView.selectionDidChangeNotification, object: tableView)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

        servicesHost.onStart?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertFalse(servicesVC.operationInFlight)
    }

    private func runSingleInstallationOperation(
        _ op: BPWindowOperation,
        formulae: [BPFormula]?,
        options: [String]?,
        zap: Bool,
        expectedMarker: String
    ) {
        let wc = BPInstallationWindowController(windowNibName: "BPInstallationWindow")
        wc.windowOperation = op
        wc.formulae = formulae
        wc.options = options
        wc.zapCask = zap

        _ = wc.window
        wc.windowDidLoad()
        guard let installHost = wc.installationHost,
              let recordTextView = wc.recordTextView else {
            XCTFail("Expected installationHost and recordTextView")
            return
        }
        _ = installHost

        var completedFlag = false
        wc.completionBlock = { completed in
            completedFlag = completed
        }
        wc.executeInstallation()

        let deadline = Date(timeIntervalSinceNow: 5.0)
        while wc.isRunningTask && deadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertFalse(wc.isRunningTask, "Installation task must finish")
        recordTextView.flushPendingOutput()
        wc.cleanupAfterTask()
        XCTAssertTrue(completedFlag, "Operation \(expectedMarker) should report completion=YES")
        XCTAssertTrue(
            recordTextView.string.contains(expectedMarker),
            "Expected '\(expectedMarker)' in transcript, got: \(recordTextView.string)"
        )
    }

    func testEndToEndInstallationWindowControllerAllOperations() {
        let firefoxCask = BPFormula.formula(withName: "mockfirefox")
        firefoxCask.cask = true
        let chromeCask = BPFormula.formula(withName: "mockchrome")
        chromeCask.cask = true

        runSingleInstallationOperation(
            .install,
            formulae: [BPFormula.formula(withName: "mockhtop")],
            options: ["--with-debug"],
            zap: false,
            expectedMarker: "MOCK_INSTALL_OK"
        )

        runSingleInstallationOperation(
            .install,
            formulae: [firefoxCask],
            options: nil,
            zap: false,
            expectedMarker: "MOCK_INSTALL_CASK_OK"
        )

        runSingleInstallationOperation(
            .uninstall,
            formulae: [BPFormula.formula(withName: "mockwget")],
            options: nil,
            zap: false,
            expectedMarker: "MOCK_UNINSTALL_OK"
        )

        runSingleInstallationOperation(
            .uninstall,
            formulae: [chromeCask],
            options: nil,
            zap: false,
            expectedMarker: "MOCK_UNINSTALL_CASK_OK"
        )

        runSingleInstallationOperation(
            .uninstall,
            formulae: [chromeCask],
            options: nil,
            zap: true,
            expectedMarker: "MOCK_UNINSTALL_CASK_ZAP_OK"
        )

        runSingleInstallationOperation(
            .upgrade,
            formulae: [BPFormula.formula(withName: "mockgit")],
            options: nil,
            zap: false,
            expectedMarker: "MOCK_UPGRADE_OK"
        )

        runSingleInstallationOperation(
            .tap,
            formulae: [BPFormula.formula(withName: "homebrew/cask-fonts")],
            options: nil,
            zap: false,
            expectedMarker: "MOCK_TAP_OK"
        )

        runSingleInstallationOperation(
            .untap,
            formulae: [BPFormula.formula(withName: "homebrew/core")],
            options: nil,
            zap: false,
            expectedMarker: "MOCK_UNTAP_OK"
        )

        runSingleInstallationOperation(
            .cleanup,
            formulae: nil,
            options: nil,
            zap: false,
            expectedMarker: "MOCK_CLEANUP_OK"
        )
    }

    func testEndToEndFormulaOptionsWindowControllerLoadsOptionsTogglesAndReturnsSelection() {
        let formula = BPFormula.formula(withName: "mockwget")
        formula.needsInformation = true
        let options = (formula.options as? [BPFormulaOption]) ?? []
        XCTAssertEqual(options.count, 2, "Mock formula info must parse --with-debug and --HEAD options")

        let wc = BPFormulaOptionsWindowController(windowNibName: "BPFormulaOptionsWindow")
        wc.formula = formula
        let availableOptions = NSMutableArray()
        for option in options {
            let entry = NSMutableDictionary(dictionary: [
                "formulaOptionCommand": option.name ?? "",
                "isFormulaOptionCommandApplied": NSNumber(value: false),
                "formulaOptionDescription": option.explanation ?? ""
            ])
            availableOptions.add(entry)
        }
        wc.availableOptions = availableOptions
        _ = wc.window

        XCTAssertNotNil(wc.optionsHost)
        XCTAssertEqual(wc.allSelectedOptions().count, 0)

        wc.optionsHost?.setApplied(true, forOptionNamed: "--with-debug")
        wc.optionsHost?.setApplied(true, forOptionNamed: "--HEAD")
        XCTAssertEqual(wc.allSelectedOptions() as? [String], ["--with-debug", "--HEAD"])

        wc.optionsHost?.setApplied(false, forOptionNamed: "--HEAD")
        XCTAssertEqual(wc.allSelectedOptions() as? [String], ["--with-debug"])
    }

    func testEndToEndAutoremoveWindowControllerPreviewAndReviewedRemoval() {
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = BPAutoremoveWindowController.present(
            for: parent,
            interface: mockInterface,
            manager: BPHomebrewManager.sharedManager()
        )
        guard let host = controller.autoremoveHost,
              let outputView = controller.outputView,
              let statusLabel = controller.statusLabel,
              let removeButton = controller.removeButton else {
            XCTFail("Expected autoremoveHost, outputView, statusLabel, and removeButton")
            return
        }

        // Wait for previewAutoremoveWithProgress: to complete
        let previewDeadline = Date(timeIntervalSinceNow: 2.0)
        while controller.busy && previewDeadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertTrue(removeButton.isEnabled)
        XCTAssertTrue(outputView.string.contains("mockunused"))

        // Trigger reviewed removal via SwiftUI host callback
        host.onRemove?()
        let removeDeadline = Date(timeIntervalSinceNow: 2.0)
        while controller.busy && removeDeadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        outputView.flushPendingOutput()
        XCTAssertTrue(outputView.string.contains("MOCK_AUTOREMOVE_OK"))
        XCTAssertTrue(statusLabel.stringValue.contains("removed"))

        // Close the sheet
        host.onCancelOrClose?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.10))
        XCTAssertFalse((NSApp.delegate as? BPAppDelegate)?.runningBackgroundTask ?? false)
    }

    func testEndToEndBundleWindowControllerImportAndExportFlows() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let brewfileURL = tempDir.appendingPathComponent("Brewfile")
        let brewfileContents = "brew \"mockwget\"\ncask \"mockchrome\"\ntap \"homebrew/core\"\n"
        try brewfileContents.write(to: brewfileURL, atomically: true, encoding: .utf8)

        let plan = try BPBrewfilePlan.plan(
            with: brewfileURL,
            inventories: [
                "brew": ["mockwget"],
                "cask": [],
                "tap": ["homebrew/core"]
            ]
        )
        XCTAssertTrue(plan.canInstall)

        // 1. Run Brewfile Import flow
        let importWC = BPBundleWindowController(windowNibName: "BPBundleWindow")
        _ = importWC.window
        importWC.windowDidLoad()
        importWC.runImportOperation(with: plan)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))

        guard let importTextView = importWC.textViewImport else {
            XCTFail("Expected textViewImport")
            return
        }
        importTextView.flushPendingOutput()
        XCTAssertTrue(
            importTextView.string.contains("MOCK_IMPORT_OK"),
            "Expected MOCK_IMPORT_OK in import output, got: \(importTextView.string)"
        )

        // 2. Run Brewfile Export flow
        let exportURL = tempDir.appendingPathComponent("ExportedBrewfile")
        let exportWC = BPBundleWindowController(windowNibName: "BPBundleWindow")
        _ = exportWC.window
        exportWC.windowDidLoad()
        exportWC.runExportOperation(withFile: exportURL)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))

        XCTAssertEqual(exportWC.buttonClose?.isEnabled, true)
        XCTAssertNotNil(exportWC.bundleHost)
        XCTAssertFalse(exportWC.exportOperation?.isRunning() ?? false)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testEndToEndOverlaysDisabledLoadingEmptyStateAndPreferencesHost() {
        // 1. BPDisabledView + BPDisabledHost
        let disabledView = BPDisabledView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        var retryCount = 0
        disabledView.retryHandler = {
            retryCount += 1
        }
        disabledView.showDiscoveryResult(BPHomebrewDiscoveryResult.missing.rawValue, checking: true)
        disabledView.showDiscoveryResult(BPHomebrewDiscoveryResult.missing.rawValue, checking: false)
        disabledView.showDiscoveryResult(BPHomebrewDiscoveryResult.invalidShell.rawValue, checking: false)
        disabledView.showDiscoveryResult(BPHomebrewDiscoveryResult.checkFailed.rawValue, checking: false)
        guard let disabledHost = disabledView.disabledHost else {
            XCTFail("Expected disabledHost")
            return
        }
        disabledHost.onRetry?()
        XCTAssertEqual(retryCount, 1)

        // 2. BPLoadingView + BPLoadingHost
        let loadingView = BPLoadingView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        guard let loadingHost = loadingView.loadingHost else {
            XCTFail("Expected loadingHost")
            return
        }
        XCTAssertNotNil(loadingHost.viewController.view)

        // 3. BPEmptyStateView + BPEmptyStateHost
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        let emptyState = BPEmptyState.state(
            forSidebarRow: Int(FormulaeSideBarItem.outdated.rawValue),
            searching: false
        )
        BPEmptyStateView.presentState(emptyState, over: container)
        XCTAssertEqual(container.subviews.count, 1)
        BPEmptyStateView.presentState(nil, over: container)
        XCTAssertEqual(container.subviews.count, 0)

        // 4. BPPreferencesWindowController + BPPreferencesHost
        let prefsWC = BPPreferencesWindowController()
        guard let prefsHost = prefsWC.preferencesHost else {
            XCTFail("Expected preferencesHost")
            return
        }
        prefsHost.onBackgroundCheckChanged?(false)
        XCTAssertFalse(BPPreferences.backgroundCheckEnabled)
        prefsHost.onIntervalChanged?(86400.0)
        XCTAssertEqual(BPPreferences.backgroundCheckInterval, 86400.0, accuracy: 0.1)
        prefsHost.onGreedyChanged?(true)
        XCTAssertTrue(BPPreferences.greedyCaskUpgrades)
        prefsHost.onAutomaticAppUpdateCheckChanged?(false)
        XCTAssertFalse(BPPreferences.automaticAppUpdateCheckEnabled)

        // 5. BPAppUpdateHost
        let updateHost = BPAppUpdateHost(currentVersion: "2.0.0", automaticCheckEnabled: true)
        XCTAssertNotNil(updateHost.window)
        XCTAssertEqual(updateHost.currentVersionString, "2.0.0")
        let gen = updateHost.beginCheck(currentVersion: "2.0.0")
        XCTAssertTrue(updateHost.isChecking)
        XCTAssertTrue(updateHost.receiveFeedUnavailable(generation: gen))
        XCTAssertFalse(updateHost.isChecking)
        XCTAssertFalse(updateHost.isUpdateAvailable)
    }

    func testEndToEndAboutWindowBrewfileReviewCommandPaletteAndMenuBarExtra() throws {
        // 1. SwiftUI Tahoe About Window (DCOAboutWindowController + BPAboutWindowHost)
        let aboutWC = DCOAboutWindowController()
        aboutWC.appName = "Cakebrew"
        aboutWC.appVersion = "Version 2.0 (Build 200)"
        aboutWC.appCopyright = "Copyright © Cakebrew Contributors"
        aboutWC.appCredits = NSAttributedString(
            string: NSLocalizedString("Credits: Bruno Philipe & Contributors", comment: "")
        )
        aboutWC.setValue(
            NSAttributedString(string: NSLocalizedString("Acknowledgements: Sparkle & DCOAboutWindow", comment: "")),
            forKey: "appAcknowledgements"
        )
        _ = aboutWC.window
        aboutWC.windowDidLoad()

        XCTAssertNotNil(aboutWC.aboutHost)
        XCTAssertNotNil(aboutWC.creditsTextView)
        XCTAssertEqual(aboutWC.aboutHost?.selectedTabIndex, 0)
        XCTAssertTrue(aboutWC.creditsTextView?.string.contains("Bruno Philipe") == true)

        aboutWC.showAcknowledgements(nil)
        XCTAssertEqual(aboutWC.aboutHost?.selectedTabIndex, 1)
        XCTAssertTrue(aboutWC.creditsTextView?.string.contains("Acknowledgements") == true)

        aboutWC.aboutHost?.selectTab(at: 0)
        XCTAssertEqual(aboutWC.aboutHost?.selectedTabIndex, 0)
        XCTAssertTrue(aboutWC.creditsTextView?.string.contains("Credits:") == true)

        let copiedVersion = aboutWC.aboutHost?.copyVersionInfoToPasteboard()
        XCTAssertEqual(copiedVersion, "Cakebrew (Version 2.0 (Build 200))")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), copiedVersion)

        // 2. SwiftUI Brewfile Review Host (BPBundleWindowController + BPBrewfileReviewHost)
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let brewfileURL = tempDir.appendingPathComponent("Brewfile")
        let brewfileContents = "brew \"mockwget\"\ncask \"mockchrome\"\ntap \"homebrew/core\"\n"
        try brewfileContents.write(to: brewfileURL, atomically: true, encoding: .utf8)

        let plan = try BPBrewfilePlan.plan(
            with: brewfileURL,
            inventories: [
                "brew": ["mockwget"],
                "cask": [],
                "tap": ["homebrew/core"]
            ]
        )
        let reviewHost = BPBundleWindowController.reviewHost(for: plan, fileName: "Brewfile", error: nil)
        let reviewEntriesView = reviewHost.entriesTextView
        XCTAssertEqual(reviewEntriesView.accessibilityIdentifier(), "brewfile.review.entries")
        XCTAssertEqual(reviewHost.totalEntryCount, 3)
        XCTAssertEqual(reviewHost.installedCount, 2)
        XCTAssertEqual(reviewHost.missingCount, 1)
        XCTAssertTrue(reviewHost.canInstall)
        XCTAssertTrue(reviewEntriesView.string.contains("mockwget"))
        try? FileManager.default.removeItem(at: tempDir)

        // 3. Command Palette (⌘K) + Unified Window Subtitle Synchronization
        var mainWindow: NSWindow?
        let vc = makeWiredHomebrewViewController(outWindow: &mainWindow)
        XCTAssertEqual(mainWindow?.subtitle, vc.label_information?.stringValue)
        XCTAssertGreaterThan(mainWindow?.subtitle.count ?? 0, 0)

        vc.showCommandPalette(nil)
        guard let palette = vc.commandPaletteHost else {
            XCTFail("Expected commandPaletteHost")
            return
        }
        XCTAssertGreaterThanOrEqual(palette.filteredCount, 19)

        palette.query = "Doctor"
        XCTAssertGreaterThanOrEqual(palette.filteredCount, 1)
        XCTAssertEqual(palette.selectedItemID, "nav.doctor")
        XCTAssertTrue(palette.executeSelectedItem())
        XCTAssertEqual(vc.sidebarController?.sidebar?.selectedRow, Int(FormulaeSideBarItem.doctor.rawValue))
        XCTAssertEqual(mainWindow?.subtitle, vc.label_information?.stringValue)

        // Select a package via Command Palette
        vc.showCommandPalette(nil)
        palette.query = "mockwget"
        XCTAssertGreaterThanOrEqual(palette.filteredCount, 1)
        XCTAssertTrue(palette.executeItem(withID: "pkg:formula:mockwget"))
        XCTAssertEqual(vc.sidebarController?.sidebar?.selectedRow, Int(FormulaeSideBarItem.installed.rawValue))
        XCTAssertEqual(vc.selectedFormula()?.name, "mockwget")

        // 4. Optional Menu Bar Extra in Settings & BPAppDelegate
        let appDelegate = BPAppDelegate()
        XCTAssertNil(appDelegate.statusItem)

        BPPreferences.showMenuBarExtra = true
        appDelegate.updateMenuBarExtra()
        XCTAssertNotNil(appDelegate.statusItem)
        XCTAssertNotNil(appDelegate.statusItem?.menu)
        XCTAssertGreaterThanOrEqual(appDelegate.statusItem?.menu?.numberOfItems ?? 0, 5)

        BPPreferences.showMenuBarExtra = false
        appDelegate.updateMenuBarExtra()
        XCTAssertNil(appDelegate.statusItem)
    }

    func testEndToEndStatusBarHostPopoverCopyAndUnifiedWindowStyling() {
        // 1. SwiftUI Tahoe Status Bar Host (BPStatusBarHost + BPHomebrewViewController)
        var mainWindow: NSWindow?
        let vc = makeWiredHomebrewViewController(outWindow: &mainWindow)
        guard let statusBarHost = vc.statusBarHost else {
            XCTFail("Expected statusBarHost")
            return
        }
        XCTAssertEqual(statusBarHost.message, vc.label_information?.stringValue)
        XCTAssertGreaterThan(statusBarHost.installedCount, 0)
        XCTAssertGreaterThan(statusBarHost.outdatedCount, 0)

        NotificationCenter.default.post(name: BPTask.didBeginBackgroundActivityNotification, object: nil)
        XCTAssertTrue(statusBarHost.isBusy)
        NotificationCenter.default.post(name: BPTask.didEndBackgroundActivityNotification, object: nil)
        XCTAssertFalse(statusBarHost.isBusy)

        statusBarHost.triggerUnifiedUpdates()
        XCTAssertEqual(vc.sidebarController?.sidebar?.selectedRow, Int(FormulaeSideBarItem.unifiedUpdates.rawValue))
        XCTAssertEqual(statusBarHost.message, vc.label_information?.stringValue)

        statusBarHost.triggerCommandPalette()
        XCTAssertNotNil(vc.commandPaletteHost)
        vc.dismissCommandPalette(nil)

        // 2. Nibless BPFormulaPopoverViewController + BPFormulaInformationHost copyInformationToPasteboard
        let popoverVC = BPFormulaPopoverViewController()
        XCTAssertNotNil(popoverVC.view)
        XCTAssertNotNil(popoverVC.formulaPopover)

        let infoHost = BPFormulaInformationHost()
        let gen = infoHost.begin(name: "mockwget", cask: false, infoType: BPFormulaInfoType.general.rawValue)
        infoHost.receive(
            information: "mockwget: Internet file retriever",
            website: URL(string: "https://www.gnu.org/software/wget/"),
            name: "mockwget",
            cask: false,
            infoType: BPFormulaInfoType.general.rawValue,
            generation: gen
        )
        let copied = infoHost.copyInformationToPasteboard()
        XCTAssertEqual(copied, "mockwget: Internet file retriever")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), copied)

        // 3. BPMainWindowController unified toolbar style & sidebar thickness bounds + BPStyle Tahoe defaults
        let mainWC = BPMainWindowController(window: mainWindow)
        let sidebarScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        let contentContainer = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        mainWC.sidebarView = sidebarScroll
        mainWC.windowContentView = contentContainer
        mainWC.setUpViews()
        XCTAssertEqual(mainWindow?.toolbarStyle, .unified)
        guard let sidebarItem = mainWC.splitViewController?.splitViewItems.first else {
            XCTFail("Expected sidebar splitViewItem")
            return
        }
        XCTAssertEqual(sidebarItem.minimumThickness, 190.0, accuracy: 0.1)
        XCTAssertEqual(sidebarItem.maximumThickness, 280.0, accuracy: 0.1)
        XCTAssertEqual(BPStyle.toolbarSize(), .default)
        XCTAssertNotNil(BPStyle.defaultFixedWidthFont())
    }

    func testEndToEndSidebarHostInteractiveInspectorAndOperationAccessoryCards() {
        // 1. BPSideBarController + BPSidebarHost synchronization + programmatic cell fallback
        var mainWindow: NSWindow?
        let vc = makeWiredHomebrewViewController(outWindow: &mainWindow)
        guard let sidebarController = vc.sidebarController else {
            XCTFail("Expected sidebarController")
            return
        }
        XCTAssertNotNil(sidebarController.sidebarHost)
        XCTAssertEqual(sidebarController.sidebarHost.sectionCount, 3)
        XCTAssertEqual(sidebarController.sidebarHost.selectableRowCount, 13)
        XCTAssertGreaterThan(
            sidebarController.sidebarHost.badgeCount(forRowIndex: Int(FormulaeSideBarItem.installed.rawValue)),
            0
        )

        sidebarController.sidebarHost.selectRow(atIndex: Int(FormulaeSideBarItem.pinned.rawValue))
        XCTAssertEqual(sidebarController.sidebarHost.selectedRowIndex, Int(FormulaeSideBarItem.pinned.rawValue))
        XCTAssertEqual(sidebarController.sidebar?.selectedRow, Int(FormulaeSideBarItem.pinned.rawValue))

        // Programmatic cell builder fallback when NSOutlineView has no XIB cell templates
        let plainOutline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main"))
        plainOutline.addTableColumn(col)
        plainOutline.outlineTableColumn = col
        let groupItem = sidebarController.outlineView(plainOutline, child: 0, ofItem: nil)
        let headerCell = sidebarController.outlineView(plainOutline, viewFor: col, item: groupItem)
        XCTAssertTrue(headerCell is BPSidebarTableCellView)
        let rowItem = sidebarController.outlineView(plainOutline, child: 0, ofItem: groupItem)
        let mainCell = sidebarController.outlineView(plainOutline, viewFor: col, item: rowItem) as? BPSidebarTableCellView
        XCTAssertNotNil(mainCell)
        XCTAssertEqual(mainCell?.textField?.accessibilityIdentifier(), "sidebar.formulae.installed")
        XCTAssertNotNil(mainCell?.badgeView)

        // 2. Interactive Package Inspector (BPSelectedFormulaViewController + BPSelectedFormulaHost + BPHomebrewViewController)
        sidebarController.sidebarHost.selectRow(atIndex: Int(FormulaeSideBarItem.installed.rawValue))
        guard let selectedVC = vc.selectedFormulaeViewController,
              let inspectorHost = selectedVC.inspectorHost else {
            XCTFail("Expected selectedFormulaeViewController and inspectorHost")
            return
        }

        let wget = BPFormula.formula(withName: "mockwget", version: "1.21", andLatestVersion: "1.21")
        wget.setValue("/tmp (10 files, 1MB)", forKey: "installPath")
        wget.setValue("mockgit, openssl", forKey: "dependencies")
        selectedVC.formulae = [wget]

        let copiedPath = inspectorHost.copyInstallPathToPasteboard()
        XCTAssertEqual(copiedPath, "/tmp (10 files, 1MB)")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), copiedPath)

        inspectorHost.selectRelatedPackage(named: "mockgit")
        XCTAssertEqual(vc.sidebarController?.sidebar?.selectedRow, Int(FormulaeSideBarItem.installed.rawValue))
        XCTAssertEqual(vc.selectedFormula()?.name, "mockgit")

        // 3. SwiftUI Operation Accessory Cards (BPTapInputHost & BPCleanupPreviewHost)
        let tapAlert = BPPackageOperationPresenter.tapInputAlert()
        guard let tapHost = BPPackageOperationPresenter.tapInputHost(for: tapAlert) else {
            XCTFail("Expected tapInputHost")
            return
        }
        let tapField = tapHost.inputField
        XCTAssertFalse(tapHost.isValidFormat)
        tapHost.repositoryName = "scottdensmore/cakebrew"
        XCTAssertTrue(tapHost.isValidFormat)
        XCTAssertEqual(tapField.stringValue, "scottdensmore/cakebrew")

        let cleanupPreview = BPCleanupPreview.preview(
            fromOutput: "Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n"
                + "==> This operation would free approximately 49.2MB of disk space.\n"
        )
        let cleanupAlert = BPPackageOperationPresenter.cleanupAlert(for: cleanupPreview)
        guard let cleanupHost = BPPackageOperationPresenter.cleanupPreviewHost(for: cleanupAlert) else {
            XCTFail("Expected cleanupPreviewHost")
            return
        }
        XCTAssertEqual(cleanupHost.itemCount, 1)
        XCTAssertGreaterThan(cleanupHost.reclaimableBytes, 0)
        XCTAssertGreaterThan(cleanupHost.formattedByteCount.count, 0)
    }

    func testEndToEndConsoleDoctorDiagnosticsAndOperationSheetLogFilterCopy() {
        let doctorVC = BPDoctorViewController()
        doctorVC.loadView()
        guard let doctorHost = doctorVC.consoleHost,
              let doctorTextView = doctorVC.doctorTextView else {
            XCTFail("Expected doctorHost and doctorTextView")
            return
        }
        XCTAssertEqual(doctorHost.diagnosticSeverityRawValue, 0)

        doctorTextView.string = "Warning: Unlinked kegs found in Cellar\nWarning: Deprecated tap in use\nAll checks complete.\n"
        doctorHost.syncLogFromTextView()
        XCTAssertEqual(doctorHost.warningCount, 2)
        XCTAssertEqual(doctorHost.diagnosticSeverityRawValue, 3)
        XCTAssertEqual(doctorHost.totalLineCount, 3)
        doctorHost.filterQuery = "Unlinked"
        XCTAssertEqual(doctorHost.matchingLineCount, 1)
        let copiedDoctor = doctorHost.copyOutputToPasteboard()
        XCTAssertEqual(copiedDoctor, "Warning: Unlinked kegs found in Cellar")

        doctorHost.onClear?()
        XCTAssertEqual(doctorHost.totalLineCount, 0)
        XCTAssertEqual(doctorHost.diagnosticSeverityRawValue, 0)

        let updateVC = BPUpdateViewController()
        updateVC.loadView()
        guard let updateHost = updateVC.consoleHost,
              let updateTextView = updateVC.updateTextView else {
            XCTFail("Expected updateHost and updateTextView")
            return
        }
        updateTextView.string = "Already up-to-date.\n"
        updateHost.syncLogFromTextView()
        XCTAssertEqual(updateHost.diagnosticSeverityRawValue, 2)
        XCTAssertEqual(updateHost.copyOutputToPasteboard(), "Already up-to-date.\n")

        updateHost.onClear?()
        XCTAssertEqual(updateHost.totalLineCount, 0)
    }

    func testEndToEndServicesFilteringPathCopyBrewfileReviewFilterAndFormulaOptionsSearch() throws {
        // 1. BPServicesViewController + BPServicesHost status filter, query filter, and path copying
        let servicesVC = BPServicesViewController(nibName: nil, bundle: nil)
        _ = servicesVC.view
        guard let servicesHost = servicesVC.servicesHost,
              let tableView = servicesVC.tableView else {
            XCTFail("Expected servicesHost and tableView")
            return
        }

        servicesVC.refreshServices()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        XCTAssertEqual(tableView.numberOfRows, 2)
        XCTAssertEqual(servicesHost.totalCount, 2)
        XCTAssertEqual(servicesHost.runningCount, 1)
        XCTAssertEqual(servicesHost.stoppedCount, 1)
        XCTAssertEqual(servicesHost.errorCount, 0)

        // Select running service (mockpostgres) and verify service path syncing + copy
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        NotificationCenter.default.post(name: NSTableView.selectionDidChangeNotification, object: tableView)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        XCTAssertEqual(servicesHost.serviceFilePath, "/cakebrew-mock-missing/service.plist")
        XCTAssertEqual(servicesHost.logFilePath, "/cakebrew-mock-missing/service.log")
        XCTAssertEqual(servicesHost.copyServiceFilePathToPasteboard(), "/cakebrew-mock-missing/service.plist")
        XCTAssertEqual(servicesHost.copyLogPathToPasteboard(), "/cakebrew-mock-missing/service.log")

        // Filter by Running (statusFilterRawValue = 1)
        servicesHost.statusFilterRawValue = 1
        XCTAssertEqual(tableView.numberOfRows, 1)
        XCTAssertEqual(
            tableView.dataSource?.tableView?(tableView, objectValueFor: tableView.tableColumns.first, row: 0) as? String,
            "mockpostgres"
        )

        // Filter by Stopped (statusFilterRawValue = 2)
        servicesHost.statusFilterRawValue = 2
        XCTAssertEqual(tableView.numberOfRows, 1)
        XCTAssertEqual(
            tableView.dataSource?.tableView?(tableView, objectValueFor: tableView.tableColumns.first, row: 0) as? String,
            "mockredis"
        )

        // Reset status filter and filter by query
        servicesHost.statusFilterRawValue = 0
        servicesHost.filterQuery = "redis"
        XCTAssertEqual(tableView.numberOfRows, 1)
        servicesHost.filterQuery = ""
        XCTAssertEqual(tableView.numberOfRows, 2)

        // 2. BPBrewfileReviewHost status filter + search + copy
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let brewfileURL = tempDir.appendingPathComponent("Brewfile")
        let brewfileContents = "brew \"mockwget\"\ncask \"mockchrome\"\ntap \"homebrew/core\"\n"
        try brewfileContents.write(to: brewfileURL, atomically: true, encoding: .utf8)

        let plan = try BPBrewfilePlan.plan(
            with: brewfileURL,
            inventories: [
                "brew": ["mockwget"],
                "cask": [],
                "tap": ["homebrew/core"]
            ]
        )
        let reviewHost = BPBundleWindowController.reviewHost(for: plan, fileName: "Brewfile", error: nil)
        XCTAssertEqual(reviewHost.matchingEntryCount, 3)
        reviewHost.statusFilterRawValue = 2 // Missing only
        XCTAssertEqual(reviewHost.matchingEntryCount, 1)
        let copiedMissing = reviewHost.copySummaryToPasteboard()
        XCTAssertTrue(copiedMissing.contains("mockchrome"))
        reviewHost.statusFilterRawValue = 1 // Installed only
        XCTAssertEqual(reviewHost.matchingEntryCount, 2)
        reviewHost.statusFilterRawValue = 0
        reviewHost.filterQuery = "wget"
        XCTAssertEqual(reviewHost.matchingEntryCount, 1)
        try? FileManager.default.removeItem(at: tempDir)

        // 3. BPFormulaOptionsWindowController + BPFormulaOptionsHost search & clearAllAppliedOptions
        let formula = BPFormula.formula(withName: "mockwget")
        formula.needsInformation = true
        let options = (formula.options as? [BPFormulaOption]) ?? []
        let optionsWC = BPFormulaOptionsWindowController(windowNibName: "BPFormulaOptionsWindow")
        optionsWC.formula = formula
        let availableOptions = NSMutableArray()
        for option in options {
            let entry = NSMutableDictionary(dictionary: [
                "formulaOptionCommand": option.name ?? "",
                "isFormulaOptionCommandApplied": NSNumber(value: false),
                "formulaOptionDescription": option.explanation ?? ""
            ])
            availableOptions.add(entry)
        }
        optionsWC.availableOptions = availableOptions
        _ = optionsWC.window
        XCTAssertEqual(optionsWC.optionsHost?.filteredOptionCount, 2)
        optionsWC.optionsHost?.filterQuery = "debug"
        XCTAssertEqual(optionsWC.optionsHost?.filteredOptionCount, 1)
        optionsWC.optionsHost?.filterQuery = ""
        optionsWC.optionsHost?.setApplied(true, forOptionNamed: "--with-debug")
        optionsWC.optionsHost?.setApplied(true, forOptionNamed: "--HEAD")
        XCTAssertEqual(optionsWC.optionsHost?.appliedOptionCount, 2)
        optionsWC.optionsHost?.clearAllAppliedOptions()
        XCTAssertEqual(optionsWC.optionsHost?.appliedOptionCount, 0)
        XCTAssertEqual(optionsWC.allSelectedOptions().count, 0)
    }
}
