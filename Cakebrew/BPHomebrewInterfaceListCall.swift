import CryptoKit
import Darwin
import Foundation

// MARK: - BPHomebrewInterface, BPMockHomebrewInterface, BPHomebrewManager & Test Subclasses

@objc(BPFormulaStatus)
public enum BPFormulaStatus: Int, Sendable {
    @objc(kBPFormulaNotInstalled) case notInstalled = 0
    @objc(kBPFormulaInstalled) case installed = 1
    @objc(kBPFormulaOutdated) case outdated = 2
}

@objc(BPHomebrewInterfaceDelegate)
public protocol BPHomebrewInterfaceDelegate: NSObjectProtocol {
    @objc(homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs:)
    func homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs(_ shouldRebuildCatalogs: Bool)

    @objc(homebrewInterfaceShouldDisplayNoBrewMessage:)
    func homebrewInterfaceShouldDisplayNoBrewMessage(_ yesOrNo: Bool)
}

@objc internal protocol BPHelperClientClassBridge: NSObjectProtocol {
    @objc(sharedClient)
    func sharedClient() -> AnyObject?
}

@objc internal protocol BPHelperClientInstanceBridge: NSObjectProtocol {
    @objc(cancelCurrentCommand)
    func cancelCurrentCommand()

    @objc(runBrewWithArguments:outputMarker:outputBlock:)
    func runBrew(
        withArguments arguments: [Any],
        outputMarker marker: String?,
        outputBlock block: (@Sendable (String) -> Void)?
    ) -> Bool
}

@inline(__always)
internal func bpSharedHelperClient() -> BPHelperClientInstanceBridge? {
    guard let cls = NSClassFromString("BPHelperClient") else { return nil }
    let classBridge = unsafeBitCast(cls as AnyObject, to: BPHelperClientClassBridge.self)
    guard let obj = classBridge.sharedClient() else { return nil }
    return unsafeBitCast(obj, to: BPHelperClientInstanceBridge.self)
}

@objc(BPHomebrewInterfaceListCall)
open class BPHomebrewInterfaceListCall: NSObject, @unchecked Sendable {
    private var _argumentsStorage: NSArray?

    @objc public var arguments: [Any] {
        (_argumentsStorage as? [Any]) ?? []
    }

    @objc(initWithArguments:)
    public init(arguments: [Any]?) {
        self._argumentsStorage = (arguments as NSArray?)?.copy() as? NSArray
        super.init()
    }

    public override convenience init() {
        self.init(arguments: [])
    }

    @objc(parseData:)
    open func parseData(_ data: String?) -> [BPFormula] {
        guard let data else { return [] }
        var dataLines = data.components(separatedBy: "\n")
        if !dataLines.isEmpty {
            dataLines.removeLast()
        }
        var formulae: [BPFormula] = []
        formulae.reserveCapacity(dataLines.count)
        for item in dataLines {
            if let formula = parseFormulaItem(item) {
                formulae.append(formula)
            }
        }
        return formulae
    }

    @objc(parseFormulaItem:)
    open func parseFormulaItem(_ item: String) -> BPFormula? {
        BPFormula.formula(withName: item)
    }
}

@objc(BPHomebrewInterfaceListCallInstalled)
open class BPHomebrewInterfaceListCallInstalled: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["list", "--versions"])
    }

    public override init(arguments: [Any]?) {
        super.init(arguments: arguments)
    }

    open override func parseFormulaItem(_ item: String) -> BPFormula? {
        let aux = item.components(separatedBy: " ")
        return BPFormula.formula(withName: aux.first, andVersion: aux.last)
    }
}

@objc(BPHomebrewInterfaceListCallAll)
open class BPHomebrewInterfaceListCallAll: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["formulae"])
    }
}

@objc(BPHomebrewInterfaceListCallLeaves)
open class BPHomebrewInterfaceListCallLeaves: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["leaves"])
    }
}

@objc(BPHomebrewInterfaceListCallUpgradeable)
open class BPHomebrewInterfaceListCallUpgradeable: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["outdated", "--formula", "--verbose"])
    }

    public override init(arguments: [Any]?) {
        super.init(arguments: arguments)
    }

    open override func parseFormulaItem(_ item: String) -> BPFormula? {
        let regexString = "(\\S+)\\s\\(((.*, )*(.*))\\) (?:<|!=) (\\S+)"
        var formula: BPFormula?
        if let regex = try? NSRegularExpression(pattern: regexString, options: .caseInsensitive) {
            let nsItem = item as NSString
            regex.enumerateMatches(in: item, options: [], range: NSRange(location: 0, length: nsItem.length)) { result, _, _ in
                guard let result, result.resultType == .regularExpression, result.numberOfRanges >= 4 else { return }
                let formulaName = nsItem.substring(with: result.range(at: 1))
                let installedVersion = nsItem.substring(with: result.range(at: result.numberOfRanges - 2))
                let latestVersion = nsItem.substring(with: result.range(at: result.numberOfRanges - 1))
                formula = BPFormula.formula(withName: formulaName, version: installedVersion, andLatestVersion: latestVersion)
            }
        }
        return formula ?? BPFormula.formula(withName: item)
    }
}

@objc(BPHomebrewInterfaceListCallRepositories)
open class BPHomebrewInterfaceListCallRepositories: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["tap"])
    }
}

@objc(BPHomebrewInterfaceListCallPinned)
open class BPHomebrewInterfaceListCallPinned: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["list", "--formula", "--pinned"])
    }
}

@objc(BPHomebrewInterfaceListCallPinnedCasks)
open class BPHomebrewInterfaceListCallPinnedCasks: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["list", "--cask", "--pinned"])
    }

    open override func parseFormulaItem(_ item: String) -> BPFormula? {
        let formula = super.parseFormulaItem(item)
        formula?.cask = true
        return formula
    }
}

@objc(BPHomebrewInterfaceListCallInstalledCasks)
open class BPHomebrewInterfaceListCallInstalledCasks: BPHomebrewInterfaceListCallInstalled, @unchecked Sendable {
    @objc public override init() {
        super.init(arguments: ["list", "--cask", "--versions"])
    }

    open override func parseFormulaItem(_ item: String) -> BPFormula? {
        let cask = super.parseFormulaItem(item)
        cask?.cask = true
        return cask
    }
}

@objc(BPHomebrewInterfaceListCallOutdatedCasks)
open class BPHomebrewInterfaceListCallOutdatedCasks: BPHomebrewInterfaceListCallUpgradeable, @unchecked Sendable {
    @objc public override init() {
        var arguments = ["outdated", "--cask", "--verbose"]
        if BPPreferences.greedyCaskUpgrades {
            arguments.append("--greedy")
        }
        super.init(arguments: arguments)
    }

    open override func parseFormulaItem(_ item: String) -> BPFormula? {
        let cask = super.parseFormulaItem(item)
        cask?.cask = true
        return cask
    }
}

@objc(BPHomebrewInterfaceListCallAllCasks)
open class BPHomebrewInterfaceListCallAllCasks: BPHomebrewInterfaceListCall, @unchecked Sendable {
    @objc public init() {
        super.init(arguments: ["casks"])
    }

    open override func parseFormulaItem(_ item: String) -> BPFormula? {
        let cask = super.parseFormulaItem(item)
        cask?.cask = true
        return cask
    }
}
