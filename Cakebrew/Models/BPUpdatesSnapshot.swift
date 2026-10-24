import CryptoKit
import Darwin
import Foundation

@objc(BPUpdateItem)
public final class BPUpdateItem: NSObject, Sendable {
    @objc public let name: String
    @objc public let version: String
    @objc public let latestVersion: String
    @objc public let cask: Bool

    @objc public init(name: String, version: String, latestVersion: String, cask: Bool) {
        self.name = name
        self.version = version
        self.latestVersion = latestVersion
        self.cask = cask
        super.init()
    }

    @objc(itemsFromFormulae:cask:)
    public static func items(fromFormulae formulae: [Any], cask: Bool) -> [BPUpdateItem] {
        var items: [BPUpdateItem] = []
        items.reserveCapacity(formulae.count)
        for element in formulae {
            guard let formula = bpAsFormula(element) else { continue }
            items.append(BPUpdateItem(
                name: formula.name ?? "",
                version: formula.version ?? "",
                latestVersion: formula.latestVersion ?? "",
                cask: cask
            ))
        }
        return items
    }
}

@objc(BPUpdatesSnapshot)
public final class BPUpdatesSnapshot: NSObject, Sendable {
    @objc public let generation: UInt
    @objc public let formulae: [BPUpdateItem]
    @objc public let casks: [BPUpdateItem]
    @objc public let pinnedFormulaNames: [String]
    @objc public let pinnedCaskNames: [String]
    @objc public let eligibleFormulae: [String]
    @objc public let eligibleCasks: [String]
    @objc public let excludedFormulae: [String]
    @objc public let excludedCasks: [String]

    @objc(initWithGeneration:formulaItems:caskItems:pinnedFormulaNames:pinnedCaskNames:)
    public init?(
        generation: UInt,
        formulaItems: [BPUpdateItem]?,
        caskItems: [BPUpdateItem]?,
        pinnedFormulaNames: [String]?,
        pinnedCaskNames: [String]?
    ) {
        guard let formulaItems, let caskItems, let pinnedFormulaNames, let pinnedCaskNames else {
            return nil
        }
        var eligFormulae: [String] = []
        var eligCasks: [String] = []
        var exclFormulae: [String] = []
        var exclCasks: [String] = []

        for isCask in [false, true] {
            let pins = isCask ? pinnedCaskNames : pinnedFormulaNames
            let tokens = Set(pins.map { ($0 as NSString).lastPathComponent })
            var seen = Set<String>()
            for item in (isCask ? caskItems : formulaItems) {
                let name = item.name
                if name.isEmpty || name != name.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return nil
                }
                if seen.contains(name) { continue }
                seen.insert(name)
                let pinned = tokens.contains((name as NSString).lastPathComponent)
                if isCask {
                    if pinned { exclCasks.append(name) } else { eligCasks.append(name) }
                } else {
                    if pinned { exclFormulae.append(name) } else { eligFormulae.append(name) }
                }
            }
        }

        self.generation = generation
        self.formulae = formulaItems
        self.casks = caskItems
        self.pinnedFormulaNames = pinnedFormulaNames
        self.pinnedCaskNames = pinnedCaskNames
        self.eligibleFormulae = eligFormulae
        self.eligibleCasks = eligCasks
        self.excludedFormulae = exclFormulae
        self.excludedCasks = exclCasks
        super.init()
    }

    @objc(initWithGeneration:formulae:casks:pinnedFormulae:pinnedCasks:)
    public convenience init?(
        generation: UInt,
        formulae: [Any]?,
        casks: [Any]?,
        pinnedFormulae: [Any]?,
        pinnedCasks: [Any]?
    ) {
        let fItems = formulae.map { BPUpdateItem.items(fromFormulae: $0, cask: false) }
        let cItems = casks.map { BPUpdateItem.items(fromFormulae: $0, cask: true) }
        let fPins = pinnedFormulae?.compactMap { bpAsFormula($0)?.name }
        let cPins = pinnedCasks?.compactMap { bpAsFormula($0)?.name }
        self.init(
            generation: generation,
            formulaItems: fItems,
            caskItems: cItems,
            pinnedFormulaNames: fPins,
            pinnedCaskNames: cPins
        )
    }

    @objc public var hasEligibleUpdates: Bool {
        eligibleFormulae.count + eligibleCasks.count > 0
    }

    @objc public func eligibleSelection() -> [Any] {
        guard let formulaCls = bpFormulaClass() else { return [] }
        var selection: [Any] = []
        var seen = Set<String>()
        let eligFormulaSet = Set(eligibleFormulae)
        let eligCaskSet = Set(eligibleCasks)
        for item in formulae + casks {
            let identity = "\(item.cask ? 1 : 0):\(item.name)"
            if seen.contains(identity) { continue }
            seen.insert(identity)
            if item.cask {
                if !eligCaskSet.contains(item.name) { continue }
            } else {
                if !eligFormulaSet.contains(item.name) { continue }
            }
            if let obj = formulaCls.formula(withName: item.name, version: item.version, andLatestVersion: item.latestVersion),
               let formula = bpAsFormula(obj) {
                formula.cask = item.cask
                selection.append(obj)
            }
        }
        return selection
    }
}
