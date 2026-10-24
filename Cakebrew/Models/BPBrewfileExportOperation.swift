import CryptoKit
import Darwin
import Foundation

// MARK: - Objective-C Runtime Bridges for Remaining Legacy Classes

@objc public protocol BPFormulaObjCBridge: NSObjectProtocol {
    var name: String? { get }
    var version: String? { get }
    var latestVersion: String? { get }
    var shortLatestVersion: String? { get }
    var information: String? { get }
    var installPath: String? { get }
    var dependencies: String? { get }
    var conflicts: String? { get }
    var shortDescription: String? { get }
    var website: URL? { get }
    var options: [Any]? { get }
    var needsInformation: Bool { get set }
    var cask: Bool { get set }
    @objc(installedName) func installedName() -> String?
    @objc(isInstalled) func isInstalled() -> Bool
    @objc(isOutdated) func isOutdated() -> Bool
}

@objc public protocol BPFormulaClassObjCBridge: NSObjectProtocol {
    @objc(formulaWithName:version:andLatestVersion:)
    func formula(withName name: String, version: String?, andLatestVersion latestVersion: String?) -> AnyObject?
    @objc(formulaWithName:andVersion:)
    func formula(withName name: String, andVersion version: String?) -> AnyObject?
    @objc(formulaWithName:)
    func formula(withName name: String) -> AnyObject?
    @objc(namesFromListOutput:)
    func names(fromListOutput output: String?) -> [String]?
}

@objc public protocol BPHomebrewInterfaceObjCBridge: NSObjectProtocol {
    var brewTransport: Int { get set }
    @objc(runBrewExportToolWithPath:)
    func runBrewExportTool(withPath path: String) -> NSError?
    @objc(runBrewImportToolWithPath:progress:withReturnsBlock:)
    func runBrewImportTool(withPath path: String, progress: Progress, withReturnsBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(previewAutoremoveWithProgress:)
    func previewAutoremove(withProgress progress: Progress) -> BPAutoremovePreview?
    @objc(removeUnusedFormulae:progress:output:)
    func removeUnusedFormulae(_ names: [String], progress: Progress, output: @escaping @Sendable (String) -> Void) -> Bool
    @objc(runDoctorWithReturnBlock:)
    func runDoctor(withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(updateWithReturnBlock:)
    func update(withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(dependantsForFormulaName:onlyInstalled:)
    func dependants(forFormulaName name: String, onlyInstalled: Bool) -> String?
    @objc(listServices)
    func listServices() -> [BPService]?
    @objc(serviceDetailsForName:)
    func serviceDetails(forName name: String?) -> BPServiceDetails?
    @objc(startService:withReturnBlock:)
    func startService(_ name: String?, withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(stopService:withReturnBlock:)
    func stopService(_ name: String?, withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(restartService:withReturnBlock:)
    func restartService(_ name: String?, withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(installCask:withReturnBlock:)
    func installCask(_ name: String?, withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(installFormula:withOptions:andReturnBlock:)
    func installFormula(_ name: String?, withOptions options: [Any]?, andReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(uninstallCask:zap:withReturnBlock:)
    func uninstallCask(_ name: String?, zap: Bool, withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(uninstallFormula:withReturnBlock:)
    func uninstallFormula(_ name: String?, withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(upgradeSelectionReporting:progress:withReturnBlock:)
    func upgradeSelectionReporting(_ formulae: [Any], progress: Progress?, withReturnBlock block: @escaping @Sendable (String) -> Void) -> BPUpgradeResult?
    @objc(tapRepository:withReturnsBlock:)
    func tapRepository(_ name: String?, withReturnsBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(untapRepository:withReturnsBlock:)
    func untapRepository(_ name: String?, withReturnsBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(runCleanupWithReturnBlock:)
    func runCleanup(withReturnBlock block: @escaping @Sendable (String) -> Void) -> Bool
    @objc(cancelCurrentOperation)
    func cancelCurrentOperation()
}

@objc public protocol BPHomebrewInterfaceClassObjCBridge: NSObjectProtocol {
    @objc(sharedInterface)
    func sharedInterface() -> AnyObject?
}

@objc public protocol BPHomebrewManagerObjCBridge: NSObjectProtocol {
    var installedFormulae: [Any]? { get }
    var outdatedFormulae: [Any]? { get }
    var allFormulae: [Any]? { get }
    var leavesFormulae: [Any]? { get }
    var searchFormulae: [Any]? { get }
    var repositoriesFormulae: [Any]? { get }
    var pinnedFormulae: [Any]? { get }
    var installedCasks: [Any]? { get }
    var outdatedCasks: [Any]? { get }
    var allCasks: [Any]? { get }
    var currentReloadGeneration: UInt { get }
    var updatesSnapshot: BPUpdatesSnapshot? { get }
    @objc(statusForFormula:)
    func status(forFormula formula: AnyObject) -> Int
    @objc(isFormulaPinned:)
    func isFormulaPinned(_ formula: AnyObject) -> Bool
    @objc(refreshFormulaStateAfterRemovalWithCompletion:)
    func refreshFormulaStateAfterRemoval(withCompletion completion: @escaping @Sendable (Bool) -> Void)
    @objc(reloadFromInterfaceRebuildingCache:)
    func reloadFromInterface(rebuildingCache: Bool)
    @objc(cleanUp)
    func cleanUp()
}

@objc public protocol BPHomebrewManagerClassObjCBridge: NSObjectProtocol {
    @objc(sharedManager)
    func sharedManager() -> AnyObject?
}

@inline(__always)
public func bpAsFormula(_ object: Any?) -> BPFormulaObjCBridge? {
    guard let obj = object as AnyObject?,
          let formulaClass = NSClassFromString("BPFormula"),
          obj.isKind(of: formulaClass) else {
        return nil
    }
    return unsafeBitCast(obj, to: BPFormulaObjCBridge.self)
}

@inline(__always)
public func bpFormulaClass() -> BPFormulaClassObjCBridge? {
    guard let formulaClass = NSClassFromString("BPFormula") else { return nil }
    return unsafeBitCast(formulaClass as AnyObject, to: BPFormulaClassObjCBridge.self)
}

@inline(__always)
public func bpAsHomebrewInterface(_ object: Any?) -> BPHomebrewInterfaceObjCBridge? {
    guard let obj = object as AnyObject? else { return nil }
    return unsafeBitCast(obj, to: BPHomebrewInterfaceObjCBridge.self)
}

@inline(__always)
public func bpSharedHomebrewInterface() -> BPHomebrewInterfaceObjCBridge? {
    guard let cls = NSClassFromString("BPHomebrewInterface") else { return nil }
    let classBridge = unsafeBitCast(cls as AnyObject, to: BPHomebrewInterfaceClassObjCBridge.self)
    return bpAsHomebrewInterface(classBridge.sharedInterface())
}

@inline(__always)
public func bpAsHomebrewManager(_ object: Any?) -> BPHomebrewManagerObjCBridge? {
    guard let obj = object as AnyObject? else { return nil }
    return unsafeBitCast(obj, to: BPHomebrewManagerObjCBridge.self)
}

@inline(__always)
public func bpSharedHomebrewManager() -> BPHomebrewManagerObjCBridge? {
    guard let cls = NSClassFromString("BPHomebrewManager") else { return nil }
    let classBridge = unsafeBitCast(cls as AnyObject, to: BPHomebrewManagerClassObjCBridge.self)
    return bpAsHomebrewManager(classBridge.sharedManager())
}

// MARK: - Migrated Operations, Snapshot, Upgrade Plan & Table Action Policy (Swift 6)

@objc(BPBrewfileExportOperation)
public final class BPBrewfileExportOperation: NSObject, @unchecked Sendable {
    @objc public private(set) var running: Bool = false
    @objc public func isRunning() -> Bool { running }

    private let url: URL?
    private let interfaceObject: AnyObject?
    private var started: Bool = false

    @objc(exportURLForSaveResponse:URL:)
    public static func exportURL(forSaveResponse response: Int, url: URL?) -> URL? {
        guard response == 1, let url, url.isFileURL else { return nil }
        return url
    }

    @objc(initWithURL:interface:)
    public init(url: URL?, interface: Any?) {
        self.url = url
        self.interfaceObject = interface as AnyObject?
        super.init()
    }

    @objc(startWithCompletion:)
    public func start(withCompletion completion: (@Sendable (NSError?) -> Void)?) {
        precondition(Thread.isMainThread, "Export starts on the main thread")
        guard !started else { return }
        started = true
        running = true
        let path = url?.path ?? ""
        nonisolated(unsafe) let iface = interfaceObject
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = bpAsHomebrewInterface(iface)?.runBrewExportTool(withPath: path)
            DispatchQueue.main.async {
                self?.running = false
                completion?(error)
            }
        }
    }
}
