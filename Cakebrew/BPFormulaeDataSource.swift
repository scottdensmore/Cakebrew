import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@objc(BPFormulaeDataSource)
public final class BPFormulaeDataSource: NSObject, NSTableViewDataSource {
    private static let columnIdentifierName = "Name"
    private static let columnIdentifierVersion = "Version"
    private static let columnIdentifierLatestVersion = "LatestVersion"
    private static let columnIdentifierStatus = "Status"

    @objc public var mode: Int = 0 {
        didSet {
            refreshBackingArray()
        }
    }

    @objc public var sortDescriptors: [NSSortDescriptor]? {
        didSet {
            refreshBackingArray()
        }
    }

    @objc public var formulaeArray: [Any]?

    public convenience override init() {
        self.init(mode: 0)
    }

    @objc(initWithMode:)
    public init(mode aMode: Int) {
        self.mode = aMode
        super.init()
        refreshBackingArray()
    }

    @objc(nameCellValueForFormula:pinned:)
    public static func nameCellValue(forFormula formula: Any?, pinned: Bool) -> Any {
        let name = bpAsFormula(formula)?.name ?? ""
        if !pinned || name.isEmpty {
            return name as NSString
        }

        let value = NSMutableAttributedString(string: name + " ")
        if let pin = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Pinned", comment: "")
        ) {
            let config = NSImage.SymbolConfiguration(pointSize: NSFont.smallSystemFontSize, weight: .regular)
            let attachment = NSTextAttachment()
            attachment.image = pin.withSymbolConfiguration(config) ?? pin
            value.append(NSAttributedString(attachment: attachment))
        }
        return value
    }

    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        self.sortDescriptors = tableView.sortDescriptors
        let descriptor = tableView.sortDescriptors.first
        BPPreferences.sortColumnIdentifier = descriptor?.key
        BPPreferences.sortAscending = descriptor?.ascending ?? true
        tableView.reloadData()
    }

    @objc public func refreshBackingArray() {
        guard let manager = bpSharedHomebrewManager() else {
            formulaeArray = []
            return
        }
        switch mode {
        case 0: // kBPListAll
            formulaeArray = manager.allFormulae
        case 1: // kBPListInstalled
            formulaeArray = manager.installedFormulae
        case 2: // kBPListLeaves
            formulaeArray = manager.leavesFormulae
        case 6: // kBPListPinned
            formulaeArray = manager.pinnedFormulae
        case 7: // kBPListInstalledCasks
            formulaeArray = manager.installedCasks
        case 8: // kBPListOutdatedCasks
            formulaeArray = manager.outdatedCasks
        case 9: // kBPListAllCasks
            formulaeArray = manager.allCasks
        case 3: // kBPListOutdated
            formulaeArray = manager.outdatedFormulae
        case 4: // kBPListSearch
            formulaeArray = manager.searchFormulae
        case 5: // kBPListRepositories
            formulaeArray = manager.repositoriesFormulae
        default:
            break
        }

        if let sortDescriptors, !sortDescriptors.isEmpty {
            formulaeArray = Self.formulae(formulaeArray, sortedBy: sortDescriptors)
        }
    }

    public func numberOfRows(in aTableView: NSTableView) -> Int {
        formulaeArray?.count ?? 0
    }

    @objc(formulaAtIndex:)
    public func formula(at index: Int) -> Any? {
        guard let array = formulaeArray, index >= 0, index < array.count else { return nil }
        return array[index]
    }

    @objc(indexOfFormulaNamed:)
    public func indexOfFormula(named name: String?) -> Int {
        indexOfFormula(named: name, cask: false)
    }

    @objc(indexOfFormulaNamed:cask:)
    public func indexOfFormula(named name: String?, cask: Bool) -> Int {
        guard let name, !name.isEmpty, let array = formulaeArray else { return -1 }
        for (idx, item) in array.enumerated() {
            if let f = bpAsFormula(item), f.cask == cask, f.name == name {
                return idx
            }
        }
        return -1
    }

    private static func compareFormula(_ lhsObj: Any, to rhsObj: Any, forKey key: String) -> ComparisonResult {
        guard let lhs = bpAsFormula(lhsObj), let rhs = bpAsFormula(rhsObj) else {
            return .orderedSame
        }
        if key == columnIdentifierName {
            return ((lhs.name ?? "") as NSString).localizedCaseInsensitiveCompare(rhs.name ?? "")
        }
        if key == columnIdentifierStatus {
            guard let manager = bpSharedHomebrewManager() else { return .orderedSame }
            let left = manager.status(forFormula: lhsObj as AnyObject)
            let right = manager.status(forFormula: rhsObj as AnyObject)
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        }

        let leftValue = (key == columnIdentifierLatestVersion ? lhs.shortLatestVersion : lhs.version) ?? ""
        let rightValue = (key == columnIdentifierLatestVersion ? rhs.shortLatestVersion : rhs.version) ?? ""
        if leftValue.isEmpty && rightValue.isEmpty { return .orderedSame }
        if leftValue.isEmpty { return .orderedAscending }
        if rightValue.isEmpty { return .orderedDescending }
        return (leftValue as NSString).localizedStandardCompare(rightValue)
    }

    @objc(formulae:sortedBy:)
    public static func formulae(_ formulae: [Any]?, sortedBy descriptors: [NSSortDescriptor]?) -> [Any] {
        guard let formulae else { return [] }
        guard let descriptor = descriptors?.first, let key = descriptor.key else {
            return formulae
        }
        let ascending = descriptor.ascending
        let positions = Array(0..<formulae.count)
        let ordered = positions.sorted { l, r in
            let cmp = compareFormula(formulae[l], to: formulae[r], forKey: key)
            if cmp == .orderedSame {
                return l < r
            }
            if ascending {
                return cmp == .orderedAscending
            } else {
                return cmp == .orderedDescending
            }
        }
        return ordered.map { formulae[$0] }
    }

    @objc(formulasAtIndexSet:)
    public func formulas(at indexSet: IndexSet) -> [Any]? {
        guard let array = formulaeArray,
              !indexSet.isEmpty,
              let last = indexSet.last,
              last < array.count else {
            return nil
        }
        return indexSet.map { array[$0] }
    }

    public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let array = formulaeArray, row >= 0, row < array.count else { return "" }
        let columnIdentifier = tableColumn?.identifier.rawValue ?? ""
        let element = array[row]
        if columnIdentifier == Self.columnIdentifierName {
            if let f = bpAsFormula(element) {
                let pinned = bpSharedHomebrewManager()?.isFormulaPinned(element as AnyObject) ?? false
                return Self.nameCellValue(forFormula: f, pinned: pinned)
            }
            return element
        } else if columnIdentifier == Self.columnIdentifierVersion {
            if let f = bpAsFormula(element) {
                return f.version
            }
            return element
        } else if columnIdentifier == Self.columnIdentifierLatestVersion {
            if let f = bpAsFormula(element) {
                return f.shortLatestVersion
            }
            return element
        } else if columnIdentifier == Self.columnIdentifierStatus {
            if bpAsFormula(element) != nil {
                let status = bpSharedHomebrewManager()?.status(forFormula: element as AnyObject) ?? -1
                switch status {
                case 1: // kBPFormulaInstalled
                    return NSLocalizedString("Formula_Status_Installed", comment: "")
                case 0: // kBPFormulaNotInstalled
                    return NSLocalizedString("Formula_Status_Not_Installed", comment: "")
                case 2: // kBPFormulaOutdated
                    return NSLocalizedString("Formula_Status_Outdated", comment: "")
                default:
                    return ""
                }
            }
            return element
        }
        return ""
    }
}
