import CryptoKit
import Darwin
import Foundation

public enum BPFormulaInformationMode: Int, Hashable, Sendable {
    case general = 0
    case installedDependents = 1
    case allDependents = 2

    public init(rawInfoType: Int) {
        self = BPFormulaInformationMode(rawValue: rawInfoType) ?? .general
    }
}

/// Values crossing the Objective-C model / Swift UI boundary never retain BPFormula.
public struct BPFormulaInformationIdentity: Hashable, Sendable {
    public let name: String
    public let cask: Bool
    public let mode: BPFormulaInformationMode

    public init(name: String, cask: Bool, mode: BPFormulaInformationMode = .general) {
        self.name = name
        self.cask = cask
        self.mode = mode
    }
}

public struct BPFormulaInformationRequest: Equatable, Sendable {
    public let identity: BPFormulaInformationIdentity
    public let generation: UInt64

    public init(identity: BPFormulaInformationIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }
}

public struct BPFormulaInformationState: Sendable {
    public private(set) var request: BPFormulaInformationRequest?
    public private(set) var information: String?
    public private(set) var website: URL?
    public private(set) var isLoading = false
    private var generation: UInt64 = 0

    public init() {}

    public mutating func begin(name: String, cask: Bool, mode: BPFormulaInformationMode = .general) -> BPFormulaInformationRequest {
        generation += 1
        let next = BPFormulaInformationRequest(
            identity: BPFormulaInformationIdentity(name: name, cask: cask, mode: mode), generation: generation)
        request = next
        information = nil
        website = nil
        isLoading = true
        return next
    }

    @discardableResult
    public mutating func receive(request: BPFormulaInformationRequest, information: String?, website: URL?) -> Bool {
        guard self.request == request else { return false }
        self.information = information.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.website = website
        isLoading = false
        return true
    }

    public mutating func close() {
        request = nil
        information = nil
        website = nil
        isLoading = false
    }
}

public struct BPSelectedFormulaSnapshot: Equatable, Sendable {
    public let identity: BPFormulaInformationIdentity
    public let isInstalled: Bool
    public let isPinned: Bool
    public let installPath: String?
    public let latestVersion: String?
    public let dependencies: String?
    public let conflicts: String?
    public let shortDescription: String?

    public init(name: String,
                cask: Bool,
                isInstalled: Bool,
                isPinned: Bool,
                installPath: String?,
                latestVersion: String?,
                dependencies: String?,
                conflicts: String?,
                shortDescription: String?) {
        self.identity = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        self.isInstalled = isInstalled
        self.isPinned = isPinned && !cask
        self.installPath = installPath.flatMap { $0.isEmpty ? nil : $0 }
        self.latestVersion = latestVersion.flatMap { $0.isEmpty ? nil : $0 }
        self.dependencies = dependencies.flatMap { $0.isEmpty ? nil : $0 }
        self.conflicts = conflicts.flatMap { $0.isEmpty ? nil : $0 }
        self.shortDescription = shortDescription.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var dependencyNames: [String] {
        guard let dependencies else { return [] }
        return dependencies
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var conflictNames: [String] {
        guard let conflicts else { return [] }
        return conflicts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct BPSelectedFormulaState: Sendable {
    public enum Selection: Equatable, Sendable {
        case none
        case single(BPSelectedFormulaSnapshot)
        case multiple
    }

    public private(set) var selection: Selection = .none
    public private(set) var request: BPFormulaInformationRequest?
    public private(set) var dependents: [String]?
    private var generation: UInt64 = 0

    public init() {}

    public var currentSnapshot: BPSelectedFormulaSnapshot? {
        if case .single(let snapshot) = selection {
            return snapshot
        }
        return nil
    }

    public var showsPinnedRow: Bool {
        guard case .single(let snapshot) = selection else { return false }
        return snapshot.isPinned && !snapshot.identity.cask
    }

    public mutating func clear() {
        generation += 1
        selection = .none
        request = nil
        dependents = nil
    }

    public mutating func selectMultiple() {
        generation += 1
        selection = .multiple
        request = nil
        dependents = nil
    }

    @discardableResult
    public mutating func beginSingle(_ snapshot: BPSelectedFormulaSnapshot) -> BPFormulaInformationRequest {
        generation += 1
        let next = BPFormulaInformationRequest(identity: snapshot.identity, generation: generation)
        selection = .single(snapshot)
        request = next
        dependents = nil
        return next
    }

    @discardableResult
    public mutating func updateSingle(_ snapshot: BPSelectedFormulaSnapshot) -> Bool {
        guard case .single(let current) = selection,
              current.identity == snapshot.identity else {
            return false
        }
        selection = .single(snapshot)
        return true
    }

    @discardableResult
    public mutating func receiveDependents(_ names: [String], for request: BPFormulaInformationRequest) -> Bool {
        guard self.request == request,
              case .single(let current) = selection,
              !current.identity.cask else {
            return false
        }
        dependents = names
        return true
    }
}

public enum BPInstalledPackageSortColumn: String, Equatable, Sendable {
    case name = "Name"
    case version = "Version"
    case latestVersion = "LatestVersion"
    case status = "Status"
}

public enum BPPackageListMode: Int, Sendable, Equatable {
    case installedFormulae = 0
    case outdatedFormulae = 1
    case allFormulae = 2
    case leaves = 3
    case pinned = 4
    case search = 5
    case installedCasks = 6
    case outdatedCasks = 7
    case allCasks = 8
    case repositories = 9

    public init(rawMode: Int) {
        self = BPPackageListMode(rawValue: rawMode) ?? .installedFormulae
    }

    public init(objcListMode: Int) {
        switch objcListMode {
        case 0: self = .allFormulae
        case 1: self = .installedFormulae
        case 2: self = .leaves
        case 3: self = .outdatedFormulae
        case 4: self = .search
        case 5: self = .repositories
        case 6: self = .pinned
        case 7: self = .installedCasks
        case 8: self = .outdatedCasks
        case 9: self = .allCasks
        default: self = .installedFormulae
        }
    }

    public var showsVersionColumn: Bool {
        self != .repositories
    }

    public var showsInstalledVersionColumn: Bool {
        switch self {
        case .installedFormulae, .installedCasks, .pinned, .outdatedFormulae, .outdatedCasks:
            return true
        case .allFormulae, .allCasks, .leaves, .search, .repositories:
            return false
        }
    }

    public var showsLatestVersionColumn: Bool {
        self == .outdatedFormulae || self == .outdatedCasks
    }

    public var showsStatusColumn: Bool {
        self == .allFormulae || self == .allCasks || self == .search
    }

    public var isCaskMode: Bool {
        self == .installedCasks || self == .outdatedCasks || self == .allCasks
    }

    public var allowsMultipleSelection: Bool {
        self == .outdatedFormulae || self == .outdatedCasks
    }
}

public struct BPInstalledPackageRow: Identifiable, Equatable, Sendable {
    public let identity: BPFormulaInformationIdentity
    public let version: String
    public let latestVersion: String
    public let statusRank: Int
    public let isPinned: Bool
    public let lowercasedName: String

    public var id: BPFormulaInformationIdentity { identity }
    public var name: String { identity.name }
    public var cask: Bool { identity.cask }

    public init(name: String,
                cask: Bool,
                version: String?,
                latestVersion: String?,
                statusRank: Int,
                isPinned: Bool) {
        self.identity = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        self.version = version ?? ""
        self.latestVersion = latestVersion ?? ""
        self.statusRank = statusRank
        self.isPinned = isPinned && !cask
        self.lowercasedName = name.lowercased()
    }
}

public struct BPInstalledPackageListState: Sendable {
    public private(set) var sourceRows: [BPInstalledPackageRow] = []
    public private(set) var displayedRows: [BPInstalledPackageRow] = []
    private var rowIndexByID: [BPFormulaInformationIdentity: Int] = [:]
    public private(set) var selectedID: BPFormulaInformationIdentity?
    public private(set) var selectedIDs: Set<BPFormulaInformationIdentity> = []
    public private(set) var isCaskList = false
    public private(set) var mode: BPPackageListMode = .installedFormulae
    public private(set) var sortColumn: BPInstalledPackageSortColumn?
    public private(set) var sortAscending = true

    public init() {}

    public var selectedRow: BPInstalledPackageRow? {
        guard let selectedID,
              let index = rowIndexByID[selectedID],
              index >= 0,
              index < displayedRows.count else {
            return nil
        }
        return displayedRows[index]
    }

    public var selectedRows: [BPInstalledPackageRow] {
        guard !selectedIDs.isEmpty else { return [] }
        return displayedRows.filter { selectedIDs.contains($0.id) }
    }

    public var selectedRowIndex: Int {
        guard let selectedID,
              let index = rowIndexByID[selectedID] else {
            return -1
        }
        return index
    }

    public var selectedRowIndexes: IndexSet {
        var result = IndexSet()
        for id in selectedIDs {
            if let index = rowIndexByID[id] {
                result.insert(index)
            }
        }
        return result
    }

    public mutating func setMode(_ mode: BPPackageListMode) {
        self.mode = mode
        self.isCaskList = mode.isCaskMode
        pruneSelectionAfterReload()
    }

    public mutating func replaceRows(_ rows: [BPInstalledPackageRow], isCaskList: Bool) {
        self.sourceRows = rows
        self.isCaskList = isCaskList
        if isCaskList && !self.mode.isCaskMode {
            self.mode = .installedCasks
        } else if !isCaskList && self.mode.isCaskMode {
            self.mode = .installedFormulae
        }
        rebuildDisplayedRows()
        pruneSelectionAfterReload()
    }

    public mutating func replaceRows(_ rows: [BPInstalledPackageRow], mode: BPPackageListMode) {
        self.mode = mode
        self.isCaskList = mode.isCaskMode
        self.sourceRows = rows
        rebuildDisplayedRows()
        pruneSelectionAfterReload()
    }

    private mutating func pruneSelectionAfterReload() {
        selectedIDs = selectedIDs.filter { rowIndexByID[$0] != nil }
        if !mode.allowsMultipleSelection && selectedIDs.count > 1 {
            if let first = displayedRows.first(where: { selectedIDs.contains($0.id) })?.id {
                selectedIDs = [first]
            } else {
                selectedIDs = []
            }
        }
        syncPrimarySelectionFromSet()
    }

    private mutating func syncPrimarySelectionFromSet() {
        if selectedIDs.isEmpty {
            selectedID = nil
        } else if selectedIDs.count == 1 {
            selectedID = selectedIDs.first
        } else if let current = selectedID, selectedIDs.contains(current), rowIndexByID[current] != nil {
            // Keep existing primary selection if still part of the set
        } else {
            selectedID = displayedRows.first(where: { selectedIDs.contains($0.id) })?.id
        }
    }

    public mutating func setSort(column: BPInstalledPackageSortColumn?, ascending: Bool) {
        self.sortColumn = column
        self.sortAscending = ascending
        rebuildDisplayedRows()
        syncPrimarySelectionFromSet()
    }

    public mutating func select(id: BPFormulaInformationIdentity?) {
        guard let id, rowIndexByID[id] != nil else {
            selectedID = nil
            selectedIDs = []
            return
        }
        selectedID = id
        selectedIDs = [id]
    }

    public mutating func select(ids: Set<BPFormulaInformationIdentity>) {
        let valid = ids.filter { rowIndexByID[$0] != nil }
        if !mode.allowsMultipleSelection && valid.count > 1 {
            if let first = displayedRows.first(where: { valid.contains($0.id) })?.id {
                selectedIDs = [first]
            } else {
                selectedIDs = []
            }
        } else {
            selectedIDs = valid
        }
        syncPrimarySelectionFromSet()
    }

    @discardableResult
    public mutating func select(name: String, cask: Bool) -> Bool {
        let candidate = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        guard rowIndexByID[candidate] != nil else {
            selectedID = nil
            selectedIDs = []
            return false
        }
        selectedID = candidate
        selectedIDs = [candidate]
        return true
    }

    @discardableResult
    public mutating func selectRow(at index: Int) -> Bool {
        guard index >= 0 && index < displayedRows.count else {
            selectedID = nil
            selectedIDs = []
            return false
        }
        let id = displayedRows[index].id
        selectedID = id
        selectedIDs = [id]
        return true
    }

    @discardableResult
    public mutating func selectRows(at indexes: IndexSet) -> Bool {
        var ids = Set<BPFormulaInformationIdentity>()
        for index in indexes where index >= 0 && index < displayedRows.count {
            ids.insert(displayedRows[index].id)
        }
        select(ids: ids)
        return !selectedIDs.isEmpty
    }

    public func index(ofName name: String, cask: Bool) -> Int {
        guard !name.isEmpty else { return -1 }
        let target = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        return rowIndexByID[target] ?? -1
    }

    private mutating func rebuildDisplayedRows() {
        if let sortColumn {
            let indexed = Array(sourceRows.enumerated())
            let sorted = indexed.sorted { lhs, rhs in
                let comparison = Self.compare(lhs.element, rhs.element, by: sortColumn)
                if comparison == .orderedSame {
                    return lhs.offset < rhs.offset
                }
                if sortAscending {
                    return comparison == .orderedAscending
                }
                return comparison == .orderedDescending
            }
            displayedRows = sorted.map(\.element)
        } else {
            displayedRows = sourceRows
        }
        var lookup: [BPFormulaInformationIdentity: Int] = [:]
        lookup.reserveCapacity(displayedRows.count)
        for (index, row) in displayedRows.enumerated() where lookup[row.id] == nil {
            lookup[row.id] = index
        }
        rowIndexByID = lookup
    }

    public static func compare(_ lhs: BPInstalledPackageRow,
                               _ rhs: BPInstalledPackageRow,
                               by column: BPInstalledPackageSortColumn) -> ComparisonResult {
        switch column {
        case .name:
            if lhs.lowercasedName == rhs.lowercasedName {
                return .orderedSame
            }
            return lhs.lowercasedName < rhs.lowercasedName ? .orderedAscending : .orderedDescending
        case .status:
            if lhs.statusRank == rhs.statusRank { return .orderedSame }
            return lhs.statusRank < rhs.statusRank ? .orderedAscending : .orderedDescending
        case .version, .latestVersion:
            let leftValue = (column == .latestVersion) ? lhs.latestVersion : lhs.version
            let rightValue = (column == .latestVersion) ? rhs.latestVersion : rhs.version
            if leftValue.isEmpty && rightValue.isEmpty { return .orderedSame }
            if leftValue.isEmpty { return .orderedAscending }
            if rightValue.isEmpty { return .orderedDescending }
            return leftValue.localizedStandardCompare(rightValue)
        }
    }
}

public struct BPUnifiedUpdateRow: Equatable, Hashable, Identifiable, Sendable {
    public let id: BPFormulaInformationIdentity
    public let version: String
    public let latestVersion: String
    public let isPinned: Bool

    public var name: String { id.name }
    public var cask: Bool { id.cask }
    public var isEligible: Bool { !isPinned }

    public init(name: String,
                cask: Bool,
                version: String?,
                latestVersion: String?,
                isPinned: Bool = false) {
        self.id = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        self.version = version ?? ""
        self.latestVersion = latestVersion ?? ""
        self.isPinned = isPinned
    }
}

public struct BPUnifiedUpdatesState: Equatable, Sendable {
    public private(set) var formulaRows: [BPUnifiedUpdateRow] = []
    public private(set) var caskRows: [BPUnifiedUpdateRow] = []
    public private(set) var selectedIDs: Set<BPFormulaInformationIdentity> = []
    public private(set) var filterQuery: String = ""

    public init(formulaRows: [BPUnifiedUpdateRow] = [],
                caskRows: [BPUnifiedUpdateRow] = [],
                selectedIDs: Set<BPFormulaInformationIdentity> = [],
                filterQuery: String = "") {
        self.formulaRows = formulaRows.filter { !$0.cask }
        self.caskRows = caskRows.filter { $0.cask }
        let validEligibleIDs = Self.eligibleIDSet(formulaRows: self.formulaRows, caskRows: self.caskRows)
        self.selectedIDs = selectedIDs.intersection(validEligibleIDs)
        self.filterQuery = filterQuery
    }

    public var filteredFormulaRows: [BPUnifiedUpdateRow] {
        let trimmed = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return formulaRows }
        return formulaRows.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    public var filteredCaskRows: [BPUnifiedUpdateRow] {
        let trimmed = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return caskRows }
        return caskRows.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    public var hasFormulaUpdates: Bool {
        !formulaRows.isEmpty
    }

    public var hasCaskUpdates: Bool {
        !caskRows.isEmpty
    }

    public var isEmpty: Bool {
        formulaRows.isEmpty && caskRows.isEmpty
    }

    public var eligibleRowIDs: Set<BPFormulaInformationIdentity> {
        Self.eligibleIDSet(formulaRows: formulaRows, caskRows: caskRows)
    }

    public var selectedFormulaNames: [String] {
        formulaRows
            .filter { !$0.cask && $0.isEligible && selectedIDs.contains($0.id) }
            .map(\.name)
    }

    public var selectedCaskNames: [String] {
        caskRows
            .filter { $0.cask && $0.isEligible && selectedIDs.contains($0.id) }
            .map(\.name)
    }

    public mutating func setFilterQuery(_ query: String) {
        self.filterQuery = query
    }

    public mutating func replace(formulaRows: [BPUnifiedUpdateRow], caskRows: [BPUnifiedUpdateRow]) {
        self.formulaRows = formulaRows.filter { !$0.cask }
        self.caskRows = caskRows.filter { $0.cask }
        let validEligibleIDs = Self.eligibleIDSet(formulaRows: self.formulaRows, caskRows: self.caskRows)
        self.selectedIDs = self.selectedIDs.intersection(validEligibleIDs)
    }

    public mutating func selectAllEligible() {
        selectedIDs = Self.eligibleIDSet(formulaRows: formulaRows, caskRows: caskRows)
    }

    public mutating func selectEligibleFormulae() {
        selectedIDs = Set(formulaRows.filter { !$0.cask && $0.isEligible }.map(\.id))
    }

    public mutating func selectEligibleCasks() {
        selectedIDs = Set(caskRows.filter { $0.cask && $0.isEligible }.map(\.id))
    }

    public mutating func clearSelection() {
        selectedIDs.removeAll()
    }

    @discardableResult
    public mutating func toggleSelection(for id: BPFormulaInformationIdentity) -> Bool {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            return false
        }
        let validEligibleIDs = Self.eligibleIDSet(formulaRows: formulaRows, caskRows: caskRows)
        guard validEligibleIDs.contains(id) else {
            return false
        }
        selectedIDs.insert(id)
        return true
    }

    private static func eligibleIDSet(formulaRows: [BPUnifiedUpdateRow],
                                      caskRows: [BPUnifiedUpdateRow]) -> Set<BPFormulaInformationIdentity> {
        let formulaIDs = formulaRows.filter { !$0.cask && $0.isEligible }.map(\.id)
        let caskIDs = caskRows.filter { $0.cask && $0.isEligible }.map(\.id)
        return Set(formulaIDs).union(caskIDs)
    }
}

