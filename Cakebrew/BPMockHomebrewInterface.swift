import CryptoKit
import Darwin
import Foundation

#if DEBUG
@objc(BPMockHomebrewInterface)
open class BPMockHomebrewInterface: BPHomebrewInterface, @unchecked Sendable {
    // All stored properties have zero-byte defaults so class_createInstance(Cls, 0) works safely.
    @objc public var mockLatestFormulaUnpinned = false
    @objc public var mockHistoricalFormulaUnpinned = false
    @objc public var mockHistoricalFormulaUnlinked = false
    @objc public var mockHistoricalCaskInstalled = false
    @objc public var mockCaskPinned = false
    @objc public var mockPinnedCaskReturned = false
    @objc public var mockPinnedCaskUnpinned = false
    @objc public var discoveryAttempts: UInt = 0
    @objc public var autoremovePreviews: UInt = 0
    private var _catalogConditionStorage: NSCondition?
    @objc public var catalogHoldReleased: Bool = false

    @objc public var catalogCondition: NSCondition {
        get {
            bpSynchronized(self) {
                if let existing = _catalogConditionStorage {
                    return existing
                }
                let created = makeCatalogCondition()
                _catalogConditionStorage = created
                return created
            }
        }
        set {
            bpSynchronized(self) {
                _catalogConditionStorage = newValue
            }
        }
    }

    @objc(initUniqueInstance)
    public required init(uniqueInstance: Void = ()) {
        super.init(uniqueInstance: ())
        _catalogConditionStorage = makeCatalogCondition()
    }

    public override init() {
        super.init()
        _catalogConditionStorage = makeCatalogCondition()
    }

    @objc open func makeCatalogCondition() -> NSCondition {
        NSCondition()
    }

    @objc(mockArgumentEnabled:)
    open func mockArgumentEnabled(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    @objc(releaseHeldCatalogs:)
    open func releaseHeldCatalogs(_ sender: Any?) {
        let cond = self.catalogCondition
        cond.lock()
        catalogHoldReleased = true
        cond.broadcast()
        cond.unlock()
    }

    open override func cancelAllRunningTasks() {
        releaseHeldCatalogs(nil)
        super.cancelAllRunningTasks()
    }

    open override func listMode(forRemovalRefresh mode: BPListMode) -> [BPFormula]? {
        guard mode == .installed || mode == .leaves || mode == .outdated else {
            return nil
        }
        return listMode(mode)
    }

    open override func listServicesForRemovalRefresh() -> [BPService]? {
        if ProcessInfo.processInfo.arguments.contains("-BPMockFailedAutoremoveRefresh") {
            return nil
        }
        return listServices()
    }

    open override func previewAutoremove(withProgress progress: Progress?) -> BPAutoremovePreview {
        autoremovePreviews += 1
        let arguments = ProcessInfo.processInfo.arguments
        var output = "==> Would autoremove 1 unneeded formula:\nmockunused\n"
        if arguments.contains("-BPMockEmptyAutoremove")
            || (arguments.contains("-BPMockChangedAutoremove") && autoremovePreviews > 1) {
            output = ""
        }
        if arguments.contains("-BPMockInvalidAutoremove") {
            output = "MOCK_UNRECOGNIZED\n"
        }
        return BPAutoremovePreview.preview(withOutput: output, succeeded: progress?.isCancelled != true)
    }

    open override func removeUnusedFormulae(
        _ names: [String]?,
        progress: Progress?,
        output: (@Sendable (String) -> Void)?
    ) -> Bool {
        if progress?.isCancelled == true {
            return false
        }
        output?("MOCK_AUTOREMOVE_STARTED\n")
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-BPMockSlowAutoremove") {
            let deadline = Date(timeIntervalSinceNow: 10)
            while progress?.isCancelled != true && deadline.timeIntervalSinceNow > 0 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        if progress?.isCancelled == true {
            output?("MOCK_AUTOREMOVE_CANCELLED\n")
            return false
        }
        if arguments.contains("-BPMockFailedAutoremove") {
            output?("MOCK_AUTOREMOVE_FAILED\n")
            return false
        }
        output?("MOCK_AUTOREMOVE_OK\n")
        return true
    }

    open override func discoverHomebrew() -> BPHomebrewDiscoveryResult {
        discoveryAttempts += 1
        let arguments = ProcessInfo.processInfo.arguments
        if discoveryAttempts > 1 && arguments.contains("-BPMockSlowHomebrewRetry") {
            Thread.sleep(forTimeInterval: 3.0)
        }
        if arguments.contains("-BPMockHomebrewInvalidShell") {
            return .invalidShell
        }
        if arguments.contains("-BPMockHomebrewCheckFailed") {
            return .checkFailed
        }
        if arguments.contains("-BPMockHomebrewMissing")
            || (arguments.contains("-BPMockHomebrewRecovers") && discoveryAttempts == 1) {
            return .missing
        }
        return .available
    }

    open override func listPinnedCasks() -> [BPFormula]? {
        guard mockCaskPinned || (mockArgumentEnabled("-BPMockPinnedHistory") && !mockPinnedCaskReturned && !mockPinnedCaskUnpinned) else { return [] }
        let cask = BPFormula.formula(withName: "mockchrome", andVersion: mockHistoricalCaskInstalled ? "0.9.0" : "1.0.0")
        cask.cask = true
        return [cask]
    }

    open override func setCaskPinned(_ name: String?, pinned: Bool) -> Bool {
        mockCaskPinned = pinned
        sendDelegateFormulaeUpdatedCall(forCommand: pinned ? "pin" : "unpin")
        return true
    }

    open override func listMode(_ mode: BPListMode) -> [BPFormula]? {
        if mode == .all || mode == .allCasks {
            if mockArgumentEnabled("-BPMockHoldCatalogUntilCancelled")
                || mockArgumentEnabled("-BPMockHoldCatalogUntilReleased") {
                let cond = self.catalogCondition
                cond.lock()
                while !catalogHoldReleased {
                    cond.wait()
                }
                cond.unlock()
            } else if mockArgumentEnabled("-BPMockSlowCatalog") {
                Thread.sleep(forTimeInterval: 6.0)
            }
        }

        switch mode {
        case .installed:
            let wget = BPFormula.formula(withName: "mockwget", andVersion: "1.0.0")
            // Exercise the browser's cached-description path without asking the
            // inspector to fetch metadata merely to draw the package list.
            wget.shortDescription = "A mock formula used for Cakebrew UI tests."
            return [
                wget,
                BPFormula.formula(withName: "mockgit", andVersion: "2.39.0"),
                BPFormula.formula(withName: "mockcurl", andVersion: "8.0.0")
            ].compactMap { $0 }
        case .outdated:
            if ProcessInfo.processInfo.arguments.contains("-BPMockEmptyOutdated") {
                return []
            }
            return [
                BPFormula.formula(withName: "mockgit", version: "2.39.0", andLatestVersion: "2.40.0")
            ].compactMap { $0 }
        case .leaves:
            return [
                BPFormula.formula(withName: "mockwget", andVersion: "1.0.0")
            ].compactMap { $0 }
        case .all:
            return [
                BPFormula.formula(withName: "mockwget"),
                BPFormula.formula(withName: "mockgit"),
                BPFormula.formula(withName: "mockcurl"),
                BPFormula.formula(withName: "mockhtop")
            ].compactMap { $0 }
        case .repositories:
            return [
                BPFormula.formula(withName: "homebrew/core"),
                BPFormula.formula(withName: "homebrew/cask")
            ].compactMap { $0 }
        case .pinned:
            if mockArgumentEnabled("-BPMockPinnedHistory") {
                return mockHistoricalFormulaUnpinned ? [] : [BPFormula.formula(withName: "mockwget@0.9.0", andVersion: "0.9.0")]
            }
            if mockLatestFormulaUnpinned { return [] }
            if ProcessInfo.processInfo.arguments.contains("-BPMockMixedUpdates") {
                return []
            }
            return [
                BPFormula.formula(withName: "mockgit")
            ].compactMap { $0 }
        case .installedCasks:
            return Self.casks(fromFormulae: [
                BPFormula.formula(withName: "mockchrome", andVersion: "120.0"),
                BPFormula.formula(withName: "mockvscode", andVersion: "1.85.0")
            ].compactMap { $0 })
        case .outdatedCasks:
            if ProcessInfo.processInfo.arguments.contains("-BPMockEmptyOutdatedCasks") {
                return []
            }
            return Self.casks(fromFormulae: [
                BPFormula.formula(withName: "mockchrome", version: "120.0", andLatestVersion: "121.0")
            ].compactMap { $0 })
        case .allCasks:
            return Self.casks(fromFormulae: [
                BPFormula.formula(withName: "mockchrome"),
                BPFormula.formula(withName: "mockvscode"),
                BPFormula.formula(withName: "mockfirefox")
            ].compactMap { $0 })
        default:
            return []
        }
    }

    @objc(casksFromFormulae:)
    public class func casks(fromFormulae formulae: [BPFormula]) -> [BPFormula] {
        for formula in formulae {
            formula.cask = true
        }
        return formulae
    }

    open override func runDoctor(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        if let block {
            block("MOCK_DOCTOR_OK\n")
            block("Checking for common problems...\n")
            block("MOCK_DOCTOR_DONE\nYour system is ready to brew.\n")
        }
        return true
    }

    open override func update(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_UPDATE_OK\nAlready up-to-date.\n")
        return true
    }

    open override func runCleanup(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_CLEANUP_OK\nFreed 0 bytes.\n")
        return true
    }

    open override func previewCleanup() -> BPCleanupPreview {
        if ProcessInfo.processInfo.arguments.contains("-BPMockEmptyCleanup") {
            return BPCleanupPreview.preview(fromOutput: "")
        }
        return BPCleanupPreview.preview(
            fromOutput: "Would remove: /Users/mock/Library/Caches/Homebrew/mockwget--1.0.0.tar.gz (1.5MB)\n"
                + "Would remove: /opt/homebrew/Cellar/mockgit/2.38.0 (1,234 files, 45.6MB)\n"
                + "Would remove: /Users/mock/Library/Caches/Homebrew/mockcurl--7.9.0.tar.gz (2.1MB)\n"
                + "==> This operation would free approximately 49.2MB of disk space.\n"
        )
    }

    open override func information(forFormulaName name: String?) -> String? {
        let fName = name ?? ""
        return "\(fName): stable 1.0.0\n"
            + "A mock formula used for Cakebrew UI tests.\n"
            + "https://example.com\n"
            + "Not installed\n"
            + "From: https://example.com/\(fName).rb\n"
            + "License: MIT\n"
            + "==> Dependencies\n"
            + "Required (1): mockgit\n"
            + "Recursive Runtime (1): all installed ✔\n"
            + "==> Analytics\n"
            + "install: 42 (30 days)\n"
            + "==> Options\n"
            + "--with-debug\n"
            + "\tBuild with debug symbols\n"
            + "--HEAD\n"
            + "\tInstall HEAD version\n"
    }

    open override func dependants(forFormulaName name: String?, onlyInstalled: Bool) -> String? {
        if name == "mockwget" {
            return onlyInstalled ? "mockcurl\n" : "mockcurl\nmockhtop\n"
        }
        return ""
    }

    open override func information(forCaskName name: String?) -> String? {
        let cName = name ?? ""
        return "==> \(cName) (Mock App): 1.0.0 (auto_updates)\n"
            + "A mock cask used for Cakebrew UI tests.\n"
            + "https://example.com/cask\n"
            + "Installed (on request)\n"
            + "/usr/local/Caskroom/\(cName)/1.0.0 (10MB)\n"
            + "From: https://example.com/\(cName).rb\n"
    }

    private func pinnedMockRelease(cask: Bool) -> BPVersionRelease {
        let name = cask ? "mockchrome" : "mockwget"
        let source = BPVersionHistorySource(url: URL(string: "https://github.com/Homebrew/homebrew-\(cask ? "cask" : "core")/blob/HEAD/\(cask ? "Casks" : "Formula")/m/\(name).rb")!)!
        return BPVersionRelease(version: "0.9.0", commit: String(repeating: "a", count: 40), date: "", message: "", source: source)
    }

    override func versionHistoryReceipt(name: String, cask: Bool) -> BPVersionRelease? {
        guard mockArgumentEnabled("-BPMockPinnedHistory"), !mockArgumentEnabled("-BPMockPinnedMissingReceipt") else { return nil }
        let release = pinnedMockRelease(cask: cask)
        return name == release.target ? release : nil
    }

    open override func readVersionHistoryCommand(_ arguments: [String], progress: Progress? = nil) -> (succeeded: Bool, output: String) {
        if arguments == ["tap"] { return (true, "homebrew/core\ncakebrew/versions\n") }
        if arguments == ["formulae"] {
            if mockArgumentEnabled("-BPMockPinnedNoOrigin") { return (true, "") }
            return (true, mockArgumentEnabled("-BPMockPinnedAmbiguousOrigin")
                ? "mockwget\nmockwget@1\n" : "mockwget\nmockgit\ncakebrew/versions/mockwget@0.9.0\n")
        }
        if arguments == ["casks"] {
            return (true, mockArgumentEnabled("-BPMockPinnedAmbiguousOrigin")
                ? "mockchrome\nexample/apps/mockchrome\n" : "mockchrome\n")
        }
        if arguments.contains("--installed") {
            let cask = arguments.contains("--cask")
            let historical = mockArgumentEnabled("-BPMockPinnedHistory")
            let release = pinnedMockRelease(cask: cask)
            let name = cask ? "mockchrome" : (historical ? "mockwget@0.9.0" : "mockgit")
            let tap = historical ? release.destinationTap : (cask ? "homebrew/cask" : "homebrew/core")
            var metadata: [String: Any] = ["tap": tap, "pinned": true, "homepage": "https://example.com/\(name.components(separatedBy: "@")[0])"]
            if cask {
                metadata["token"] = name
                metadata["installed"] = "0.9.0"
            } else {
                metadata["name"] = name
                metadata["installed"] = [["version": historical ? "0.9.0" : "1.0.0"]]
                metadata["linked_keg"] = historical ? "0.9.0" : "1.0.0"
            }
            let data = try! JSONSerialization.data(withJSONObject: [cask ? "casks" : "formulae": [metadata]])
            return (true, String(decoding: data, as: UTF8.self))
        }
        let name = arguments.last ?? ""
        if arguments.first == "--repository" { return (true, "/tmp/mock-history-tap") }
        if arguments.contains("--cask") {
            let historical = name.hasPrefix("cakebrew/history-")
            let fixtureOld = mockArgumentEnabled("-BPMockPinnedHistory") && !mockPinnedCaskReturned
            let installed = mockHistoricalCaskInstalled || (mockArgumentEnabled("-BPMockPinnedHistory") && !mockPinnedCaskReturned) ? "0.9.0" : "1.0.0"
            let metadata: [String: Any] = [
                "version": historical ? "0.9.0" : "1.0.0", "installed": installed,
                "token": "mockchrome", "tap": historical ? pinnedMockRelease(cask: true).destinationTap :
                    (name.contains("/") ? name.split(separator: "/").dropLast().joined(separator: "/") : "homebrew/cask"),
                "homepage": "https://example.com/mockchrome",
                "pinned": mockCaskPinned || (fixtureOld && !mockPinnedCaskUnpinned),
                "pinned_version": mockCaskPinned || (fixtureOld && !mockPinnedCaskUnpinned) ? installed as Any : NSNull(),
                "sha256": String(repeating: "a", count: 64)
            ]
            let data = try! JSONSerialization.data(withJSONObject: ["casks": [metadata]])
            return (true, String(decoding: data, as: UTF8.self))
        }
        let version = name.components(separatedBy: "@").last ?? "1.0.0"
        let stable = name.contains("cakebrew/versions/") ? version : "1.0.0"
        let historical = name.hasPrefix("cakebrew/versions/")
        let pinned = historical ? !mockHistoricalFormulaUnpinned : !mockLatestFormulaUnpinned
        let linked = historical && mockHistoricalFormulaUnlinked ? "" : stable
        return (true, "{\"formulae\":[{\"name\":\"\(name.split(separator: "/").last ?? "")\",\"tap\":\"\(historical ? "cakebrew/versions" : "homebrew/core")\",\"homepage\":\"https://example.com/\((name.split(separator: "/").last.map(String.init) ?? "").components(separatedBy: "@")[0])\",\"versions\":{\"stable\":\"\(stable)\"},\"installed\":[{\"version\":\"\(stable)\"}],\"pinned\":\(pinned),\"linked_keg\":\"\(linked)\"}]}")
    }

    open override func runVersionHistoryCommand(_ arguments: [String], progress: Progress,
                                                output: (@Sendable (String) -> Void)?) -> Bool {
        output?("MOCK_VERSION_COMMAND \(arguments.joined(separator: " "))\n")
        guard !progress.isCancelled,
              !(["install", "reinstall"].contains(arguments.first ?? "") && mockArgumentEnabled("-BPMockVersionInstallFailure")) else { return false }
        if mockArgumentEnabled("-BPMockReturnLatestFailure"), arguments.first == "link",
           arguments.last?.hasPrefix("homebrew/") == true { return false }
        if arguments.contains("--cask") {
            if ["install", "reinstall"].contains(arguments.first ?? "") {
                mockHistoricalCaskInstalled = arguments.last?.hasPrefix("cakebrew/history-") == true
                if arguments.last?.hasPrefix("homebrew/") == true { mockPinnedCaskReturned = true }
            }
            if arguments.first == "pin" { mockCaskPinned = true }
            if arguments.first == "unpin" { mockCaskPinned = false; mockPinnedCaskUnpinned = true }
        } else {
            let historical = arguments.last?.hasPrefix("cakebrew/versions/") == true
            if arguments.first == "unpin" {
                if historical { mockHistoricalFormulaUnpinned = true } else { mockLatestFormulaUnpinned = true }
            }
            if arguments.first == "pin" {
                if historical { mockHistoricalFormulaUnpinned = false } else { mockLatestFormulaUnpinned = false }
            }
            if arguments.first == "unlink", historical { mockHistoricalFormulaUnlinked = true }
            if arguments.first == "link", historical { mockHistoricalFormulaUnlinked = false }
        }
        return true
    }

    open override func pinFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_PIN_OK\n")
        return true
    }

    open override func uninstallCask(_ cask: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        uninstallCask(cask, zap: false, withReturnBlock: block)
    }

    open override func uninstallCask(
        _ cask: String?,
        zap: Bool,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        block?(zap ? "MOCK_UNINSTALL_CASK_ZAP_OK\n" : "MOCK_UNINSTALL_CASK_OK\n")
        return true
    }

    open override func upgradeFormulae(_ formulae: [Any]?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_UPGRADE_OK\nUpgraded 0 formulae.\n")
        return true
    }

    open override func upgradeCasks(_ casks: [Any]?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        true
    }

    open override func upgradeSelectedFormulae(
        _ formulae: [BPFormula]?,
        progress: Progress?,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        upgradeSelectionReporting(formulae, progress: progress, withReturnBlock: block).succeeded
    }

    open override func upgradeSelectionReporting(
        _ formulae: [BPFormula]?,
        progress: Progress?,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> BPUpgradeResult {
        let plan = BPUpgradePlan(selection: formulae)
        return plan.executeReporting(withProgress: progress) { arguments in
            let procArgs = ProcessInfo.processInfo.arguments
            if procArgs.contains("-BPMockSlowUpgrade") {
                block?("MOCK_UPGRADE_STARTED\n")
                for _ in 0..<100 {
                    if progress?.isCancelled == true { break }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if progress?.isCancelled == true {
                    block?("MOCK_UPGRADE_CANCELLING\n")
                    Thread.sleep(forTimeInterval: 5.0)
                    return false
                }
            }
            block?("MOCK_UPGRADE_OK\nMOCK_UPGRADE_ARGUMENTS: \(arguments.joined(separator: " "))\nUpgraded 0 packages.\n")
            if procArgs.contains("-BPMockFailedCaskUpgrade") && arguments.contains("--cask") {
                return false
            }
            return true
        }
    }

    open override func installCask(_ cask: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_INSTALL_CASK_OK\n")
        return true
    }

    open override func listServices() -> [BPService] {
        BPService.services(
            fromJSONString: "[{\"name\":\"mockpostgres\",\"status\":\"started\",\"user\":\"mockuser\",\"pid\":123},"
                + "{\"name\":\"mockredis\",\"status\":\"none\",\"user\":null,\"pid\":null}]"
        )
    }

    open override func startService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_SERVICE_START_OK\n")
        return true
    }

    open override func serviceDetails(forName name: String?) -> BPServiceDetails {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-BPMockServiceDetailsFailure") {
            return BPServiceDetails.details(
                forName: name,
                output: "Error: mock service details unavailable\nThe mock service list is still available.",
                succeeded: false
            )
        }
        if arguments.contains("-BPMockSlowServiceDetails") {
            Thread.sleep(forTimeInterval: 2.0)
        }
        let sName = name ?? ""
        let running = (sName == "mockpostgres")
        let record: [String: Any] = [
            "name": sName,
            "status": running ? "started" : "none",
            "pid": running ? NSNumber(value: 123) : NSNull(),
            "user": running ? "mockuser" : NSNull(),
            "file": "/cakebrew-mock-missing/service.plist",
            "log_path": "/cakebrew-mock-missing/service.log",
            "error_log_path": "/cakebrew-mock-missing/service.log",
            "exit_code": NSNull()
        ]
        let data = try? JSONSerialization.data(withJSONObject: [record], options: [])
        let output = data.flatMap { String(data: $0, encoding: .utf8) }
        return BPServiceDetails.details(forName: name, output: output, succeeded: true)
    }

    open override func stopService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_SERVICE_STOP_OK\n")
        return true
    }

    open override func restartService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_SERVICE_RESTART_OK\n")
        return true
    }

    open override func unpinFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_UNPIN_OK\n")
        return true
    }

    open override func installFormula(
        _ formula: String?,
        withOptions options: [Any]?,
        andReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        block?("MOCK_INSTALL_OK\nInstalled 1 formula.\n")
        return true
    }

    open override func uninstallFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_UNINSTALL_OK\nUninstalled 1 formula.\n")
        return true
    }

    open override func tapRepository(_ repository: String?, withReturnsBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_TAP_OK\nTapped 1 repository.\n")
        return true
    }

    open override func untapRepository(_ repository: String?, withReturnsBlock block: (@Sendable (String) -> Void)?) -> Bool {
        block?("MOCK_UNTAP_OK\nUntapped 1 repository.\n")
        return true
    }

    open override func runBrewExportTool(withPath path: String?) -> NSError? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-BPMockSlowExport") {
            Thread.sleep(forTimeInterval: 10.0)
        }
        if args.contains("-BPMockExportFails") {
            return NSError(
                domain: "Cakebrew.Mock.Export",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "MOCK_EXPORT_FAILED: destination is not writable."]
            )
        }
        return nil
    }

    open override func runBrewImportTool(
        withPath path: String?,
        withReturnsBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        block?("MOCK_IMPORT_OK\nBrewfile applied.\n")
        return true
    }

    @objc open func brewfileImportDeadline() -> Date {
        Date(timeIntervalSinceNow: 5.0)
    }

    @objc open func pauseBrewfileImport() {
        Thread.sleep(forTimeInterval: 0.05)
    }

    open override func runBrewImportTool(
        withPath path: String?,
        progress: Progress?,
        withReturnsBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        if progress?.isCancelled == true {
            return false
        }
        block?("MOCK_IMPORT_STARTED\n")
        let holdUntilCancelled = mockArgumentEnabled("-BPMockHoldBrewfileImportUntilCancelled")
        if holdUntilCancelled || mockArgumentEnabled("-BPMockSlowBrewfileImport") {
            let deadline = brewfileImportDeadline()
            while progress?.isCancelled != true && (holdUntilCancelled || deadline.timeIntervalSinceNow > 0) {
                pauseBrewfileImport()
            }
        }
        if progress?.isCancelled == true {
            block?("MOCK_IMPORT_CANCELLED\n")
            return false
        }
        if mockArgumentEnabled("-BPMockBrewfileImportFails") {
            block?("MOCK_IMPORT_FAILED\n")
            return false
        }
        block?("MOCK_IMPORT_OK\n")
        return true
    }
}
#endif
