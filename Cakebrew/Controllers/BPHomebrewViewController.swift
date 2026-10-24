import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

// MARK: - Swift 6 Wave 8: BPHomebrewViewController

@objc(BPContentTab)
public enum BPContentTab: UInt, Sendable {
    @objc(kBPContentTabFormulae) case formulae = 0
    @objc(kBPContentTabDoctor) case doctor = 1
    @objc(kBPContentTabUpdate) case update = 2
    @objc(kBPContentTabServices) case services = 3
}

@MainActor
@objc(BPHomebrewViewController)
open class BPHomebrewViewController: NSViewController,
    BPDockMenuTarget,
    BPBrewfileImporting,
    BPNotificationNavigation,
    NSTableViewDelegate,
    BPFormulaeTableActionDelegate,
    BPSideBarControllerDelegate,
    BPSelectedFormulaViewControllerDelegate,
    BPHomebrewManagerDelegate,
    NSMenuDelegate,
    NSOpenSavePanelDelegate
{
    private static let kDefaultDetailPaneHeight: CGFloat = 120.0
    #if DEBUG
    private static let notificationSearchFixtureIdentifier = "mockvscode"
    #endif

    nonisolated(unsafe) private var _homebrewManager: BPHomebrewManager = BPHomebrewManager.sharedManager()
    private var didCommonInit: Bool = false

    @IBOutlet @objc open weak var sidebarController: BPSideBarController?
    @IBOutlet @objc open weak var formulaeTableView: BPFormulaeTableView?
    @IBOutlet @objc open weak var scrollView_formulae: NSScrollView?
    @IBOutlet @objc open weak var tabView: NSTabView?
    @IBOutlet @objc open weak var label_information: NSTextField?
    @IBOutlet @objc open weak var menu_formula: NSMenu?
    @IBOutlet @objc open weak var formulaeSplitView: NSSplitView?
    @IBOutlet @objc open weak var selectedFormulaView: NSView?
    @IBOutlet @objc open weak var backgroundActivityIndicator: NSProgressIndicator?
    @IBOutlet @objc open weak var mainWindowController: BPMainWindowController?

    @objc open private(set) var commandPaletteHost: BPCommandPaletteHost?
    @objc open private(set) var statusBarHost: BPStatusBarHost?

    // Cocoa bindings
    @objc dynamic open var enableUpgradeFormulasMenu: Bool = false
    @objc dynamic open var enableUpgradeAllMenu: Bool = false
    @objc dynamic open var currentFormula: BPFormula?

    @objc nonisolated public class func keyPathsForValuesAffectingCurrentFormulaPinned() -> Set<String> {
        ["currentFormula"]
    }

    @objc open var currentFormulaPinned: Bool {
        guard let currentFormula else { return false }
        return BPHomebrewManager.sharedManager().isFormulaPinned(currentFormula)
    }

    @objc open weak var appDelegate: BPAppDelegate?
    @objc open var lastSelectedSidebarIndex: Int = 0
    @objc open var hasAppliedDefaultDividerPosition: Bool = false

    private var _searchCoordinator: BPSearchCoordinator?
    @objc open var searchCoordinator: BPSearchCoordinator {
        get {
            if let existing = _searchCoordinator {
                return existing
            }
            let created = BPSearchCoordinator(
                performSearch: { query in
                    BPHomebrewManager.sharedManager().updateSearch(withName: query)
                },
                cancelSearch: {
                    BPHomebrewManager.sharedManager().cancelSearch()
                }
            )
            _searchCoordinator = created
            return created
        }
        set {
            _searchCoordinator = newValue
        }
    }

    @objc open var cleanupPreviewInFlight: Bool = false

    @objc open var searching: Bool {
        @objc(isSearching) get {
            searchCoordinator.searching
        }
    }

    @objc open var homebrewInstalled: Bool = true

    @objc(isHomebrewInstalled)
    nonisolated open func isHomebrewInstalled() -> Bool {
        MainActor.assumeIsolated {
            self.homebrewInstalled
        }
    }

    @objc open var formulaeDataSource: BPFormulaeDataSource?
    @objc open var installedPackageListHost: BPInstalledPackageListHost?
    @objc open var unifiedUpdatesHost: BPUnifiedUpdatesHost?
    @objc open var commandPaletteSheetWindow: NSWindow?
    @objc open var formulaOptionsWindowController: BPFormulaOptionsWindowController?
    @objc open var operationWindowController: NSWindowController?
    @objc open var updateViewController: BPUpdateViewController?
    @objc open var doctorViewController: BPDoctorViewController?
    @objc open var servicesViewController: BPServicesViewController?

    private var _formulaPopoverViewController: BPFormulaPopoverViewController?
    @objc open var formulaPopoverViewController: BPFormulaPopoverViewController {
        get {
            if let existing = _formulaPopoverViewController {
                return existing
            }
            let created = BPFormulaPopoverViewController()
            _ = created.view
            _formulaPopoverViewController = created
            return created
        }
        set {
            _formulaPopoverViewController = newValue
        }
    }

    @objc open var selectedFormulaeViewController: BPSelectedFormulaViewController?
    @objc open var toolbar: BPToolbar?
    @objc open var disabledView: BPDisabledView?
    @objc open var loadingView: BPLoadingView?

    public convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    @objc open func commonInit() {
        guard !didCommonInit else { return }
        didCommonInit = true

        _homebrewManager = BPHomebrewManager.sharedManager()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatesSnapshotChanged(_:)),
            name: Notification.Name(BPHomebrewManagerUpdatesSnapshotDidChangeNotification),
            object: _homebrewManager
        )
        self.enableUpgradeAllMenu = (_homebrewManager.updatesSnapshot?.hasEligibleUpdates == true)
        _homebrewManager.delegate = self

        let selectedVC = BPSelectedFormulaViewController()
        selectedVC.delegate = self
        self.selectedFormulaeViewController = selectedVC

        self.homebrewInstalled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveBackgroundActivityNotification(_:)),
            name: BPTask.didBeginBackgroundActivityNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveBackgroundActivityNotification(_:)),
            name: BPTask.didEndBackgroundActivityNotification,
            object: nil
        )
    }

    deinit {
        _homebrewManager.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc(updatesSnapshotChanged:)
    nonisolated open func updatesSnapshotChanged(_ notification: Notification) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.enableUpgradeAllMenu = (self._homebrewManager.updatesSnapshot?.hasEligibleUpdates == true)
                self.syncStatusBarHost()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.enableUpgradeAllMenu = (self._homebrewManager.updatesSnapshot?.hasEligibleUpdates == true)
                self.syncStatusBarHost()
            }
        }
    }

    @objc(didReceiveBackgroundActivityNotification:)
    nonisolated open func didReceiveBackgroundActivityNotification(_ notification: Notification) {
        let name = notification.name
        if name == BPTask.didBeginBackgroundActivityNotification {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.backgroundActivityIndicator?.startAnimation(self)
                    self.statusBarHost?.isBusy = true
                }
            } else {
                DispatchQueue.main.sync {
                    self.backgroundActivityIndicator?.startAnimation(self)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.statusBarHost?.isBusy = true
                }
            }
        } else if name == BPTask.didEndBackgroundActivityNotification {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.backgroundActivityIndicator?.stopAnimation(self)
                    self.statusBarHost?.isBusy = false
                }
            } else {
                DispatchQueue.main.sync {
                    self.backgroundActivityIndicator?.stopAnimation(self)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.statusBarHost?.isBusy = false
                }
            }
        }
    }

    open override func loadView() {
        if let nibName = self.nibName,
           !nibName.isEmpty,
           Bundle(for: BPHomebrewViewController.self).path(forResource: nibName, ofType: "nib") != nil {
            super.loadView()
            return
        }
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 520))
        let splitView = NSSplitView(frame: rootView.bounds)
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 120, width: 820, height: 400))
        let tableView = BPFormulaeTableView(frame: scrollView.bounds)
        scrollView.documentView = tableView
        let detailContainer = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 120))
        splitView.addSubview(scrollView)
        splitView.addSubview(detailContainer)
        let tab = NSTabView(frame: rootView.bounds)
        tab.tabViewType = .noTabsNoBorder
        tab.autoresizingMask = [.width, .height]
        for idx in 0...3 {
            let item = NSTabViewItem(identifier: "\(idx)")
            item.view = (idx == 0) ? splitView : NSView(frame: rootView.bounds)
            tab.addTabViewItem(item)
        }
        rootView.addSubview(tab)
        let infoLabel = NSTextField(labelWithString: "")
        let activity = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        activity.style = .spinning
        rootView.addSubview(infoLabel)
        rootView.addSubview(activity)
        self.formulaeSplitView = splitView
        self.scrollView_formulae = scrollView
        self.formulaeTableView = tableView
        self.selectedFormulaView = detailContainer
        self.tabView = tab
        self.label_information = infoLabel
        self.backgroundActivityIndicator = activity
        self.view = rootView
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        mainWindowController?.setUpViews()
        mainWindowController?.setContentViewHidden(true)

        let ds = BPFormulaeDataSource(mode: BPListMode.all.rawValue)
        self.formulaeDataSource = ds
        self.formulaeTableView?.dataSource = ds
        setUpInstalledPackageListHost()
        setUpUnifiedUpdatesHost()
        setUpStatusBarHost()

        if let sortColumn = BPPreferences.sortColumnIdentifier, !sortColumn.isEmpty {
            let ascending = BPPreferences.sortAscending
            let restored = NSSortDescriptor(key: sortColumn, ascending: ascending)
            formulaeTableView?.sortDescriptors = [restored]
            formulaeDataSource?.sortDescriptors = [restored]
            installedPackageListHost?.applySort(columnIdentifier: sortColumn, ascending: ascending)
        }
        formulaeTableView?.delegate = self
        formulaeTableView?.actionDelegate = self
        formulaeTableView?.setAccessibilityLabel(NSLocalizedString("Formulae", comment: ""))

        formulaeSplitView?.autosaveName = "BPFormulaeSplitView"

        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.formulae.rawValue) {
            let formulaeTab = tabView.tabViewItem(at: Int(BPContentTab.formulae.rawValue))
            formulaeTab.view = formulaeSplitView
        }

        let updateVC = BPUpdateViewController(nibName: nil, bundle: nil)
        self.updateViewController = updateVC
        let updateView = updateVC.view
        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.update.rawValue) {
            let updateTab = tabView.tabViewItem(at: Int(BPContentTab.update.rawValue))
            updateTab.view = updateView
        }

        let doctorVC = BPDoctorViewController(nibName: nil, bundle: nil)
        self.doctorViewController = doctorVC
        let doctorView = doctorVC.view
        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.doctor.rawValue) {
            let doctorTab = tabView.tabViewItem(at: Int(BPContentTab.doctor.rawValue))
            doctorTab.view = doctorView
        }

        let servicesVC = BPServicesViewController(nibName: nil, bundle: nil)
        self.servicesViewController = servicesVC
        let servicesView = servicesVC.view
        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.services.rawValue) {
            let servicesTab = tabView.tabViewItem(at: Int(BPContentTab.services.rawValue))
            servicesTab.view = servicesView
        }

        if let selectedVC = selectedFormulaeViewController, let container = selectedFormulaView {
            let detailView = selectedVC.view
            container.addSubview(detailView)
            detailView.translatesAutoresizingMaskIntoConstraints = false
            container.addConstraints(NSLayoutConstraint.constraints(
                withVisualFormat: "V:|-0-[view]-0-|",
                options: [],
                metrics: nil,
                views: ["view": detailView]
            ))
            container.addConstraints(NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-0-[view]-0-|",
                options: [],
                metrics: nil,
                views: ["view": detailView]
            ))
        }

        sidebarController?.delegate = self
        sidebarController?.refreshSidebarBadges()
        sidebarController?.configureSidebarSettings()

        addToolbar()
        addLoadingView()

        let delegate = NSApplication.shared.delegate as? BPAppDelegate
        self.appDelegate = delegate
        delegate?.dockActionTarget = self
        delegate?.brewfileImportTarget = self
        delegate?.notificationNavigationTarget = self
        installCommandPaletteMenuItemIfAvailable()
        #if DEBUG
        installMockWarmNotificationMenu()
        installMockBrewfileMenu()
        #endif
    }

    #if DEBUG
    @objc open func installMockBrewfileMenu() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-BPMockBrew"),
              let index = arguments.firstIndex(of: "-BPMockBrewfileURL"),
              index + 1 < arguments.count else {
            return
        }
        let root = NSMenuItem(title: NSLocalizedString("Brewfile Test", comment: ""), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: root.title)
        let item = menu.addItem(
            withTitle: NSLocalizedString("Review Mock Brewfile", comment: ""),
            action: #selector(reviewMockBrewfile(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = arguments[index + 1]
        root.submenu = menu
        NSApp.mainMenu?.addItem(root)
    }

    @objc(reviewMockBrewfile:)
    open func reviewMockBrewfile(_ item: NSMenuItem) {
        guard let path = item.representedObject as? String else { return }
        importBrewfile(at: URL(fileURLWithPath: path))
    }

    @objc open func installMockWarmNotificationMenu() {
        let arguments = ProcessInfo.processInfo.arguments
        let targetIndex = arguments.firstIndex(of: "-BPMockWarmNotificationTarget")
        let hasWarmTarget = targetIndex != nil && (targetIndex! + 1) < arguments.count
        let holdsCatalog = arguments.contains("-BPMockHoldCatalogUntilReleased")
        guard arguments.contains("-BPMockBrew"), (hasWarmTarget || holdsCatalog) else { return }

        let root = NSMenuItem(title: NSLocalizedString("Notification Test", comment: ""), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: root.title)
        if hasWarmTarget, let targetIdx = targetIndex {
            let titles: [(String, Selector)] = [
                (NSLocalizedString("Search Mock Packages", comment: ""), #selector(beginMockNotificationSearch(_:))),
                (NSLocalizedString("Open Mock Notification", comment: ""), #selector(openMockNotification(_:))),
                (NSLocalizedString("Search Then Open Mock Notification", comment: ""), #selector(openMockNotificationDuringSearch(_:))),
                (NSLocalizedString("Search Then Clear Mock Search", comment: ""), #selector(clearMockSearchBeforeDebounce(_:)))
            ]
            for (title, action) in titles {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
                item.representedObject = arguments[targetIdx + 1]
            }
        }
        if holdsCatalog, let mockInterface = BPHomebrewInterface.sharedInterface() as? BPMockHomebrewInterface {
            let item = menu.addItem(
                withTitle: NSLocalizedString("Complete Mock Catalog", comment: ""),
                action: #selector(BPMockHomebrewInterface.releaseHeldCatalogs(_:)),
                keyEquivalent: ""
            )
            item.identifier = NSUserInterfaceItemIdentifier("mock.catalog.complete")
            item.target = mockInterface
        }
        root.submenu = menu
        NSApp.mainMenu?.addItem(root)
    }

    @objc(beginMockNotificationSearch:)
    open func beginMockNotificationSearch(_ sender: Any?) {
        toolbar?.searchField?.stringValue = Self.notificationSearchFixtureIdentifier
        performSearch(with: toolbar?.searchField?.stringValue ?? "")
    }

    @objc(openMockNotification:)
    open func openMockNotification(_ sender: NSMenuItem) {
        guard let target = sender.representedObject else { return }
        appDelegate?.navigate(forNotificationUserInfo: [BPBackgroundUpdater.outdatedNotificationTargetKey: target])
    }

    @objc(openMockNotificationDuringSearch:)
    open func openMockNotificationDuringSearch(_ sender: NSMenuItem) {
        beginMockNotificationSearch(sender)
        openMockNotification(sender)
    }

    @objc(clearMockSearchBeforeDebounce:)
    open func clearMockSearchBeforeDebounce(_ sender: Any?) {
        guard let field = toolbar?.searchField else { return }
        let change = Notification(name: NSControl.textDidChangeNotification, object: field)
        field.stringValue = Self.notificationSearchFixtureIdentifier
        field.delegate?.controlTextDidChange?(change)
        field.stringValue = ""
        field.delegate?.controlTextDidChange?(change)
    }
    #endif

    @objc open func addToolbar() {
        let tb = BPToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        tb.delegate = tb
        tb.controller = self
        self.toolbar = tb
        view.window?.toolbar = tb
        tb.displayMode = .iconOnly
        tb.lockItems()
    }

    @objc open func addDisabledView() {
        guard disabledView == nil else { return }
        let dv = BPDisabledView(frame: .zero)
        let manager = _homebrewManager
        dv.retryHandler = { [weak manager] in
            manager?.retryHomebrewDiscovery()
        }
        dv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dv)

        let referenceView = mainWindowController?.windowContentView ?? view
        NSLayoutConstraint.activate([
            NSLayoutConstraint(item: referenceView, attribute: .leading, relatedBy: .equal, toItem: dv, attribute: .leading, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .trailing, relatedBy: .equal, toItem: dv, attribute: .trailing, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .top, relatedBy: .equal, toItem: dv, attribute: .top, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .bottom, relatedBy: .equal, toItem: dv, attribute: .bottom, multiplier: 1, constant: 0)
        ])
        self.disabledView = dv
    }

    @objc open func addLoadingView() {
        let lv = BPLoadingView(frame: .zero)
        lv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lv)

        let referenceView = mainWindowController?.windowContentView ?? view
        NSLayoutConstraint.activate([
            NSLayoutConstraint(item: referenceView, attribute: .leading, relatedBy: .equal, toItem: lv, attribute: .leading, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .trailing, relatedBy: .equal, toItem: lv, attribute: .trailing, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .top, relatedBy: .equal, toItem: lv, attribute: .top, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .bottom, relatedBy: .equal, toItem: lv, attribute: .bottom, multiplier: 1, constant: 0)
        ])
        self.loadingView = lv
    }

    @objc open func applyDefaultDividerPositionIfNeeded() {
        guard !hasAppliedDefaultDividerPosition else { return }
        guard let splitView = formulaeSplitView else { return }
        let height = splitView.bounds.size.height
        guard height > 0 else { return }

        hasAppliedDefaultDividerPosition = true

        if let autosaveName = splitView.autosaveName, !autosaveName.isEmpty,
           UserDefaults.standard.object(forKey: "NSSplitView Subview Frames \(autosaveName)") != nil {
            return
        }

        splitView.setPosition(height - Self.kDefaultDetailPaneHeight, ofDividerAt: 0)
    }

    open override func viewDidLayout() {
        super.viewDidLayout()
        applyDefaultDividerPositionIfNeeded()
    }

    @objc(usesInstalledPackageListHostForMode:)
    open func usesInstalledPackageListHost(forMode mode: BPListMode) -> Bool {
        switch mode {
        case .all, .installed, .leaves, .pinned, .outdated, .search, .repositories, .installedCasks, .outdatedCasks, .allCasks:
            return true
        @unknown default:
            return false
        }
    }

    @objc open var isUsingUnifiedUpdatesHost: Bool {
        !searching && sidebarController?.sidebar?.selectedRow == Int(FormulaeSideBarItem.unifiedUpdates.rawValue)
    }

    @objc open var isUsingInstalledPackageListHost: Bool {
        guard !isUsingUnifiedUpdatesHost else { return false }
        let mode = BPListMode(rawValue: formulaeDataSource?.mode ?? 0) ?? .all
        return usesInstalledPackageListHost(forMode: mode)
    }

    @objc open func setUpUnifiedUpdatesHost() {
        let host = BPUnifiedUpdatesHost()
        host.onSelectionChanged = { [weak self] in
            guard let self, self.isUsingUnifiedUpdatesHost else { return }
            self.updateInterfaceItems()
        }
        host.onUpgradeSelected = { [weak self] _, _ in
            self?.upgradeSelectedFormulae(nil)
        }
        host.onUpgradeAll = { [weak self] in
            self?.upgradeAllOutdatedFormulae(nil)
        }
        self.unifiedUpdatesHost = host
    }

    @objc open func setUpStatusBarHost() {
        let host = BPStatusBarHost()
        host.onOpenCommandPalette = { [weak self] in
            self?.showCommandPalette(nil)
        }
        host.onOpenUnifiedUpdates = { [weak self] in
            self?.showUnifiedUpdates(nil)
        }
        self.statusBarHost = host

        if let footerContainer = label_information?.superview {
            label_information?.alphaValue = 0.0
            backgroundActivityIndicator?.alphaValue = 0.0
            let barView = host.viewController.view
            barView.translatesAutoresizingMaskIntoConstraints = false
            footerContainer.addSubview(barView)
            NSLayoutConstraint.activate([
                barView.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
                barView.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
                barView.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),
                barView.heightAnchor.constraint(equalToConstant: 26.0)
            ])
        }
        syncStatusBarHost()
    }

    @objc open func syncStatusBarHost() {
        guard let statusBarHost else { return }
        let message = label_information?.stringValue ?? ""
        let installedCount = (_homebrewManager.installedFormulae?.count ?? 0) + (_homebrewManager.installedCasks?.count ?? 0)
        let outdatedCount = (_homebrewManager.outdatedFormulae?.count ?? 0) + (_homebrewManager.outdatedCasks?.count ?? 0)
        let pinnedCount = _homebrewManager.pinnedFormulae?.count ?? 0
        statusBarHost.update(
            message: message,
            isBusy: statusBarHost.isBusy,
            installedCount: installedCount,
            outdatedCount: outdatedCount,
            pinnedCount: pinnedCount
        )
    }

    @objc open func syncUnifiedUpdatesHostRows() {
        guard let unifiedUpdatesHost else { return }
        let formulae = _homebrewManager.outdatedFormulae ?? []
        var formulaNames: [String] = []
        var formulaVersions: [String] = []
        var formulaLatestVersions: [String] = []
        var formulaPinnedFlags: [NSNumber] = []
        formulaNames.reserveCapacity(formulae.count)
        formulaVersions.reserveCapacity(formulae.count)
        formulaLatestVersions.reserveCapacity(formulae.count)
        formulaPinnedFlags.reserveCapacity(formulae.count)

        for formula in formulae {
            formulaNames.append(formula.name ?? "")
            formulaVersions.append(formula.version ?? "")
            formulaLatestVersions.append(formula.shortLatestVersion ?? "")
            formulaPinnedFlags.append(NSNumber(value: _homebrewManager.isFormulaPinned(formula)))
        }

        let casks = _homebrewManager.outdatedCasks ?? []
        var caskNames: [String] = []
        var caskVersions: [String] = []
        var caskLatestVersions: [String] = []
        var caskPinnedFlags: [NSNumber] = []
        caskNames.reserveCapacity(casks.count)
        caskVersions.reserveCapacity(casks.count)
        caskLatestVersions.reserveCapacity(casks.count)
        caskPinnedFlags.reserveCapacity(casks.count)

        for cask in casks {
            caskNames.append(cask.name ?? "")
            caskVersions.append(cask.version ?? "")
            caskLatestVersions.append(cask.shortLatestVersion ?? "")
            caskPinnedFlags.append(NSNumber(value: _homebrewManager.isFormulaPinned(cask)))
        }

        unifiedUpdatesHost.update(
            formulaNames: formulaNames,
            formulaVersions: formulaVersions,
            formulaLatestVersions: formulaLatestVersions,
            formulaPinnedFlags: formulaPinnedFlags,
            caskNames: caskNames,
            caskVersions: caskVersions,
            caskLatestVersions: caskLatestVersions,
            caskPinnedFlags: caskPinnedFlags
        )
    }

    @objc open func setUpInstalledPackageListHost() {
        let host = BPInstalledPackageListHost()
        host.contextMenu = formulaeTableView?.menu

        host.onSelectionChanged = { [weak self] _, _ in
            guard let self, self.isUsingInstalledPackageListHost else { return }
            self.updateInterfaceItems()
        }
        host.onSortChanged = { [weak self] key, ascending in
            guard let self else { return }
            BPPreferences.sortColumnIdentifier = key
            BPPreferences.sortAscending = ascending
            if let key, !key.isEmpty {
                let descriptor = NSSortDescriptor(key: key, ascending: ascending)
                self.formulaeTableView?.sortDescriptors = [descriptor]
                self.formulaeDataSource?.sortDescriptors = [descriptor]
            } else {
                self.formulaeTableView?.sortDescriptors = []
                self.formulaeDataSource?.sortDescriptors = []
            }
        }
        host.onTableAction = { [weak self] request in
            guard let self, let req = BPFormulaeTableRequest(rawValue: request) else { return }
            self.handleInstalledPackageListAction(req)
        }
        host.onSpacePressed = { [weak self] in
            self?.showFormulaInfo(nil)
        }
        self.installedPackageListHost = host
    }

    @objc(sourceFormulaeForMode:)
    open func sourceFormulae(forMode mode: BPListMode) -> [BPFormula] {
        switch mode {
        case .all: return _homebrewManager.allFormulae ?? []
        case .installed: return _homebrewManager.installedFormulae ?? []
        case .leaves: return _homebrewManager.leavesFormulae ?? []
        case .pinned: return _homebrewManager.pinnedFormulae ?? []
        case .outdated: return _homebrewManager.outdatedFormulae ?? []
        case .search: return _homebrewManager.searchFormulae ?? []
        case .repositories: return _homebrewManager.repositoriesFormulae ?? []
        case .installedCasks: return _homebrewManager.installedCasks ?? []
        case .outdatedCasks: return _homebrewManager.outdatedCasks ?? []
        case .allCasks: return _homebrewManager.allCasks ?? []
        @unknown default: return []
        }
    }

    @objc open func syncInstalledPackageListHostRows() {
        guard let installedPackageListHost else { return }
        let descriptor = formulaeDataSource?.sortDescriptors?.first
        installedPackageListHost.applySort(
            columnIdentifier: descriptor?.key,
            ascending: descriptor?.ascending ?? true
        )

        let rawMode = formulaeDataSource?.mode ?? BPListMode.all.rawValue
        let mode = BPListMode(rawValue: rawMode) ?? .all
        let source = sourceFormulae(forMode: mode)
        let count = source.count
        var names: [String] = []
        var versions: [String] = []
        var latestVersions: [String] = []
        var statusRanks: [NSNumber] = []
        var pinnedFlags: [NSNumber] = []
        var caskFlags: [NSNumber] = []
        names.reserveCapacity(count)
        versions.reserveCapacity(count)
        latestVersions.reserveCapacity(count)
        statusRanks.reserveCapacity(count)
        pinnedFlags.reserveCapacity(count)
        caskFlags.reserveCapacity(count)

        for formula in source {
            names.append(formula.name ?? "")
            versions.append(formula.version ?? "")
            latestVersions.append(formula.shortLatestVersion ?? "")
            statusRanks.append(NSNumber(value: _homebrewManager.status(forFormula: formula).rawValue))
            pinnedFlags.append(NSNumber(value: _homebrewManager.isFormulaPinned(formula)))
            caskFlags.append(NSNumber(value: formula.cask))
        }

        installedPackageListHost.updateRowsForObjCMode(
            names: names,
            versions: versions,
            latestVersions: latestVersions,
            statusRanks: statusRanks,
            pinnedFlags: pinnedFlags,
            caskFlags: caskFlags,
            objcListMode: rawMode
        )
    }

    @objc(embedHostView:inContainer:)
    open func embedHostView(_ hostView: NSView?, inContainer container: NSView?) {
        guard let container, let hostView else { return }
        if hostView.superview !== container {
            hostView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostView)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostView.topAnchor.constraint(equalTo: container.topAnchor),
                hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        hostView.isHidden = false
    }

    @objc open func updateActiveListSurfaceVisibility() {
        let container = scrollView_formulae?.superview
        let installedView = installedPackageListHost?.viewController.view
        let unifiedView = unifiedUpdatesHost?.viewController.view
        if isUsingUnifiedUpdatesHost {
            scrollView_formulae?.isHidden = true
            if installedView?.superview != nil { installedView?.removeFromSuperview() }
            embedHostView(unifiedView, inContainer: container)
        } else if isUsingInstalledPackageListHost {
            scrollView_formulae?.isHidden = true
            if unifiedView?.superview != nil { unifiedView?.removeFromSuperview() }
            embedHostView(installedView, inContainer: container)
        } else {
            if installedView?.superview != nil { installedView?.removeFromSuperview() }
            if unifiedView?.superview != nil { unifiedView?.removeFromSuperview() }
            scrollView_formulae?.isHidden = false
        }
    }

    @objc(handleInstalledPackageListAction:)
    open func handleInstalledPackageListAction(_ request: BPFormulaeTableRequest) {
        guard let hostView = installedPackageListHost?.viewController.view else { return }
        guard isUsingInstalledPackageListHost,
              hostView.window != nil,
              !hostView.isHiddenOrHasHiddenAncestor,
              loadingView == nil,
              disabledView == nil,
              homebrewInstalled,
              appDelegate?.window?.attachedSheet == nil,
              let selectedTab = tabView?.selectedTabViewItem,
              tabView?.indexOfTabViewItem(selectedTab) == Int(BPContentTab.formulae.rawValue),
              appDelegate?.runningBackgroundTask != true else {
            return
        }
        guard let formulae = selectedFormulae(), !formulae.isEmpty else { return }
        var statuses: [NSNumber] = []
        statuses.reserveCapacity(formulae.count)
        for formula in formulae {
            statuses.append(NSNumber(value: _homebrewManager.status(forFormula: formula).rawValue))
        }
        let action = BPFormulaeTableActions.action(
            forRequest: request.rawValue,
            mode: formulaeDataSource?.mode ?? 0,
            formulae: formulae,
            statuses: statuses
        )
        switch action {
        case .install: installFormula(hostView)
        case .upgrade: upgradeSelectedFormulae(hostView)
        case .info: showFormulaInfo(hostView)
        case .uninstall: uninstallFormula(hostView)
        case .none: break
        @unknown default: break
        }
    }

    @objc open func updateInterfaceItems() {
        let selectedSidebarRow = sidebarController?.sidebar?.selectedRow ?? -1
        let selected = selectedFormulae() ?? []
        let selectedCount: UInt
        if isUsingUnifiedUpdatesHost {
            selectedCount = UInt(max(0, unifiedUpdatesHost?.selectedCount ?? 0))
        } else if isUsingInstalledPackageListHost {
            selectedCount = UInt(max(0, installedPackageListHost?.selectedCount ?? 0))
        } else {
            let selectedIndex = formulaeTableView?.selectedRow ?? -1
            selectedCount = selectedIndex >= 0 ? UInt(formulaeTableView?.selectedRowIndexes.count ?? 0) : 0
        }
        if selected.isEmpty {
            currentFormula = nil
        }

        let selectedStatus: BPFormulaStatus = selectedCount == 1
            ? BPHomebrewManager.sharedManager().status(forFormula: selectedFormula())
            : .notInstalled
        let toolbarMode = BPFormulaeTableActions.toolbarMode(
            forSidebarRow: selectedSidebarRow,
            selectedCount: selectedCount,
            selectedFormulaStatus: selectedStatus.rawValue
        )
        toolbar?.configure(for: toolbarMode)

        if searching
            || formulaeDataSource?.mode == BPListMode.search.rawValue
            || BPFormulaeTableActions.shouldShowFormulaInfo(forSidebarRow: selectedSidebarRow) {
            selectedFormulaView?.isHidden = false
            selectedFormulaeViewController?.formulae = selected
        } else {
            selectedFormulaView?.isHidden = true
        }
    }

    @objc open func configureForUnifiedUpdates() {
        formulaeTableView?.deselectAll(nil)
        installedPackageListHost?.deselectAll()
        unifiedUpdatesHost?.clearSelection()
        updateActiveListSurfaceVisibility()
        syncUnifiedUpdatesHostRows()
        updateInterfaceItems()
        refreshEmptyState()
    }

    @objc(configureTableForListing:)
    open func configureTable(forListing mode: BPListMode) {
        formulaeTableView?.deselectAll(nil)
        installedPackageListHost?.deselectAll()
        unifiedUpdatesHost?.clearSelection()
        formulaeDataSource?.mode = mode.rawValue
        formulaeTableView?.mode = mode
        updateActiveListSurfaceVisibility()
        if isUsingInstalledPackageListHost {
            syncInstalledPackageListHostRows()
        }
        formulaeTableView?.reloadData()
        updateInterfaceItems()
        refreshEmptyState()
    }

    @objc open func refreshEmptyState() {
        let container = scrollView_formulae?.superview ?? scrollView_formulae
        if isUsingUnifiedUpdatesHost {
            BPEmptyStateView.presentState(nil, over: container)
            return
        }
        let rows: Int
        if isUsingInstalledPackageListHost {
            rows = installedPackageListHost?.rowCount ?? 0
        } else if let tableView = formulaeTableView, let dataSource = formulaeDataSource {
            rows = dataSource.numberOfRows(in: tableView)
        } else {
            rows = 0
        }
        let loading = (loadingView != nil)

        var state: BPEmptyState?
        if BPEmptyState.shouldShow(forRowCount: rows, loading: loading) {
            state = BPEmptyState.state(
                forSidebarRow: sidebarController?.sidebar?.selectedRow ?? -1,
                searching: searching
            )
        }
        BPEmptyStateView.presentState(state, over: container)
    }

    // MARK: - Footer Information Label

    @objc open func updateInfoLabelWithSidebarSelection() {
        let selectedSidebarRow = sidebarController?.sidebar?.selectedRow ?? -1
        let key = BPFormulaeTableActions.footerLocalizationKey(
            forSidebarRow: selectedSidebarRow,
            searching: searching
        )
        let message = key.map { NSLocalizedString($0, comment: "") }
        updateInfoLabel(withText: message)
    }

    @objc(updateInfoLabelWithText:)
    open func updateInfoLabel(withText message: String?) {
        let resolved = message ?? ""
        label_information?.stringValue = resolved
        let window = view.window ?? appDelegate?.window
        window?.subtitle = resolved
        syncStatusBarHost()
    }

    // MARK: - Homebrew Manager Delegate

    @objc(homebrewManager:didBeginStepForMode:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, didBeginStepForMode mode: BPListMode) {
        MainActor.assumeIsolated {
            self.toolbar?.showsCancelReload = true
            guard !self.searching else { return }
            self.updateInfoLabel(withText: BPLoadingStatus.status(forListMode: mode.rawValue))
        }
    }

    @objc(homebrewManagerFinishedStepping:)
    nonisolated open func homebrewManagerFinishedStepping(_ manager: BPHomebrewManager) {
        MainActor.assumeIsolated {
            self.toolbar?.showsCancelReload = false
            guard !self.searching else { return }
            self.updateInfoLabelWithSidebarSelection()
        }
    }

    @IBAction @objc(cancelReload:)
    open func cancelReload(_ sender: Any?) {
        BPHomebrewManager.sharedManager().cancelReload()
    }

    @objc(homebrewManager:didPublishListForMode:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, didPublishListForMode mode: BPListMode) {
        MainActor.assumeIsolated {
            guard self.homebrewInstalled && !self.searching else { return }

            self.sidebarController?.refreshBadge(forListMode: mode.rawValue)
            self.syncStatusBarHost()

            if mode == .outdated {
                self.enableUpgradeFormulasMenu = !(manager.outdatedFormulae ?? []).isEmpty
            }

            if mode == .installed && self.loadingView != nil {
                self.revealContentForFirstPublishedList()
            }

            let isLoading = (self.loadingView != nil)
            let activeMode = self.formulaeDataSource?.mode ?? BPListMode.all.rawValue
            if BPFormulaeTableActions.shouldSyncUnifiedUpdates(
                forPublishedMode: mode.rawValue,
                isLoading: isLoading,
                isUsingUnifiedUpdatesHost: self.isUsingUnifiedUpdatesHost
            ) {
                self.syncUnifiedUpdatesHostRows()
                self.refreshEmptyState()
            } else if BPFormulaeTableActions.shouldRefreshVisibleList(
                forPublishedMode: mode.rawValue,
                activeMode: activeMode,
                isLoading: isLoading
            ) {
                self.formulaeDataSource?.refreshBackingArray()
                if self.isUsingInstalledPackageListHost {
                    self.syncInstalledPackageListHostRows()
                }
                self.formulaeTableView?.reloadData()
                self.refreshEmptyState()
            } else if BPFormulaeTableActions.shouldSyncInstalledHostMetadata(
                forPublishedMode: mode.rawValue,
                activeMode: activeMode,
                isLoading: isLoading,
                isUsingInstalledHost: self.isUsingInstalledPackageListHost
            ) || (!isLoading && self.isUsingInstalledPackageListHost && (mode == .installed || mode == .installedCasks)) {
                self.syncInstalledPackageListHostRows()
            }
        }
    }

    @objc open func revealContentForFirstPublishedList() {
        loadingView?.removeFromSuperview()
        loadingView = nil

        mainWindowController?.setContentViewHidden(false)
        label_information?.isHidden = false

        toolbar?.configure(for: .default)
        toolbar?.unlockItems()

        formulaeDataSource?.refreshBackingArray()
        updateActiveListSurfaceVisibility()
        if isUsingUnifiedUpdatesHost {
            syncUnifiedUpdatesHostRows()
        } else if isUsingInstalledPackageListHost {
            syncInstalledPackageListHostRows()
        }
        formulaeTableView?.reloadData()
        refreshEmptyState()
    }

    @objc(homebrewManagerFinishedUpdating:)
    nonisolated open func homebrewManagerFinishedUpdating(_ manager: BPHomebrewManager) {
        MainActor.assumeIsolated {
            self.loadingView?.removeFromSuperview()
            self.loadingView = nil

            guard self.homebrewInstalled else { return }

            self.formulaeTableView?.menu?.cancelTracking()

            let previouslySelectedFormula = self.currentFormula

            self.mainWindowController?.setContentViewHidden(false)
            self.label_information?.isHidden = false

            self.toolbar?.configure(for: .default)
            self.toolbar?.unlockItems()
            self.formulaeDataSource?.refreshBackingArray()

            let shouldReselectFirstRow = (self.sidebarController?.sidebar?.selectedRow ?? -1) < 0

            self.sidebarController?.refreshSidebarBadges()
            self.sidebarController?.sidebar?.reloadData()

            self.enableUpgradeFormulasMenu = !(BPHomebrewManager.sharedManager().outdatedFormulae ?? []).isEmpty

            if shouldReselectFirstRow {
                self.sidebarController?.sidebar?.selectRowIndexes(
                    IndexSet(integer: Int(FormulaeSideBarItem.installed.rawValue)),
                    byExtendingSelection: false
                )
            } else {
                self.sidebarController?.sidebar?.selectRowIndexes(
                    IndexSet(integer: max(0, self.lastSelectedSidebarIndex)),
                    byExtendingSelection: false
                )
            }

            self.restoreSelectedFormula(previouslySelectedFormula)
            self.refreshEmptyState()
        }
    }

    @objc(restoreSelectedFormula:)
    open func restoreSelectedFormula(_ formula: BPFormula?) {
        if isUsingUnifiedUpdatesHost {
            syncUnifiedUpdatesHostRows()
            return
        }
        if isUsingInstalledPackageListHost {
            syncInstalledPackageListHostRows()
            if let formula,
               installedPackageListHost?.selectPackage(named: formula.name ?? "", cask: formula.cask) == true {
                return
            }
            currentFormula = nil
            selectedFormulaeViewController?.formulae = nil
            return
        }

        let row = formula.map { formulaeDataSource?.indexOfFormula(named: $0.name ?? "", cask: $0.cask) ?? -1 } ?? -1
        if row < 0 {
            currentFormula = nil
            selectedFormulaeViewController?.formulae = nil
            return
        }
        formulaeTableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        formulaeTableView?.scrollRowToVisible(row)
    }

    @objc(homebrewManager:didUpdateSearchResults:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, didUpdateSearchResults searchResults: [Any]?) {
        MainActor.assumeIsolated {
            self.loadSearchResults()
        }
    }

    @objc(homebrewManager:shouldDisplayNoBrewMessage:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, shouldDisplayNoBrewMessage yesOrNo: Bool) {
        MainActor.assumeIsolated {
            self.homebrewInstalled = !yesOrNo
            if yesOrNo {
                self.loadingView?.removeFromSuperview()
                self.loadingView = nil
                self.addDisabledView()
                self.disabledView?.showDiscoveryResult(manager.discoveryResult.rawValue, checking: manager.checkingHomebrew)
                self.label_information?.isHidden = true
                self.mainWindowController?.setContentViewHidden(true)
                self.toolbar?.lockItems()
            } else {
                self.disabledView?.removeFromSuperview()
                self.disabledView = nil
                if self.loadingView == nil {
                    self.addLoadingView()
                }
                self.toolbar?.lockItems()
            }
        }
    }

    @objc(homebrewManagerDidBeginDiscovery:)
    nonisolated open func homebrewManagerDidBeginDiscovery(_ manager: BPHomebrewManager) {
        MainActor.assumeIsolated {
            self.disabledView?.showDiscoveryResult(manager.discoveryResult.rawValue, checking: true)
        }
    }

    @objc(showFormulaInfoForCurrentlySelectedFormulaUsingInfoType:)
    open func showFormulaInfoForCurrentlySelectedFormula(usingInfoType type: BPFormulaInfoType) {
        let popover = formulaPopoverViewController.formulaPopover
        if popover?.isShown == true {
            popover?.close()
        }
        guard let formula = selectedFormula() else { return }

        formulaPopoverViewController.infoType = type
        formulaPopoverViewController.formula = formula

        if isUsingUnifiedUpdatesHost {
            if let anchorView = unifiedUpdatesHost?.viewController.view {
                popover?.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
            }
            return
        }

        if isUsingInstalledPackageListHost {
            if let host = installedPackageListHost {
                let anchorView = host.viewController.view
                let anchorRect = host.rectOfSelectedRow(in: anchorView)
                popover?.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .maxX)
            }
            return
        }

        guard let tableView = formulaeTableView, let scrollView = scrollView_formulae else { return }
        let selectedIndex = tableView.selectedRow
        var anchorRect = tableView.rect(ofRow: selectedIndex)
        anchorRect.origin = scrollView.convert(anchorRect.origin, from: tableView)
        popover?.show(relativeTo: anchorRect, of: scrollView, preferredEdge: .maxX)
    }

    // MARK: - Search Mode

    @objc open func loadSearchResults() {
        searchCoordinator.didReceiveResults(forSidebarRow: sidebarController?.sidebar?.selectedRow ?? 0)
        configureTable(forListing: .search)
    }

    @objc open func endSearchAndCleanup() {
        toolbar?.searchField?.stringValue = ""
        let originalRow = searchCoordinator.endSearchReturningSidebarRow()
        let row = BPSideBarController.restorableRow(
            from: originalRow,
            rowCount: sidebarController?.sidebar?.numberOfRows ?? 0
        )
        sidebarController?.sidebar?.selectRowIndexes(IndexSet(integer: Int(row.rawValue)), byExtendingSelection: false)
        updateInfoLabelWithSidebarSelection()
    }

    // MARK: - NSTableView Delegate

    @objc(formulaeTableView:requestAction:)
    nonisolated open func formulaeTableView(_ table: BPFormulaeTableView, requestAction request: BPFormulaeTableRequest) {
        let requestRaw = request.rawValue
        MainActor.assumeIsolated {
            guard table === self.formulaeTableView,
                  table.window != nil,
                  table.isEnabled,
                  !table.isHiddenOrHasHiddenAncestor,
                  self.loadingView == nil,
                  self.disabledView == nil,
                  self.homebrewInstalled,
                  self.appDelegate?.window?.attachedSheet == nil,
                  let selectedTab = self.tabView?.selectedTabViewItem,
                  self.tabView?.indexOfTabViewItem(selectedTab) == Int(BPContentTab.formulae.rawValue),
                  table.mode.rawValue == self.formulaeDataSource?.mode,
                  self.appDelegate?.runningBackgroundTask != true else {
                return
            }
            let rows = table.selectedRowIndexes
            guard !rows.isEmpty,
                  let lastRow = rows.last,
                  lastRow < table.numberOfRows,
                  let formulae = self.formulaeDataSource?.formulas(at: rows) as? [BPFormula],
                  formulae.count == rows.count else {
                return
            }
            var statuses: [NSNumber] = []
            statuses.reserveCapacity(formulae.count)
            for formula in formulae {
                statuses.append(NSNumber(value: self._homebrewManager.status(forFormula: formula).rawValue))
            }
            let action = BPFormulaeTableActions.action(
                forRequest: requestRaw,
                mode: table.mode.rawValue,
                formulae: formulae,
                statuses: statuses
            )
            switch action {
            case .install: self.installFormula(table)
            case .upgrade: self.upgradeSelectedFormulae(table)
            case .info: self.showFormulaInfo(table)
            case .uninstall: self.uninstallFormula(table)
            case .none: break
            @unknown default: break
            }
        }
    }

    open func tableViewSelectionDidChange(_ notification: Notification) {
        updateInterfaceItems()
    }

    // MARK: - BPSelectedFormulaViewController Delegate

    @objc(selectedFormulaViewDidUpdateFormulaInfoForFormula:)
    nonisolated open func selectedFormulaViewDidUpdateFormulaInfo(forFormula formula: Any?) {
        nonisolated(unsafe) let rawFormula = formula
        MainActor.assumeIsolated {
            if let f = rawFormula as? BPFormula {
                self.currentFormula = f
            }
        }
    }

    @objc(selectedFormulaViewDidRequestSelectRelatedFormulaNamed:)
    nonisolated open func selectedFormulaViewDidRequestSelectRelatedFormulaNamed(_ formulaName: String) {
        MainActor.assumeIsolated {
            guard !formulaName.isEmpty else { return }
            let isInstalled = (self._homebrewManager.installedFormulae ?? []).contains { $0.name == formulaName }
            let targetRow: FormulaeSideBarItem = isInstalled ? .installed : .all
            self.showOutdatedSidebarRow(targetRow)
            let formula = BPFormula.formula(withName: formulaName, version: nil, andLatestVersion: nil)
            formula.cask = false
            self.restoreSelectedFormula(formula)
        }
    }

    @objc nonisolated open func selectedFormulaViewDidRequestShowMoreInformation() {
        MainActor.assumeIsolated {
            self.showFormulaInfo(nil)
        }
    }

    @objc nonisolated open func selectedFormulaViewDidRequestOpenWebsite() {
        MainActor.assumeIsolated {
            self.openSelectedFormulaWebsite(nil)
        }
    }

    // MARK: - BPSideBarController Delegate

    @objc nonisolated open func sourceListSelectionDidChange() {
        MainActor.assumeIsolated {
            var tabIndex: BPContentTab = .formulae
            let selectedSidebarRow = self.sidebarController?.sidebar?.selectedRow ?? -1

            if self.searching {
                self.endSearchAndCleanup()
            }

            if selectedSidebarRow >= 0 {
                self.lastSelectedSidebarIndex = selectedSidebarRow
                BPPreferences.lastSelectedSidebarRow = selectedSidebarRow
            }

            self.formulaeTableView?.deselectAll(nil)
            self.installedPackageListHost?.deselectAll()
            self.unifiedUpdatesHost?.clearSelection()
            self.currentFormula = nil

            self.updateInterfaceItems()

            if selectedSidebarRow >= 0, let item = FormulaeSideBarItem(rawValue: UInt(selectedSidebarRow)) {
                switch item {
                case .installed:
                    self.configureTable(forListing: .installed)
                case .outdated:
                    self.configureTable(forListing: .outdated)
                case .all:
                    self.configureTable(forListing: .all)
                case .leaves:
                    self.configureTable(forListing: .leaves)
                case .pinned:
                    self.configureTable(forListing: .pinned)
                case .repositories:
                    self.configureTable(forListing: .repositories)
                case .installedCasks:
                    self.configureTable(forListing: .installedCasks)
                case .outdatedCasks:
                    self.configureTable(forListing: .outdatedCasks)
                case .allCasks:
                    self.configureTable(forListing: .allCasks)
                case .doctor:
                    tabIndex = .doctor
                case .update:
                    tabIndex = .update
                case .services:
                    tabIndex = .services
                    self.servicesViewController?.refreshServices()
                case .unifiedUpdates:
                    self.configureForUnifiedUpdates()
                case .formulaeCategory, .casksCategory, .toolsCategory:
                    break
                @unknown default:
                    break
                }
            }

            self.updateInfoLabelWithSidebarSelection()
            self.tabView?.selectTabViewItem(at: Int(tabIndex.rawValue))
            if tabIndex != .services {
                self.servicesViewController?.invalidateServiceDetails()
            }
        }
    }

    // MARK: - NSMenu Delegate

    open func menuNeedsUpdate(_ menu: NSMenu) {
        if isUsingInstalledPackageListHost {
            installedPackageListHost?.selectClickedRowIfNeeded()
            return
        }
        if let clickedRow = formulaeTableView?.clickedRow, clickedRow >= 0 {
            formulaeTableView?.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
    }

    // MARK: - IBActions

    @IBAction @objc(showFormulaInfo:)
    open func showFormulaInfo(_ sender: Any?) {
        showFormulaInfoForCurrentlySelectedFormula(usingInfoType: .general)
    }

    @IBAction @objc(showFormulaDependents:)
    open func showFormulaDependents(_ sender: Any?) {
        var onlyInstalledFormulae = true
        if let menuItem = sender as? NSMenuItem {
            onlyInstalledFormulae = !menuItem.isAlternate
        }
        let type: BPFormulaInfoType = onlyInstalledFormulae ? .installedDependents : .allDependents
        showFormulaInfoForCurrentlySelectedFormula(usingInfoType: type)
    }

    @IBAction @objc(installFormula:)
    open func installFormula(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula(),
              let alert = BPPackageOperationPresenter.installAlert(forFormula: formula),
              let window = appDelegate?.window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .install,
                formulae: [formula],
                options: nil
            )
        }
    }

    @IBAction @objc(installFormulaWithOptions:)
    open func installFormulaWithOptions(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula() else { return }
        if formula.cask {
            installFormula(sender)
            return
        }
        formulaOptionsWindowController = BPFormulaOptionsWindowController.runFormula(formula) { [weak self] options in
            guard let self else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .install,
                formulae: [formula],
                options: options as? [String]
            )
        }
    }

    @IBAction @objc(uninstallFormula:)
    open func uninstallFormula(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula(),
              let alert = BPPackageOperationPresenter.uninstallAlert(
                  forFormula: formula,
                  initialZapState: BPPreferences.zapCasksOnUninstall
              ),
              let window = appDelegate?.window else {
            return
        }
        let zapCheckbox = alert.accessoryView as? NSButton
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            let zap = (zapCheckbox?.state == .on)
            if zapCheckbox != nil {
                BPPreferences.zapCasksOnUninstall = zap
            }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .uninstall,
                formulae: [formula],
                options: nil,
                zap: zap
            )
        }
    }

    @IBAction @objc(pinSelectedFormula:)
    open func pinSelectedFormula(_ sender: Any?) {
        guard let formula = selectedFormula(), !formula.cask else { return }
        _ = BPHomebrewInterface.sharedInterface().pinFormula(formula.name, withReturnBlock: nil)
    }

    @IBAction @objc(unpinSelectedFormula:)
    open func unpinSelectedFormula(_ sender: Any?) {
        guard let formula = selectedFormula(), !formula.cask else { return }
        _ = BPHomebrewInterface.sharedInterface().unpinFormula(formula.name, withReturnBlock: nil)
    }

    @IBAction @objc(upgradeSelectedFormulae:)
    open func upgradeSelectedFormulae(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let selectedFormulae = selectedFormulae(),
              let alert = BPPackageOperationPresenter.upgradeAlert(forFormulae: selectedFormulae),
              let window = appDelegate?.window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .upgrade,
                formulae: selectedFormulae,
                options: nil
            )
        }
    }

    @IBAction @objc(upgradeAllOutdatedFormulae:)
    nonisolated open func upgradeAllOutdatedFormulae(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard !self.hasBlockingBackgroundTask() else { return }
            let snapshot = self._homebrewManager.updatesSnapshot
            guard let alert = BPPackageOperationPresenter.upgradeAllAlert(forSnapshot: snapshot),
                  let window = self.appDelegate?.window else {
                return
            }
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn, !self.hasBlockingBackgroundTask() else { return }
                guard let selection = self._homebrewManager.selection(forConfirmedUpdatesSnapshot: snapshot),
                      !selection.isEmpty else {
                    let changed = BPPackageOperationPresenter.updatesChangedAlert()
                    if let win = self.appDelegate?.window {
                        changed.beginSheetModal(for: win, completionHandler: nil)
                    }
                    return
                }
                self.operationWindowController = BPInstallationWindowController.run(
                    withOperation: .upgrade,
                    formulae: selection,
                    options: nil
                )
            }
        }
    }

    @IBAction @objc(tapRepository:)
    open func tapRepository(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        let alert = BPPackageOperationPresenter.tapInputAlert()
        let input = BPPackageOperationPresenter.tapInputHost(for: alert)?.inputField
        guard let window = appDelegate?.window else { return }

        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            let name = (input?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            guard BPHomebrewInterface.isValidTapName(name) else {
                let error = BPPackageOperationPresenter.invalidTapAlert()
                if let win = self.appDelegate?.window {
                    error.beginSheetModal(for: win, completionHandler: nil)
                }
                return
            }
            let lformula = BPFormula.formula(withName: name)
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .tap,
                formulae: [lformula],
                options: nil
            )
        }
    }

    @IBAction @objc(untapRepository:)
    open func untapRepository(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula(),
              let alert = BPPackageOperationPresenter.untapAlert(forFormula: formula),
              let window = appDelegate?.window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .untap,
                formulae: [formula],
                options: nil
            )
        }
    }

    @IBAction @objc(updateHomebrew:)
    nonisolated open func updateHomebrew(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.sidebarController?.sidebar?.selectRowIndexes(
                IndexSet(integer: Int(FormulaeSideBarItem.update.rawValue)),
                byExtendingSelection: false
            )
            self.updateViewController?.runStopUpdate(nil)
        }
    }

    @IBAction @objc(showOutdatedFormulae:)
    nonisolated open func showOutdatedFormulae(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.showOutdatedSidebarRow(.outdated)
        }
    }

    @IBAction @objc(showOutdatedCasks:)
    nonisolated open func showOutdatedCasks(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.showOutdatedSidebarRow(.outdatedCasks)
        }
    }

    @IBAction @objc(showUnifiedUpdates:)
    nonisolated open func showUnifiedUpdates(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.showOutdatedSidebarRow(.unifiedUpdates)
        }
    }

    @objc(showOutdatedSidebarRow:)
    open func showOutdatedSidebarRow(_ row: FormulaeSideBarItem) {
        toolbar?.searchField?.stringValue = ""
        searchCoordinator.cancelForNavigation()

        let alreadySelected = sidebarController?.sidebar?.selectedRow == Int(row.rawValue)
        sidebarController?.sidebar?.selectRowIndexes(
            IndexSet(integer: Int(row.rawValue)),
            byExtendingSelection: false
        )
        if alreadySelected {
            sourceListSelectionDidChange()
        }
    }

    @IBAction @objc(openSelectedFormulaWebsite:)
    open func openSelectedFormulaWebsite(_ sender: Any?) {
        guard let formula = selectedFormula(), let website = formula.website else { return }
        NSWorkspace.shared.open(website)
    }

    @objc(performSearchWithString:)
    open func performSearch(with searchPhrase: String?) {
        guard let searchPhrase, !searchPhrase.isEmpty else {
            endSearchAndCleanup()
            return
        }
        searchCoordinator.scheduleQuery(searchPhrase)
    }

    @IBAction @objc(beginFormulaSearch:)
    open func beginFormulaSearch(_ sender: Any?) {
        toolbar?.makeSearchFieldFirstResponder()
    }

    @objc open func installCommandPaletteMenuItemIfAvailable() {
        guard let items = NSApp.mainMenu?.items else { return }
        for topItem in items {
            guard let submenu = topItem.submenu else { continue }
            if submenu.indexOfItem(withTarget: self, andAction: #selector(updateHomebrew(_:))) >= 0 {
                BPAppDelegate.installCommandPaletteMenuItem(inToolsMenu: submenu, target: self)
                return
            }
        }
    }

    @objc(populateCommandPaletteHost:)
    open func populateCommandPaletteHost(_ host: BPCommandPaletteHost) {
        host.removeAllItems()

        let navigationEntries: [(String, String, String, String, FormulaeSideBarItem)] = [
            ("nav.installed", NSLocalizedString("Sidebar_Item_Installed", comment: ""), NSLocalizedString("Sidebar_Info_Installed", comment: ""), "checkmark.square", .installed),
            ("nav.outdated", NSLocalizedString("Sidebar_Item_Outdated", comment: ""), NSLocalizedString("Sidebar_Info_Outdated", comment: ""), "clock.arrow.circlepath", .outdated),
            ("nav.all", NSLocalizedString("Sidebar_Item_All", comment: ""), NSLocalizedString("Sidebar_Info_All", comment: ""), "books.vertical", .all),
            ("nav.leaves", NSLocalizedString("Sidebar_Item_Leaves", comment: ""), NSLocalizedString("Sidebar_Info_Leaves", comment: ""), "leaf", .leaves),
            ("nav.pinned", NSLocalizedString("Sidebar_Item_Pinned", comment: ""), NSLocalizedString("Sidebar_Info_Pinned", comment: ""), "pin", .pinned),
            ("nav.repos", NSLocalizedString("Sidebar_Item_Repos", comment: ""), NSLocalizedString("Sidebar_Info_Repos", comment: ""), "externaldrive", .repositories),
            ("nav.installedCasks", NSLocalizedString("Sidebar_Item_Installed", comment: ""), NSLocalizedString("Sidebar_Info_Casks", comment: ""), "macwindow.badge.plus", .installedCasks),
            ("nav.outdatedCasks", NSLocalizedString("Sidebar_Item_Outdated", comment: ""), NSLocalizedString("Sidebar_Info_OutdatedCasks", comment: ""), "arrow.down.app", .outdatedCasks),
            ("nav.allCasks", NSLocalizedString("Sidebar_Item_AllCasks", comment: ""), NSLocalizedString("Sidebar_Info_AllCasks", comment: ""), "square.grid.2x2", .allCasks),
            ("nav.doctor", NSLocalizedString("Sidebar_Item_Doctor", comment: ""), NSLocalizedString("Sidebar_Info_Doctor", comment: ""), "stethoscope", .doctor),
            ("nav.update", NSLocalizedString("Sidebar_Item_Update", comment: ""), NSLocalizedString("Sidebar_Info_Update", comment: ""), "arrow.triangle.2.circlepath", .update),
            ("nav.services", NSLocalizedString("Sidebar_Item_Services", comment: ""), NSLocalizedString("Sidebar_Info_Services", comment: ""), "gearshape.2", .services),
            ("nav.unifiedUpdates", NSLocalizedString("Sidebar_Item_Unified_Updates", comment: ""), NSLocalizedString("Sidebar_Info_Unified_Updates", comment: ""), "arrow.down.circle", .unifiedUpdates)
        ]

        for entry in navigationEntries {
            host.addNavigationItem(
                id: entry.0,
                title: entry.1,
                subtitle: entry.2,
                symbolName: entry.3,
                sidebarRow: Int(entry.4.rawValue)
            )
        }

        host.addActionItem(
            id: "action.updateHomebrew",
            title: NSLocalizedString("Toolbar_Homebrew_Update", comment: ""),
            subtitle: NSLocalizedString("Sidebar_Info_Update", comment: ""),
            symbolName: "arrow.triangle.2.circlepath",
            shortcutHint: "⌘U"
        )
        host.addActionItem(
            id: "action.upgradeAll",
            title: NSLocalizedString("Dock_Upgrade_All_Outdated", comment: ""),
            subtitle: NSLocalizedString("Sidebar_Info_Unified_Updates", comment: ""),
            symbolName: "arrow.down.circle.fill",
            shortcutHint: "⌥⌘U"
        )
        host.addActionItem(
            id: "action.cleanup",
            title: NSLocalizedString("Cleanup_Nothing_Title", comment: ""),
            subtitle: NSLocalizedString("Sidebar_VoiceOver_Tools", comment: ""),
            symbolName: "trash",
            shortcutHint: nil
        )
        host.addActionItem(
            id: "action.autoremove",
            title: NSLocalizedString("Remove Unused Dependencies", comment: ""),
            subtitle: NSLocalizedString("Sidebar_VoiceOver_Tools", comment: ""),
            symbolName: "scissors",
            shortcutHint: nil
        )
        host.addActionItem(
            id: "action.importBrewfile",
            title: NSLocalizedString("Import Brewfile", comment: ""),
            subtitle: NSLocalizedString("Review Brewfile", comment: ""),
            symbolName: "square.and.arrow.down",
            shortcutHint: nil
        )
        host.addActionItem(
            id: "action.exportBrewfile",
            title: NSLocalizedString("Panel_Export_Button", comment: ""),
            subtitle: NSLocalizedString("Panel_Export_Message", comment: ""),
            symbolName: "square.and.arrow.up",
            shortcutHint: nil
        )

        for formula in _homebrewManager.installedFormulae ?? [] {
            host.addPackageItem(
                name: formula.name ?? "",
                version: formula.version ?? "",
                cask: false
            )
        }
        for cask in _homebrewManager.installedCasks ?? [] {
            host.addPackageItem(
                name: cask.name ?? "",
                version: cask.version ?? "",
                cask: true
            )
        }
    }

    @IBAction @objc(showCommandPalette:)
    open func showCommandPalette(_ sender: Any?) {
        if commandPaletteHost == nil {
            let host = BPCommandPaletteHost()
            host.onNavigateToSidebarRow = { [weak self] row in
                guard let self, row >= 0, let item = FormulaeSideBarItem(rawValue: UInt(row)) else { return }
                self.showOutdatedSidebarRow(item)
            }
            host.onPerformAction = { [weak self] actionID in
                guard let self else { return }
                switch actionID {
                case "action.updateHomebrew":
                    self.updateHomebrew(nil)
                case "action.upgradeAll":
                    self.upgradeAllOutdatedFormulae(nil)
                case "action.cleanup":
                    self.runHomebrewCleanup(nil)
                case "action.autoremove":
                    self.removeUnusedDependencies(nil)
                case "action.importBrewfile":
                    self.runHomebrewImport(nil)
                case "action.exportBrewfile":
                    self.runHomebrewExport(nil)
                default:
                    break
                }
            }
            host.onSelectPackage = { [weak self] name, isCask in
                guard let self else { return }
                let targetRow: FormulaeSideBarItem = isCask ? .installedCasks : .installed
                self.showOutdatedSidebarRow(targetRow)
                let formula = BPFormula.formula(withName: name, version: nil, andLatestVersion: nil)
                formula.cask = isCask
                self.restoreSelectedFormula(formula)
            }
            host.onDismiss = { [weak self] in
                self?.dismissCommandPalette(nil)
            }
            self.commandPaletteHost = host
        }

        if let host = commandPaletteHost {
            populateCommandPaletteHost(host)
        }

        guard let parentWindow = view.window ?? appDelegate?.window,
              parentWindow.attachedSheet == nil else {
            return
        }

        if commandPaletteSheetWindow == nil, let host = commandPaletteHost {
            let sheet = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            sheet.title = NSLocalizedString("Command_Palette_Title", comment: "")
            sheet.contentViewController = host.viewController
            commandPaletteSheetWindow = sheet
        }

        if let sheet = commandPaletteSheetWindow {
            parentWindow.beginSheet(sheet, completionHandler: nil)
        }
    }

    @IBAction @objc(dismissCommandPalette:)
    open func dismissCommandPalette(_ sender: Any?) {
        let parentWindow = commandPaletteSheetWindow?.sheetParent ?? (view.window ?? appDelegate?.window)
        if let parentWindow, let sheet = commandPaletteSheetWindow {
            parentWindow.endSheet(sheet)
        }
    }

    @IBAction @objc(runHomebrewCleanup:)
    open func runHomebrewCleanup(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(), !cleanupPreviewInFlight else { return }
        cleanupPreviewInFlight = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let preview = BPHomebrewInterface.sharedInterface().previewCleanup()
            DispatchQueue.main.async {
                guard let self else { return }
                self.cleanupPreviewInFlight = false
                self.presentCleanupConfirmation(for: preview)
            }
        }
    }

    @IBAction @objc(removeUnusedDependencies:)
    open func removeUnusedDependencies(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(), appDelegate?.window?.attachedSheet == nil else { return }
        operationWindowController = BPAutoremoveWindowController.present(
            for: appDelegate?.window,
            interface: BPHomebrewInterface.sharedInterface(),
            manager: _homebrewManager
        )
    }

    @objc(presentCleanupConfirmationForPreview:)
    open func presentCleanupConfirmation(for preview: BPCleanupPreview) {
        guard !hasBlockingBackgroundTask(), let window = appDelegate?.window else { return }

        let alert = BPPackageOperationPresenter.cleanupAlert(for: preview)
        if preview.empty {
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
        }

        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .cleanup,
                formulae: nil,
                options: nil
            )
        }
    }

    @IBAction @objc(runHomebrewExport:)
    open func runHomebrewExport(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(), appDelegate?.window?.attachedSheet == nil else { return }
        appDelegate?.runningBackgroundTask = true

        let completion: (NSApplication.ModalResponse, URL?) -> Void = { [weak self] response, url in
            guard let self else { return }
            guard let destination = BPBrewfileExportOperation.exportURL(forSaveResponse: response.rawValue, url: url) else {
                self.appDelegate?.runningBackgroundTask = false
                return
            }
            DispatchQueue.main.async {
                self.operationWindowController = BPBundleWindowController.runExportOperation(withFile: destination)
            }
        }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-BPMockBrew"),
           let index = arguments.firstIndex(of: "-BPMockExportURL"),
           index + 1 < arguments.count {
            let response: NSApplication.ModalResponse = arguments.contains("-BPMockExportCancel") ? .cancel : .OK
            completion(response, URL(fileURLWithPath: arguments[index + 1]))
            return
        }
        #endif

        guard let window = appDelegate?.window else {
            appDelegate?.runningBackgroundTask = false
            return
        }
        let savePanel = NSSavePanel()
        savePanel.nameFieldLabel = NSLocalizedString("Panel_Export_Message", comment: "")
        savePanel.prompt = NSLocalizedString("Panel_Export_Button", comment: "")
        savePanel.nameFieldStringValue = BPBrewfile.defaultFilename()
        savePanel.beginSheetModal(for: window) { response in
            completion(response, savePanel.url)
        }
    }

    @objc(importBrewfileAtURL:)
    nonisolated open func importBrewfile(at url: URL) {
        MainActor.assumeIsolated {
            guard !self.hasBlockingBackgroundTask(),
                  self.appDelegate?.window?.attachedSheet == nil else {
                return
            }
            self.appDelegate?.runningBackgroundTask = true
            let manager = BPHomebrewManager.sharedManager()
            let inventories = BPPackageOperationPresenter.brewfileInventories(
                forInstalledFormulae: manager.installedFormulae,
                installedCasks: manager.installedCasks,
                repositories: manager.repositoriesFormulae
            )
            BPBundleWindowController.reviewFile(url, inventories: inventories, parentWindow: self.appDelegate?.window) { [weak self] plan in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let plan else {
                        self.appDelegate?.runningBackgroundTask = false
                        return
                    }
                    self.operationWindowController = BPBundleWindowController.runImportOperation(with: plan)
                }
            }
        }
    }

    @IBAction @objc(runHomebrewImport:)
    open func runHomebrewImport(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(),
              appDelegate?.window?.attachedSheet == nil,
              let window = appDelegate?.window else {
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.nameFieldLabel = NSLocalizedString("Panel_Import_Message", comment: "")
        openPanel.prompt = NSLocalizedString("Panel_Import_Button", comment: "")
        openPanel.nameFieldStringValue = BPBrewfile.defaultFilename()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.delegate = self

        openPanel.beginSheetModal(for: window) { [weak self] result in
            guard let self, let fileURL = openPanel.url, result.rawValue != 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.importBrewfile(at: fileURL)
            }
        }
    }

    @objc open func hasBlockingBackgroundTask() -> Bool {
        guard BPAppDelegate.shouldBlockOperation(whileRunningBackgroundTask: appDelegate?.runningBackgroundTask == true) else {
            return false
        }
        appDelegate?.displayBackgroundWarning()
        return true
    }

    @objc open func selectedFormula() -> BPFormula? {
        if isUsingUnifiedUpdatesHost {
            let selected = selectedFormulae()
            return selected?.count == 1 ? selected?.first : nil
        }
        if isUsingInstalledPackageListHost {
            guard let name = installedPackageListHost?.selectedPackageName, !name.isEmpty,
                  let ds = formulaeDataSource else {
                return nil
            }
            let index = ds.indexOfFormula(named: name, cask: installedPackageListHost?.selectedPackageCask == true)
            return ds.formula(at: index) as? BPFormula
        }
        guard let selectedIndex = formulaeTableView?.selectedRow else { return nil }
        return formulaeDataSource?.formula(at: selectedIndex) as? BPFormula
    }

    @objc open func selectedFormulae() -> [BPFormula]? {
        if isUsingUnifiedUpdatesHost {
            guard let host = unifiedUpdatesHost else { return nil }
            let resolved = BPPackageOperationPresenter.resolvedSelection(
                forFormulaNames: host.selectedFormulaNames,
                caskNames: host.selectedCaskNames,
                outdatedFormulae: _homebrewManager.outdatedFormulae,
                outdatedCasks: _homebrewManager.outdatedCasks
            ).compactMap { $0 as? BPFormula }
            return resolved.isEmpty ? nil : resolved
        }
        if isUsingInstalledPackageListHost {
            guard let host = installedPackageListHost else { return nil }
            let names = host.selectedPackageNames
            let casks = host.selectedPackageCasks
            guard !names.isEmpty, let ds = formulaeDataSource else { return nil }
            var selected: [BPFormula] = []
            selected.reserveCapacity(names.count)
            for (i, name) in names.enumerated() {
                let isCask = i < casks.count ? casks[i].boolValue : false
                let idx = ds.indexOfFormula(named: name, cask: isCask)
                if let formula = ds.formula(at: idx) as? BPFormula {
                    selected.append(formula)
                }
            }
            return selected.isEmpty ? nil : selected
        }
        guard let selectedIndexes = formulaeTableView?.selectedRowIndexes else { return nil }
        return formulaeDataSource?.formulas(at: selectedIndexes) as? [BPFormula]
    }

    @objc open func selectedFormulaNames() -> [String]? {
        selectedFormulae()?.compactMap(\.name)
    }

    // MARK: - Open Save Panels Delegate

    @objc(panel:shouldEnableURL:)
    nonisolated open func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        BPBrewfile.isBrewfileURL(url)
    }
}



