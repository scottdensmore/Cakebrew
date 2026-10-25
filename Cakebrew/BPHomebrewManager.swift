import CryptoKit
import Darwin
import Foundation

@objc(BPHomebrewManagerDelegate)
public protocol BPHomebrewManagerDelegate: NSObjectProtocol {
    @objc(homebrewManagerFinishedUpdating:)
    func homebrewManagerFinishedUpdating(_ manager: BPHomebrewManager)

    @objc(homebrewManagerDidBeginDiscovery:)
    optional func homebrewManagerDidBeginDiscovery(_ manager: BPHomebrewManager)

    @objc(homebrewManager:didPublishListForMode:)
    optional func homebrewManager(_ manager: BPHomebrewManager, didPublishListForMode mode: BPListMode)

    @objc(homebrewManager:didBeginStepForMode:)
    optional func homebrewManager(_ manager: BPHomebrewManager, didBeginStepForMode mode: BPListMode)

    @objc(homebrewManagerFinishedStepping:)
    optional func homebrewManagerFinishedStepping(_ manager: BPHomebrewManager)

    @objc(homebrewManager:didUpdateSearchResults:)
    func homebrewManager(_ manager: BPHomebrewManager, didUpdateSearchResults searchResults: [Any]?)

    @objc(homebrewManager:shouldDisplayNoBrewMessage:)
    func homebrewManager(_ manager: BPHomebrewManager, shouldDisplayNoBrewMessage yesOrNo: Bool)
}

public let kBPCacheLastUpdateKey = "BPCacheLastUpdateKey"
public let kBPCacheDataKey = "BPCacheDataKey"
public let kBPCacheCasksDataKey = "BPCacheCasksDataKey"
public let kBPCacheVersionKey = "BPCacheVersionKey"
public let kBPCacheStoredDateKey = "BPCacheStoredDateKey"

public let BPHomebrewManagerUpdatesSnapshotDidChangeNotification = "BPHomebrewManagerUpdatesSnapshotDidChangeNotification"
public let BPHomebrewManagerDidPublishOutdatedSnapshotNotification = "BPHomebrewManagerDidPublishOutdatedSnapshotNotification"
public let BPOutdatedSnapshotFormulaeCountKey = "formulae-count"
public let BPOutdatedSnapshotCaskCountKey = "cask-count"
public let BPOutdatedSnapshotGenerationKey = "generation"

@objc(BPHomebrewManager)
open class BPHomebrewManager: NSObject, BPHomebrewInterfaceDelegate, @unchecked Sendable {
    private static let kBPCacheVersion: Int = 2
    private static let kBPSecondsInADay: TimeInterval = 86400

    nonisolated(unsafe) private static var sharedInstance: BPHomebrewManager?

    // All stored properties have zero-byte defaults so class_createInstance(Cls, 0) works safely.
    private var _currentSearchQuery: NSString?
    @objc public var reloadInFlight: Bool = false
    private var _reloadRequestedWhileRunning: Bool = false
    @objc public var reloadGeneration: UInt = 0
    private var _pendingRebuildCache: Bool = false
    private var _updatesGeneration: UInt = 0
    private var _updatesInputs: NSMutableDictionary?
    private var _updatesSnapshot: BPUpdatesSnapshot?
    private var _outdatedSnapshotGeneration: UInt = 0
    private var _outdatedSnapshotFormulaeCount: NSNumber?
    private var _outdatedSnapshotCaskCount: NSNumber?
    private var _didPublishOutdatedSnapshot: Bool = false
    @objc public var discoveryInFlight: Bool = false
    private var _formulaRefreshRequested: Bool = false
    private var _formulaRefreshCompletions: NSMutableArray?
    private var _discoveryResultRaw: Int = 0

    private var _installedFormulaeStorage: NSArray?
    private var _outdatedFormulaeStorage: NSArray?
    private var _allFormulaeStorage: NSArray?
    private var _leavesFormulaeStorage: NSArray?
    private var _searchFormulaeStorage: NSArray?
    private var _repositoriesFormulaeStorage: NSArray?
    private var _pinnedFormulaeStorage: NSArray?
    private var _pinnedCasksStorage: NSArray?
    private var _installedCasksStorage: NSArray?
    private var _outdatedCasksStorage: NSArray?
    private var _allCasksStorage: NSArray?
    private var _servicesStorage: NSArray?

    private var _installedFormulaNamesSet: NSSet?
    private var _outdatedFormulaNamesSet: NSSet?
    private var _installedCaskNamesSet: NSSet?
    private var _outdatedCaskNamesSet: NSSet?
    private var _pinnedFormulaNamesSet: NSSet?

    @objc public weak var delegate: (any BPHomebrewManagerDelegate)?

    @objc dynamic public var allFormulae: [BPFormula]? {
        get { bpSynchronized(self) { _allFormulaeStorage as? [BPFormula] } }
        set { bpSynchronized(self) { _allFormulaeStorage = newValue as NSArray? } }
    }

    @objc dynamic public var leavesFormulae: [BPFormula]? {
        get { bpSynchronized(self) { _leavesFormulaeStorage as? [BPFormula] } }
        set { bpSynchronized(self) { _leavesFormulaeStorage = newValue as NSArray? } }
    }

    @objc dynamic public var searchFormulae: [BPFormula]? {
        get { bpSynchronized(self) { _searchFormulaeStorage as? [BPFormula] } }
        set { bpSynchronized(self) { _searchFormulaeStorage = newValue as NSArray? } }
    }

    @objc dynamic public var repositoriesFormulae: [BPFormula]? {
        get { bpSynchronized(self) { _repositoriesFormulaeStorage as? [BPFormula] } }
        set { bpSynchronized(self) { _repositoriesFormulaeStorage = newValue as NSArray? } }
    }

    @objc dynamic public var allCasks: [BPFormula]? {
        get { bpSynchronized(self) { _allCasksStorage as? [BPFormula] } }
        set { bpSynchronized(self) { _allCasksStorage = newValue as NSArray? } }
    }

    @objc dynamic public var services: [BPService]? {
        get { bpSynchronized(self) { _servicesStorage as? [BPService] } }
        set { bpSynchronized(self) { _servicesStorage = newValue as NSArray? } }
    }

    @objc public class func sharedManager() -> BPHomebrewManager {
        bpSynchronized(self) {
            if let existing = sharedInstance {
                return existing
            }
            let instance = BPHomebrewManager(uniqueInstance: ())
            sharedInstance = instance
            return instance
        }
    }

    @objc(initUniqueInstance)
    public required init(uniqueInstance: Void = ()) {
        super.init()
    }

    public override init() {
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc(shouldStartReloadWhenInFlight:)
    public class func shouldStartReload(whenInFlight inFlight: Bool) -> Bool {
        !inFlight
    }

    @objc(shouldPublishReloadGeneration:current:)
    public class func shouldPublishReloadGeneration(_ generation: UInt, current: UInt) -> Bool {
        generation == current
    }

    @objc public var currentReloadGeneration: UInt {
        bpSynchronized(self) {
            reloadGeneration
        }
    }

    @objc open var updatesSnapshot: BPUpdatesSnapshot? {
        bpSynchronized(self) {
            guard let snap = _updatesSnapshot, snap.generation == reloadGeneration else {
                return nil
            }
            return snap
        }
    }

    @objc(selectionForConfirmedUpdatesSnapshot:)
    open func selection(forConfirmedUpdatesSnapshot snapshot: BPUpdatesSnapshot?) -> [BPFormula]? {
        bpSynchronized(self) {
            guard let snapshot,
                  snapshot === self.updatesSnapshot,
                  snapshot.generation == reloadGeneration else {
                return nil
            }
            return snapshot.eligibleSelection() as? [BPFormula]
        }
    }

    private func notifyUpdatesSnapshotChanged() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.notifyUpdatesSnapshotChanged()
            }
            return
        }
        NotificationCenter.default.post(
            name: Notification.Name(BPHomebrewManagerUpdatesSnapshotDidChangeNotification),
            object: self
        )
    }

    private func publishUpdatesInput(_ input: [Any]?, key: String, generation: UInt) {
        if !Thread.isMainThread {
            nonisolated(unsafe) let inputBox = input as NSArray?
            DispatchQueue.main.async { [weak self] in
                self?.publishUpdatesInput(inputBox as? [Any], key: key, generation: generation)
            }
            return
        }
        bpSynchronized(self) {
            guard generation == reloadGeneration else { return }
            if _updatesInputs == nil || _updatesGeneration != generation {
                _updatesGeneration = generation
                _updatesInputs = NSMutableDictionary()
                _updatesSnapshot = nil
            }
            if let input {
                _updatesInputs?[key] = input as NSArray
            } else {
                _updatesInputs?.removeObject(forKey: key)
            }
            _updatesSnapshot = BPUpdatesSnapshot(
                generation: generation,
                formulaItems: _updatesInputs?["formulae"] as? [BPUpdateItem],
                caskItems: _updatesInputs?["casks"] as? [BPUpdateItem],
                pinnedFormulaNames: _updatesInputs?["formulaPins"] as? [String],
                pinnedCaskNames: _updatesInputs?["caskPins"] as? [String]
            )
        }
        notifyUpdatesSnapshotChanged()
    }

    @objc(publishPinnedCasks:generation:)
    open func publishPinnedCasks(_ casks: [BPFormula]?, generation: UInt) {
        guard Self.shouldPublishReloadGeneration(generation, current: currentReloadGeneration) else { return }
        bpSynchronized(self) { _pinnedCasksStorage = casks as NSArray? }
        let names: [String]? = casks?.compactMap { ($0.name as NSString?)?.copy() as? String }
        publishUpdatesInput(names, key: "caskPins", generation: generation)
    }

    @objc open func cancelReload() {
        bpSynchronized(self) {
            reloadGeneration &+= 1
            _reloadRequestedWhileRunning = false
            _pendingRebuildCache = false
        }
        notifyUpdatesSnapshotChanged()
        BPHomebrewInterface.sharedInterface().cancelAllRunningTasks()
        delegate?.homebrewManagerFinishedStepping?(self)
    }

    @objc(announceStepForMode:generation:)
    open func announceStep(forMode mode: BPListMode, generation: UInt) {
        guard Self.shouldPublishReloadGeneration(generation, current: currentReloadGeneration) else {
            return
        }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.announceStep(forMode: mode, generation: generation)
            }
            return
        }
        delegate?.homebrewManager?(self, didBeginStepForMode: mode)
    }

    @objc(publishList:forMode:generation:)
    open func publishList(_ list: [BPFormula]?, forMode mode: BPListMode, generation: UInt) {
        var key: String?
        var frozen: [Any]?
        if mode == .outdated || mode == .outdatedCasks {
            key = (mode == .outdated) ? "formulae" : "casks"
            frozen = list.map { BPUpdateItem.items(fromFormulae: $0, cask: mode == .outdatedCasks) }
        } else if mode == .pinned {
            key = "formulaPins"
            frozen = list?.compactMap { ($0.name as NSString?)?.copy() as? String }
        }
        if let key {
            publishUpdatesInput(frozen, key: key, generation: generation)
        }

        guard Self.shouldPublishReloadGeneration(generation, current: currentReloadGeneration) else {
            return
        }

        if !Thread.isMainThread {
            nonisolated(unsafe) let listBox = list as NSArray?
            DispatchQueue.main.async { [weak self] in
                self?.publishListOnMain(listBox as? [BPFormula], forMode: mode, generation: generation)
            }
            return
        }
        publishListOnMain(list, forMode: mode, generation: generation)
    }

    private func publishListOnMain(_ list: [BPFormula]?, forMode mode: BPListMode, generation: UInt) {
        guard generation == currentReloadGeneration else { return }

        switch mode {
        case .installed:
            self.installedFormulae = list
        case .leaves:
            self.leavesFormulae = list
        case .outdated:
            self.outdatedFormulae = list
        case .repositories:
            self.repositoriesFormulae = list
        case .pinned:
            self.pinnedFormulae = list
        case .installedCasks:
            self.installedCasks = list
        case .outdatedCasks:
            self.outdatedCasks = list
        case .all:
            self.allFormulae = list
        case .allCasks:
            self.allCasks = list
        case .search:
            return
        }

        publishOutdatedSnapshot(forList: list, mode: mode, generation: generation)
        delegate?.homebrewManager?(self, didPublishListForMode: mode)
    }

    private func publishOutdatedSnapshot(forList list: [BPFormula]?, mode: BPListMode, generation: UInt) {
        guard mode == .outdated || mode == .outdatedCasks else { return }
        var snapshot: [String: Any]?
        bpSynchronized(self) {
            guard generation == reloadGeneration else { return }
            if _outdatedSnapshotGeneration != generation {
                _outdatedSnapshotGeneration = generation
                _outdatedSnapshotFormulaeCount = nil
                _outdatedSnapshotCaskCount = nil
                _didPublishOutdatedSnapshot = false
            }
            guard let list, !_didPublishOutdatedSnapshot else { return }
            if mode == .outdated {
                _outdatedSnapshotFormulaeCount = NSNumber(value: list.count)
            } else {
                _outdatedSnapshotCaskCount = NSNumber(value: list.count)
            }
            guard let formulaeCount = _outdatedSnapshotFormulaeCount,
                  let caskCount = _outdatedSnapshotCaskCount else {
                return
            }
            snapshot = [
                BPOutdatedSnapshotFormulaeCountKey: formulaeCount,
                BPOutdatedSnapshotCaskCountKey: caskCount,
                BPOutdatedSnapshotGenerationKey: NSNumber(value: generation)
            ]
            _didPublishOutdatedSnapshot = true
        }
        if let snapshot {
            NotificationCenter.default.post(
                name: Notification.Name(BPHomebrewManagerDidPublishOutdatedSnapshotNotification),
                object: self,
                userInfo: snapshot
            )
        }
    }

    @objc open func homebrewInterface() -> BPHomebrewInterface? {
        BPHomebrewInterface.sharedInterface()
    }

    @objc(refreshFormulaStateAfterRemovalWithCompletion:)
    open func refreshFormulaStateAfterRemoval(withCompletion completion: (@Sendable (Bool) -> Void)?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.refreshFormulaStateAfterRemoval(withCompletion: completion)
            }
            return
        }
        var generation: UInt = 0
        var shouldStart = false
        bpSynchronized(self) {
            if _formulaRefreshCompletions == nil {
                _formulaRefreshCompletions = NSMutableArray()
            }
            if let completion {
                _formulaRefreshCompletions?.add(completion as AnyObject)
            }
            if reloadInFlight {
                _formulaRefreshRequested = true
                return
            }
            shouldStart = true
            _formulaRefreshRequested = false
            reloadInFlight = true
            let caskCount = (_outdatedSnapshotGeneration == reloadGeneration) ? _outdatedSnapshotCaskCount : nil
            let baseline = self.updatesSnapshot
            reloadGeneration &+= 1
            generation = reloadGeneration
            _updatesGeneration = generation
            _updatesSnapshot = nil
            let inputs = NSMutableDictionary()
            if let baseline {
                inputs["casks"] = baseline.casks as NSArray
                inputs["formulaPins"] = baseline.pinnedFormulaNames as NSArray
                inputs["caskPins"] = baseline.pinnedCaskNames as NSArray
            }
            _updatesInputs = inputs
            _outdatedSnapshotGeneration = generation
            _outdatedSnapshotFormulaeCount = nil
            _outdatedSnapshotCaskCount = caskCount
            _didPublishOutdatedSnapshot = false
        }
        guard shouldStart else { return }
        notifyUpdatesSnapshotChanged()

        let capturedGeneration = generation
        let interface = self.homebrewInterface()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let installed = interface?.listMode(forRemovalRefresh: .installed)
            let leaves = interface?.listMode(forRemovalRefresh: .leaves)
            let outdated = interface?.listMode(forRemovalRefresh: .outdated)
            let services = interface?.listServicesForRemovalRefresh()
            DispatchQueue.main.async {
                guard let self else { return }
                var succeeded = (installed != nil && leaves != nil && outdated != nil && services != nil)
                if let installed {
                    self.publishList(installed, forMode: .installed, generation: capturedGeneration)
                }
                if let leaves {
                    self.publishList(leaves, forMode: .leaves, generation: capturedGeneration)
                }
                if let outdated {
                    self.publishList(outdated, forMode: .outdated, generation: capturedGeneration)
                }
                if capturedGeneration == self.currentReloadGeneration, let services {
                    self.services = services
                }
                succeeded = succeeded && (capturedGeneration == self.currentReloadGeneration)

                var completions: [(@Sendable (Bool) -> Void)] = []
                var rerun = false
                var rebuild = false
                var formulaRerun = false
                bpSynchronized(self) {
                    self.reloadInFlight = false
                    completions = (self._formulaRefreshCompletions as? [(@Sendable (Bool) -> Void)]) ?? []
                    self._formulaRefreshCompletions?.removeAllObjects()
                    rerun = self._reloadRequestedWhileRunning
                    rebuild = self._pendingRebuildCache
                    formulaRerun = self._formulaRefreshRequested
                    self._reloadRequestedWhileRunning = false
                    self._pendingRebuildCache = false
                }
                for done in completions {
                    done(succeeded)
                }
                if formulaRerun {
                    self.refreshFormulaStateAfterRemoval(withCompletion: nil)
                }
                if rerun {
                    self.reloadFromInterface(rebuildingCache: rebuild)
                }
            }
        }
    }

    @objc open var discoveryResult: BPHomebrewDiscoveryResult {
        bpSynchronized(self) {
            BPHomebrewDiscoveryResult(rawValue: _discoveryResultRaw) ?? .unknown
        }
    }

    @objc open var checkingHomebrew: Bool {
        bpSynchronized(self) {
            discoveryInFlight
        }
    }

    @objc open func isCheckingHomebrew() -> Bool {
        checkingHomebrew
    }

    @objc open func retryHomebrewDiscovery() {
        bpSynchronized(self) {
            if reloadInFlight { return }
            reloadFromInterface(rebuildingCache: false)
        }
    }

    @objc(reloadFromInterfaceRebuildingCache:)
    open func reloadFromInterface(rebuildingCache shouldRebuildCache: Bool) {
        var generation: UInt = 0
        var needsDiscovery = false
        var shouldStart = false

        bpSynchronized(self) {
            if discoveryInFlight { return }
            if !Self.shouldStartReload(whenInFlight: reloadInFlight) {
                _reloadRequestedWhileRunning = true
                _pendingRebuildCache = _pendingRebuildCache || shouldRebuildCache
                return
            }
            shouldStart = true
            reloadInFlight = true
            reloadGeneration &+= 1
            generation = reloadGeneration
            needsDiscovery = (BPHomebrewDiscoveryResult(rawValue: _discoveryResultRaw) != .available)
            discoveryInFlight = needsDiscovery
        }
        guard shouldStart else { return }

        notifyUpdatesSnapshotChanged()
        if needsDiscovery {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.homebrewManagerDidBeginDiscovery?(self)
            }
        }

        let capturedGeneration = generation
        let capturedNeedsDiscovery = needsDiscovery
        let previousCountOfAllFormulae = self.allFormulae?.count ?? 0

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let interface = self.homebrewInterface()
            interface?.delegate = self
            if capturedNeedsDiscovery {
                let result = interface?.discoverHomebrew() ?? .checkFailed
                let current = bpSynchronized(self) { capturedGeneration == self.reloadGeneration }
                if result != .available || !current {
                    DispatchQueue.main.async {
                        var pendingFormulaCompletions: [(@Sendable (Bool) -> Void)] = []
                        var publishFailure = false
                        bpSynchronized(self) {
                            self.discoveryInFlight = false
                            self.reloadInFlight = false
                            self._reloadRequestedWhileRunning = false
                            self._pendingRebuildCache = false
                            pendingFormulaCompletions = (self._formulaRefreshCompletions as? [(@Sendable (Bool) -> Void)]) ?? []
                            self._formulaRefreshCompletions?.removeAllObjects()
                            self._formulaRefreshRequested = false
                            publishFailure = (capturedGeneration == self.reloadGeneration)
                            if publishFailure {
                                self._discoveryResultRaw = result.rawValue
                            }
                        }
                        for done in pendingFormulaCompletions {
                            done(false)
                        }
                        if publishFailure {
                            self.delegate?.homebrewManager(self, shouldDisplayNoBrewMessage: true)
                        }
                    }
                    return
                }
                DispatchQueue.main.async {
                    var shouldNotify = false
                    bpSynchronized(self) {
                        self.discoveryInFlight = false
                        if capturedGeneration == self.reloadGeneration {
                            self._discoveryResultRaw = result.rawValue
                            shouldNotify = true
                        }
                    }
                    if shouldNotify {
                        self.delegate?.homebrewManager(self, shouldDisplayNoBrewMessage: false)
                    }
                }
            }

            let fanOut = DispatchQueue.global(qos: .utility)
            let group = DispatchGroup()

            nonisolated(unsafe) var fetchedServices: [BPService]?
            var didFetchCatalogs = false

            self.announceStep(forMode: .installed, generation: capturedGeneration)

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                self.publishList(interface?.listMode(.installed), forMode: .installed, generation: capturedGeneration)
            }

            let fastModes: [BPListMode] = [.leaves, .outdated, .repositories, .pinned, .installedCasks, .outdatedCasks]
            for mode in fastModes {
                group.enter()
                fanOut.async {
                    defer { group.leave() }
                    self.publishList(interface?.listMode(mode), forMode: mode, generation: capturedGeneration)
                }
            }

            group.enter()
            fanOut.async {
                defer { group.leave() }
                self.publishPinnedCasks(interface?.listPinnedCasks(), generation: capturedGeneration)
            }

            group.enter()
            fanOut.async {
                defer { group.leave() }
                fetchedServices = interface?.listServices()
            }

            group.wait()

            if !self.loadAllFormulaeCaches()
                || previousCountOfAllFormulae <= 100
                || self.allCasks == nil
                || shouldRebuildCache {
                didFetchCatalogs = true
                self.announceStep(forMode: .allCasks, generation: capturedGeneration)

                group.enter()
                fanOut.async {
                    defer { group.leave() }
                    self.publishList(interface?.listMode(.all), forMode: .all, generation: capturedGeneration)
                }

                group.enter()
                fanOut.async {
                    defer { group.leave() }
                    self.publishList(interface?.listMode(.allCasks), forMode: .allCasks, generation: capturedGeneration)
                }

                group.wait()
            }

            let finalServices = fetchedServices
            let finalDidFetchCatalogs = didFetchCatalogs
            DispatchQueue.main.async {
                var rerun = false
                var rerunRebuild = false
                var currentGen: UInt = 0
                var formulaRefreshReq = false

                bpSynchronized(self) {
                    self.reloadInFlight = false
                    rerun = self._reloadRequestedWhileRunning
                    rerunRebuild = self._pendingRebuildCache
                    self._reloadRequestedWhileRunning = false
                    self._pendingRebuildCache = false
                    currentGen = self.reloadGeneration
                    formulaRefreshReq = self._formulaRefreshRequested
                }

                if Self.shouldPublishReloadGeneration(capturedGeneration, current: currentGen) {
                    if finalDidFetchCatalogs {
                        DispatchQueue.global(qos: .utility).async {
                            self.storeAllFormulaeCaches()
                        }
                    }
                    self.services = finalServices
                    self.delegate?.homebrewManagerFinishedUpdating(self)
                    self.delegate?.homebrewManagerFinishedStepping?(self)
                }

                if formulaRefreshReq {
                    self.refreshFormulaStateAfterRemoval(withCompletion: nil)
                }
                if rerun {
                    self.reloadFromInterface(rebuildingCache: rerunRebuild)
                }
            }
        }
    }

    @objc(formulae:casks:matchingQuery:)
    public class func formulae(
        _ formulae: [BPFormula]?,
        casks: [BPFormula]?,
        matchingQuery query: String?
    ) -> [BPFormula] {
        guard let query, !query.isEmpty else { return [] }
        var matches: [BPFormula] = []
        for namespace in [formulae ?? [], casks ?? []] {
            for entry in namespace {
                if let entryName = entry.name as NSString?,
                   entryName.range(of: query, options: .caseInsensitive).location != NSNotFound {
                    matches.append(entry)
                }
            }
        }
        return matches
    }

    @objc(shouldPublishResultsForQuery:currentQuery:)
    public class func shouldPublishResults(forQuery query: String?, currentQuery: String?) -> Bool {
        guard let query, let currentQuery else { return false }
        return query == currentQuery
    }

    @objc(updateSearchWithName:)
    open func updateSearch(withName name: String?) {
        bpSynchronized(self) {
            _currentSearchQuery = (name as NSString?)?.copy() as? NSString
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let matches = Self.formulae(self.allFormulae, casks: self.allCasks, matchingQuery: name)
            DispatchQueue.main.async {
                let current = bpSynchronized(self) { self._currentSearchQuery as String? }
                guard Self.shouldPublishResults(forQuery: name, currentQuery: current) else {
                    return
                }
                self.searchFormulae = matches
                self.delegate?.homebrewManager(self, didUpdateSearchResults: matches)
            }
        }
    }

    @objc open func cancelSearch() {
        bpSynchronized(self) {
            _currentSearchQuery = nil
        }
    }

    @objc open func loadAllFormulaeCaches() -> Bool {
        guard let cachesFolder = BPAppDelegate.urlForApplicationCachesFolder() else {
            return false
        }
        let allFormulaeFile = cachesFolder.appendingPathComponent("allFormulae.cache.bin")
        guard FileManager.default.fileExists(atPath: allFormulaeFile.relativePath),
              let data = try? Data(contentsOf: allFormulaeFile) else {
            return false
        }

        let classes: [AnyClass] = [
            NSDictionary.self,
            NSArray.self,
            NSMutableArray.self,
            BPFormula.self,
            NSString.self,
            NSURL.self,
            NSNumber.self,
            NSDate.self,
            BPFormulaOption.self
        ]
        let cacheDict: [String: Any]?
        do {
            cacheDict = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? [String: Any]
        } catch {
            NSLog("Discarding unreadable catalog cache: %@", error.localizedDescription)
            discardCatalogCache()
            return false
        }

        guard let cacheDict else {
            discardCatalogCache()
            return false
        }

        guard (cacheDict[kBPCacheVersionKey] as? NSNumber)?.intValue == Self.kBPCacheVersion else {
            discardCatalogCache()
            return false
        }

        guard let storedDate = cacheDict[kBPCacheStoredDateKey] as? Date,
              Date().timeIntervalSince(storedDate) <= Self.kBPSecondsInADay else {
            discardCatalogCache()
            return false
        }

        guard let formulae = cacheDict[kBPCacheDataKey] as? [BPFormula] else {
            discardCatalogCache()
            return false
        }

        self.allFormulae = formulae
        self.allCasks = cacheDict[kBPCacheCasksDataKey] as? [BPFormula]
        return true
    }

    @objc open func discardCatalogCache() {
        if let cachesFolder = BPAppDelegate.urlForApplicationCachesFolder() {
            let allFormulaeFile = cachesFolder.appendingPathComponent("allFormulae.cache.bin")
            try? FileManager.default.removeItem(at: allFormulaeFile)
        }
        UserDefaults.standard.removeObject(forKey: kBPCacheLastUpdateKey)
    }

    @objc open func storeAllFormulaeCaches() {
        guard let allFormulae = self.allFormulae else { return }
        guard let cachesFolder = BPAppDelegate.urlForApplicationCachesFolder() else {
            NSLog("Could not store cache file. BPAppDelegate function returned nil!")
            return
        }
        let allFormulaeFile = cachesFolder.appendingPathComponent("allFormulae.cache.bin")
        let cacheDict: NSDictionary = [
            kBPCacheVersionKey: NSNumber(value: Self.kBPCacheVersion),
            kBPCacheStoredDateKey: Date() as NSDate,
            kBPCacheDataKey: allFormulae as NSArray,
            kBPCacheCasksDataKey: (self.allCasks ?? []) as NSArray
        ]

        let cacheData: Data
        do {
            cacheData = try NSKeyedArchiver.archivedData(withRootObject: cacheDict, requiringSecureCoding: true)
        } catch {
            NSLog("Failed encoding data: %@", error.localizedDescription)
            return
        }

        do {
            try cacheData.write(to: allFormulaeFile, options: .atomic)
        } catch {
            NSLog("Failed writing cache: %@", error.localizedDescription)
            return
        }

        UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: kBPCacheLastUpdateKey)
    }

    @objc(installedNameSetFromFormulae:)
    public class func installedNameSet(fromFormulae formulae: [Any]?) -> Set<String> {
        guard let formulae, !formulae.isEmpty else { return [] }
        var names = Set<String>(minimumCapacity: formulae.count)
        for item in formulae {
            guard let formula = item as? BPFormula,
                  let installedName = formula.installedName(),
                  !installedName.isEmpty else {
                continue
            }
            names.insert(installedName)
        }
        return names
    }

    @objc dynamic public var installedFormulae: [BPFormula]? {
        get { bpSynchronized(self) { _installedFormulaeStorage as? [BPFormula] } }
        set {
            let names = Self.installedNameSet(fromFormulae: newValue) as NSSet
            bpSynchronized(self) {
                _installedFormulaeStorage = newValue as NSArray?
                _installedFormulaNamesSet = names
            }
        }
    }

    @objc dynamic public var outdatedFormulae: [BPFormula]? {
        get { bpSynchronized(self) { _outdatedFormulaeStorage as? [BPFormula] } }
        set {
            let names = Self.installedNameSet(fromFormulae: newValue) as NSSet
            bpSynchronized(self) {
                _outdatedFormulaeStorage = newValue as NSArray?
                _outdatedFormulaNamesSet = names
            }
        }
    }

    @objc dynamic public var installedCasks: [BPFormula]? {
        get { bpSynchronized(self) { _installedCasksStorage as? [BPFormula] } }
        set {
            let names = Self.installedNameSet(fromFormulae: newValue) as NSSet
            bpSynchronized(self) {
                _installedCasksStorage = newValue as NSArray?
                _installedCaskNamesSet = names
            }
        }
    }

    @objc dynamic public var outdatedCasks: [BPFormula]? {
        get { bpSynchronized(self) { _outdatedCasksStorage as? [BPFormula] } }
        set {
            let names = Self.installedNameSet(fromFormulae: newValue) as NSSet
            bpSynchronized(self) {
                _outdatedCasksStorage = newValue as NSArray?
                _outdatedCaskNamesSet = names
            }
        }
    }

    @objc dynamic public var pinnedFormulae: [BPFormula]? {
        get {
            bpSynchronized(self) {
                guard _pinnedFormulaeStorage != nil || _pinnedCasksStorage != nil else { return nil }
                return (_pinnedFormulaeStorage as? [BPFormula] ?? []) + (_pinnedCasksStorage as? [BPFormula] ?? [])
            }
        }
        set {
            let names = Self.installedNameSet(fromFormulae: newValue) as NSSet
            bpSynchronized(self) {
                _pinnedFormulaeStorage = newValue as NSArray?
                _pinnedFormulaNamesSet = names
            }
        }
    }

    @objc(statusForFormula:)
    open func status(forFormula formula: Any?) -> BPFormulaStatus {
        guard let formula = formula as? BPFormula,
              let installedName = formula.installedName(),
              !installedName.isEmpty else {
            return .notInstalled
        }
        var installed: NSSet?
        var outdated: NSSet?
        bpSynchronized(self) {
            installed = formula.cask ? _installedCaskNamesSet : _installedFormulaNamesSet
            outdated = formula.cask ? _outdatedCaskNamesSet : _outdatedFormulaNamesSet
        }
        if installed?.contains(installedName) == true {
            if outdated?.contains(installedName) == true {
                return .outdated
            }
            return .installed
        }
        return .notInstalled
    }

    @objc(isFormulaPinned:)
    open func isFormulaPinned(_ formula: Any?) -> Bool {
        guard let formula = formula as? BPFormula,
              let installedName = formula.installedName(),
              !installedName.isEmpty else {
            return false
        }
        if formula.cask {
            let casks = bpSynchronized(self) { _pinnedCasksStorage as? [BPFormula] ?? [] }
            return Self.installedNameSet(fromFormulae: casks).contains(installedName)
        }
        let pinned = bpSynchronized(self) { _pinnedFormulaNamesSet }
        return pinned?.contains(installedName) == true
    }

    @objc open func cleanUp() {
        BPHomebrewInterface.sharedInterface().cleanup()
    }

    // MARK: - BPHomebrewInterfaceDelegate

    @objc(homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs:)
    open func homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs(_ shouldRebuildCatalogs: Bool) {
        reloadFromInterface(rebuildingCache: shouldRebuildCatalogs)
    }

    @objc(homebrewInterfaceShouldDisplayNoBrewMessage:)
    open func homebrewInterfaceShouldDisplayNoBrewMessage(_ yesOrNo: Bool) {
        delegate?.homebrewManager(self, shouldDisplayNoBrewMessage: yesOrNo)
    }
}

// MARK: - Test Subclasses for CakebrewTests

// 1. BPAutoremoveTests Subclasses
@objc(CB150RefreshInterface)
open class CB150RefreshInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var modes: NSMutableArray?
    @objc public var serviceCalls: UInt = 0
    @objc public var fail: Bool = false
    @objc public var discoveryEntered: (() -> Void)?
    @objc public var finishDiscovery: DispatchSemaphore?

    open override func discoverHomebrew() -> BPHomebrewDiscoveryResult {
        discoveryEntered?()
        if let finishDiscovery {
            _ = finishDiscovery.wait(timeout: .now() + 5.0)
        }
        return .missing
    }

    open override func listMode(_ mode: BPListMode) -> [BPFormula]? {
        modes?.add(NSNumber(value: mode.rawValue))
        return fail ? nil : []
    }

    open override func listServices() -> [BPService] {
        serviceCalls += 1
        return fail ? [] : []
    }

    open override func listMode(forRemovalRefresh mode: BPListMode) -> [BPFormula]? {
        listMode(mode)
    }

    open override func listServicesForRemovalRefresh() -> [BPService]? {
        serviceCalls += 1
        return fail ? nil : []
    }
}

@objc(CB150Manager)
open class CB150Manager: BPHomebrewManager, @unchecked Sendable {
    @objc public var fixtureInterface: BPHomebrewInterface?

    open override func homebrewInterface() -> BPHomebrewInterface? {
        fixtureInterface
    }
}

@objc(CB150Interface)
open class CB150Interface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var preview: BPAutoremovePreview?
    @objc public var previewCalls: UInt = 0
    @objc public var removalCalls: UInt = 0
    @objc public var removed: NSArray?
    @objc public var removalSuccess: Bool = false

    open override func previewAutoremove(withProgress progress: Progress?) -> BPAutoremovePreview {
        previewCalls += 1
        return preview ?? BPAutoremovePreview.preview(withOutput: "", succeeded: false)
    }

    open override func removeUnusedFormulae(
        _ names: [String]?,
        progress: Progress?,
        output: (@Sendable (String) -> Void)?
    ) -> Bool {
        precondition(!Thread.isMainThread, "removeUnusedFormulae must run off the main thread")
        removalCalls += 1
        removed = (names as NSArray?)?.copy() as? NSArray
        output?("fixture stream")
        return removalSuccess
    }
}

@objc(CB150CommandInterface)
open class CB150CommandInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var arguments: NSArray?
    @objc public var fixture: NSString?
    @objc public var status: Int32 = 0

    open override func executeAutoremoveArguments(
        _ arguments: [Any],
        progress: Progress?,
        output: (@Sendable (String) -> Void)?
    ) -> Int32 {
        self.arguments = (arguments as NSArray).copy() as? NSArray
        output?((fixture as String?) ?? "")
        return status
    }
}

@objc(CB150TaskInterface)
open class CB150TaskInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var script: NSString?
    @objc public var formatting: (() -> Void)?

    open override func formatAutoremoveArguments(_ arguments: [Any]) -> [Any] {
        formatting?()
        return ["-c", (script as String?) ?? ""]
    }
}

@objc(CB150RefreshShellInterface)
open class CB150RefreshShellInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var outputs: NSDictionary?
    @objc public var statuses: NSDictionary?
    @objc public var commands: NSMutableArray?

    open override func formatArguments(_ extraArguments: [Any]?, sendOutputId sendOutputID: Bool) -> [Any] {
        let key = (extraArguments ?? []).compactMap { $0 as? String }.joined(separator: " ")
        commands?.add(key)
        let outVal = (outputs?[key] as? String) ?? ""
        let statusVal = (statuses?[key] as? NSNumber)?.stringValue ?? "0"
        return [
            "-c",
            "printf 'login banner\\n+++++Cakebrew+++++\\n'; printf '%s' \"$1\"; exit \"$2\"",
            "fixture",
            outVal,
            statusVal
        ]
    }
}

// 2. BPBrewfileTests Subclasses
@objc(CB151ImportInterface)
open class CB151ImportInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var snapshotPath: NSString?
    @objc public var entered: (() -> Void)?
    @objc public var releaseCommand: DispatchSemaphore?
    @objc public var calls: UInt = 0

    open override func runBrewImportTool(
        withPath path: String?,
        progress: Progress?,
        withReturnsBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        calls += 1
        snapshotPath = (path as NSString?)?.copy() as? NSString
        precondition(!Thread.isMainThread, "Import must run off the main thread")
        if let path {
            precondition(FileManager.default.fileExists(atPath: path), "Snapshot file must exist")
        }
        block?("fixture output")
        entered?()
        if let releaseCommand {
            _ = releaseCommand.wait(timeout: .now() + 10.0)
        }
        return progress?.isCancelled != true
    }
}

@objc(CB151DirectInterface)
open class CB151DirectInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var duringFormatting: (() -> Void)?
    @objc public var receivedArguments: NSArray?

    open override func formatArguments(_ extraArguments: [Any]?, sendOutputId sendOutputID: Bool) -> [Any] {
        receivedArguments = (extraArguments as NSArray?)?.copy() as? NSArray
        duringFormatting?()
        return ["-c", "printf 'ACTUAL_FIXTURE_LAUNCH\\n'"]
    }
}

@objc(CBExportInterface)
open class CBExportInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var commandSucceeded: Bool = false
    @objc public var commandOutput: NSString?
    @objc public var exportArguments: NSArray?

    open override func performSyncBrewCommand(withArguments arguments: [Any]?) -> String? {
        exportArguments = (arguments as NSArray?)?.copy() as? NSArray
        return commandOutput as String?
    }

    open override func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        includesCompletionMessage: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        exportArguments = (arguments as NSArray?)?.copy() as? NSArray
        if let commandOutput {
            block?(commandOutput as String)
        }
        return commandSucceeded
    }
}

@objc(CBDelayedExportInterface)
open class CBDelayedExportInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var entered: (() -> Void)?
    @objc public var releaseCommand: DispatchSemaphore?
    @objc public var calls: UInt = 0
    @objc public var exportError: NSError?

    open override func runBrewExportTool(withPath path: String?) -> NSError? {
        precondition(!Thread.isMainThread, "Export must run off the main thread")
        precondition(path == "/fixture/Brewfile", "Unexpected export path")
        calls += 1
        entered?()
        if let releaseCommand {
            _ = releaseCommand.wait(timeout: .now() + 10.0)
        }
        return exportError
    }
}

// 3. BPHomebrewRecoveryTests Subclasses
@objc(BPRecoveryShellInterface)
open class BPRecoveryShellInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var shell: NSString?

    open override func getValidUserShellPath() -> String? {
        shell as String?
    }
}

@objc(BPRecoveryFixtureInterface)
open class BPRecoveryFixtureInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var nextResult: BPHomebrewDiscoveryResult = .unknown
    @objc public var discoveryCalls: UInt = 0
    @objc public var listCalls: UInt = 0
    @objc public var holdDiscovery: DispatchSemaphore?
    @objc public var onDiscovery: (() -> Void)?

    open override func discoverHomebrew() -> BPHomebrewDiscoveryResult {
        discoveryCalls += 1
        onDiscovery?()
        if let holdDiscovery {
            _ = holdDiscovery.wait(timeout: .now() + 5.0)
        }
        return nextResult
    }

    open override func listMode(_ mode: BPListMode) -> [BPFormula]? {
        bpSynchronized(self) { listCalls += 1 }
        return [BPFormula.formula(withName: "recovered")].compactMap { $0 }
    }

    open override func listPinnedCasks() -> [BPFormula]? {
        bpSynchronized(self) { listCalls += 1 }
        return []
    }

    open override func listServices() -> [BPService] {
        bpSynchronized(self) { listCalls += 1 }
        return []
    }
}

@objc(BPRecoveryFixtureManager)
open class BPRecoveryFixtureManager: BPHomebrewManager, @unchecked Sendable {
    @objc public var fixture: BPRecoveryFixtureInterface?

    open override func homebrewInterface() -> BPHomebrewInterface? {
        fixture
    }

    open override func loadAllFormulaeCaches() -> Bool {
        false
    }

    open override func storeAllFormulaeCaches() {}
}

// 4. BPUpgradePlanTests Subclasses
@objc(BPUpgradeInterfaceRecorder)
open class BPUpgradeInterfaceRecorder: BPHomebrewInterface, @unchecked Sendable {
    @objc public var commands: NSMutableArray?
    @objc public var seenProgress: Progress?
    @objc public var reloads: UInt = 0
    @objc public var failFirst: Bool = false
    @objc public var cancelFirst: Bool = false

    open override func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        progress: Progress?,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        precondition(!isSynchronous, "Upgrade command must not be synchronous")
        precondition(reloads == 0, "Reload must wait until every attempted batch exits")
        seenProgress = progress
        if let arguments {
            commands?.add(arguments as NSArray)
        }
        block?("batch output\n")
        if cancelFirst {
            progress?.cancel()
        }
        return !failFirst
    }

    open override func sendDelegateFormulaeUpdatedCall(forCommand command: String?) {
        precondition(command == "upgrade", "Expected upgrade command")
        reloads += 1
    }
}

@objc(BPUpdatesReadRecorder)
open class BPUpdatesReadRecorder: BPHomebrewInterface, @unchecked Sendable {
    @objc public var readSucceeded: Bool = false
    @objc public var readOutput: NSString?
    @objc public var readArguments: NSArray?

    open override func performCleanReadOnlyBrewCommand(
        withArguments arguments: [Any]?,
        output result: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        readArguments = (arguments as NSArray?)?.copy() as? NSArray
        result?.pointee = readOutput
        return readSucceeded
    }

    open override func performSyncBrewCommand(withArguments arguments: [Any]?) -> String? {
        preconditionFailure("Update and pin inventories must preserve process success")
    }
}

// 5. BPMockFidelityTests Subclasses
#if DEBUG
@objc(CBCatalogCondition)
open class CBCatalogCondition: NSCondition, @unchecked Sendable {
    @objc public var observedArrivalCount: UInt = 0
    @objc public var waitingThreads: NSMutableSet = NSMutableSet()

    public override init() {
        super.init()
        waitingThreads = NSMutableSet()
    }

    open override func wait() {
        let current = Thread.current
        if !waitingThreads.contains(current) {
            waitingThreads.add(current)
            observedArrivalCount = UInt(waitingThreads.count)
        }
        super.wait()
    }
}

@objc(CBHeldCatalogInterface)
open class CBHeldCatalogInterface: BPMockHomebrewInterface, @unchecked Sendable {
    @objc public var observedCondition: CBCatalogCondition?
    @objc public var slowCatalogEnabled: Bool = false
    @objc public var normalReleaseEnabled: Bool = false
    @objc public var cancellations: UInt = 0

    @objc(initUniqueInstance)
    public required init(uniqueInstance: Void = ()) {
        super.init(uniqueInstance: ())
        if observedCondition == nil {
            let cond = CBCatalogCondition()
            observedCondition = cond
            self.catalogCondition = cond
        }
    }

    public override init() {
        super.init()
        if observedCondition == nil {
            let cond = CBCatalogCondition()
            observedCondition = cond
            self.catalogCondition = cond
        }
    }

    open override func makeCatalogCondition() -> NSCondition {
        let cond = CBCatalogCondition()
        observedCondition = cond
        return cond
    }

    open override func mockArgumentEnabled(_ argument: String) -> Bool {
        if argument == "-BPMockHoldCatalogUntilCancelled" {
            return !normalReleaseEnabled
        }
        if argument == "-BPMockHoldCatalogUntilReleased" {
            return normalReleaseEnabled
        }
        if argument == "-BPMockSlowCatalog" {
            return slowCatalogEnabled
        }
        return false
    }

    open override func cancelAllRunningTasks() {
        cancellations += 1
        super.cancelAllRunningTasks()
    }
}

@objc(CBHeldImportInterface)
open class CBHeldImportInterface: BPMockHomebrewInterface, @unchecked Sendable {
    @objc public var arguments: NSSet?
    @objc public var pauseCondition: NSCondition?
    @objc public var pauseCount: UInt = 0
    @objc public var returned: Bool = false
    @objc public var pauseReleased: Bool = false

    open override func mockArgumentEnabled(_ argument: String) -> Bool {
        arguments?.contains(argument) == true
    }

    open override func brewfileImportDeadline() -> Date {
        Date.distantPast
    }

    open override func pauseBrewfileImport() {
        pauseCondition?.lock()
        pauseCount += 1
        while !pauseReleased {
            pauseCondition?.wait()
        }
        pauseCondition?.unlock()
    }

    @objc open func releasePause() {
        pauseCondition?.lock()
        pauseReleased = true
        pauseCondition?.broadcast()
        pauseCondition?.unlock()
    }
}

@objc(CBCatalogCompletionManager)
open class CBCatalogCompletionManager: BPHomebrewManager, @unchecked Sendable {
    @objc public var fixture: CBHeldCatalogInterface?

    open override func homebrewInterface() -> BPHomebrewInterface? {
        fixture
    }

    open override func loadAllFormulaeCaches() -> Bool {
        false
    }

    open override func storeAllFormulaeCaches() {}
}
#endif

// 6. BPServiceDetailsTests Subclasses
@objc(BPServiceInfoFixtureInterface)
open class BPServiceInfoFixtureInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var arguments: NSArray?
    @objc public var fixture: NSString?
    @objc public var succeeded: Bool = false
    @objc public var readOnly: Bool = false
    @objc public var footer: Bool = false

    open override func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        includesCompletionMessage: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        self.arguments = (arguments as NSArray?)?.copy() as? NSArray
        self.readOnly = isSynchronous
        self.footer = includesCompletionMessage
        block?((fixture as String?) ?? "")
        return succeeded
    }
}

@objc(BPServiceInfoShellInterface)
open class BPServiceInfoShellInterface: BPHomebrewInterface, @unchecked Sendable {
    @objc public var fixtureCommand: NSString?

    open override func formatArguments(_ extraArguments: [Any]?, sendOutputId sendOutputID: Bool) -> [Any] {
        ["-c", (fixtureCommand as String?) ?? ""]
    }
}

