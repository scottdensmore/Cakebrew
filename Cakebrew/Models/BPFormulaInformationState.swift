import Foundation

enum BPFormulaInformationMode: Int, Hashable, Sendable {
    case general = 0
    case installedDependents = 1
    case allDependents = 2

    init(rawInfoType: Int) {
        self = BPFormulaInformationMode(rawValue: rawInfoType) ?? .general
    }
}

/// Values crossing the Objective-C model / Swift UI boundary never retain BPFormula.
struct BPFormulaInformationIdentity: Hashable, Sendable {
    let name: String
    let cask: Bool
    let mode: BPFormulaInformationMode

    init(name: String, cask: Bool, mode: BPFormulaInformationMode = .general) {
        self.name = name
        self.cask = cask
        self.mode = mode
    }
}

struct BPFormulaInformationRequest: Equatable, Sendable {
    let identity: BPFormulaInformationIdentity
    let generation: UInt64
}

struct BPFormulaInformationState: Sendable {
    private(set) var request: BPFormulaInformationRequest?
    private(set) var information: String?
    private(set) var website: URL?
    private(set) var isLoading = false
    private var generation: UInt64 = 0

    mutating func begin(name: String, cask: Bool, mode: BPFormulaInformationMode = .general) -> BPFormulaInformationRequest {
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
    mutating func receive(request: BPFormulaInformationRequest, information: String?, website: URL?) -> Bool {
        guard self.request == request else { return false }
        self.information = information.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.website = website
        isLoading = false
        return true
    }

    mutating func close() {
        request = nil
        information = nil
        website = nil
        isLoading = false
    }
}

struct BPSelectedFormulaSnapshot: Equatable, Sendable {
    let identity: BPFormulaInformationIdentity
    let isInstalled: Bool
    let isPinned: Bool
    let installPath: String?
    let latestVersion: String?
    let dependencies: String?
    let conflicts: String?
    let shortDescription: String?

    init(name: String,
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
}

struct BPSelectedFormulaState: Sendable {
    enum Selection: Equatable, Sendable {
        case none
        case single(BPSelectedFormulaSnapshot)
        case multiple
    }

    private(set) var selection: Selection = .none
    private(set) var request: BPFormulaInformationRequest?
    private(set) var dependents: [String]?
    private var generation: UInt64 = 0

    var currentSnapshot: BPSelectedFormulaSnapshot? {
        if case .single(let snapshot) = selection {
            return snapshot
        }
        return nil
    }

    var showsPinnedRow: Bool {
        guard case .single(let snapshot) = selection else { return false }
        return snapshot.isPinned && !snapshot.identity.cask
    }

    mutating func clear() {
        generation += 1
        selection = .none
        request = nil
        dependents = nil
    }

    mutating func selectMultiple() {
        generation += 1
        selection = .multiple
        request = nil
        dependents = nil
    }

    @discardableResult
    mutating func beginSingle(_ snapshot: BPSelectedFormulaSnapshot) -> BPFormulaInformationRequest {
        generation += 1
        let next = BPFormulaInformationRequest(identity: snapshot.identity, generation: generation)
        selection = .single(snapshot)
        request = next
        dependents = nil
        return next
    }

    @discardableResult
    mutating func updateSingle(_ snapshot: BPSelectedFormulaSnapshot) -> Bool {
        guard case .single(let current) = selection,
              current.identity == snapshot.identity else {
            return false
        }
        selection = .single(snapshot)
        return true
    }

    @discardableResult
    mutating func receiveDependents(_ names: [String], for request: BPFormulaInformationRequest) -> Bool {
        guard self.request == request,
              case .single(let current) = selection,
              !current.identity.cask else {
            return false
        }
        dependents = names
        return true
    }
}

enum BPInstalledPackageSortColumn: String, Equatable, Sendable {
    case name = "Name"
    case version = "Version"
    case latestVersion = "LatestVersion"
    case status = "Status"
}

struct BPInstalledPackageRow: Identifiable, Equatable, Sendable {
    let identity: BPFormulaInformationIdentity
    let version: String
    let latestVersion: String
    let statusRank: Int
    let isPinned: Bool

    var id: BPFormulaInformationIdentity { identity }
    var name: String { identity.name }
    var cask: Bool { identity.cask }

    init(name: String,
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
    }
}

struct BPInstalledPackageListState: Sendable {
    private(set) var sourceRows: [BPInstalledPackageRow] = []
    private(set) var displayedRows: [BPInstalledPackageRow] = []
    private(set) var selectedID: BPFormulaInformationIdentity?
    private(set) var isCaskList = false
    private(set) var sortColumn: BPInstalledPackageSortColumn?
    private(set) var sortAscending = true

    var selectedRow: BPInstalledPackageRow? {
        guard let selectedID else { return nil }
        return displayedRows.first { $0.id == selectedID }
    }

    var selectedRowIndex: Int {
        guard let selectedID,
              let index = displayedRows.firstIndex(where: { $0.id == selectedID }) else {
            return -1
        }
        return index
    }

    mutating func replaceRows(_ rows: [BPInstalledPackageRow], isCaskList: Bool) {
        self.sourceRows = rows
        self.isCaskList = isCaskList
        rebuildDisplayedRows()
        if let selectedID, !displayedRows.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    mutating func setSort(column: BPInstalledPackageSortColumn?, ascending: Bool) {
        self.sortColumn = column
        self.sortAscending = ascending
        rebuildDisplayedRows()
    }

    mutating func select(id: BPFormulaInformationIdentity?) {
        guard let id, displayedRows.contains(where: { $0.id == id }) else {
            selectedID = nil
            return
        }
        selectedID = id
    }

    @discardableResult
    mutating func select(name: String, cask: Bool) -> Bool {
        let candidate = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        guard displayedRows.contains(where: { $0.id == candidate }) else {
            selectedID = nil
            return false
        }
        selectedID = candidate
        return true
    }

    @discardableResult
    mutating func selectRow(at index: Int) -> Bool {
        guard index >= 0 && index < displayedRows.count else {
            selectedID = nil
            return false
        }
        selectedID = displayedRows[index].id
        return true
    }

    func index(ofName name: String, cask: Bool) -> Int {
        guard !name.isEmpty else { return -1 }
        let target = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        return displayedRows.firstIndex(where: { $0.id == target }) ?? -1
    }

    private mutating func rebuildDisplayedRows() {
        guard let sortColumn else {
            displayedRows = sourceRows
            return
        }
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
    }

    static func compare(_ lhs: BPInstalledPackageRow,
                        _ rhs: BPInstalledPackageRow,
                        by column: BPInstalledPackageSortColumn) -> ComparisonResult {
        switch column {
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
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
