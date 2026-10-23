import CryptoKit
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

// MARK: - Secure In-App Update Discovery (#149)

public struct BPAppVersion: Equatable, Comparable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let raw: String

    public init(major: Int, minor: Int, patch: Int = 0, prerelease: String? = nil, raw: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        let cleanedPre = prerelease?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prerelease = (cleanedPre?.isEmpty == false) ? cleanedPre : nil
        if let raw, !raw.isEmpty {
            self.raw = raw
        } else if let prerelease = self.prerelease {
            self.raw = "\(major).\(minor).\(patch)-\(prerelease)"
        } else {
            self.raw = "\(major).\(minor).\(patch)"
        }
    }

    public init?(parsing string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutPrefix: String
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            withoutPrefix = String(trimmed.dropFirst())
        } else {
            withoutPrefix = trimmed
        }
        guard !withoutPrefix.isEmpty else { return nil }

        // Strip optional build metadata (+...)
        let withoutBuild = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let dashParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let corePart = String(dashParts[0])
        let prereleasePart: String? = dashParts.count > 1 ? String(dashParts[1]) : nil
        if let prereleasePart, prereleasePart.isEmpty {
            return nil
        }

        let numbers = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(numbers.count) else { return nil }
        guard let major = Int(numbers[0]), major >= 0,
              let minor = Int(numbers[1]), minor >= 0 else {
            return nil
        }
        let patch: Int
        if numbers.count == 3 {
            guard let parsedPatch = Int(numbers[2]), parsedPatch >= 0 else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }

        self.init(major: major, minor: minor, patch: patch, prerelease: prereleasePart, raw: withoutPrefix)
    }

    public static func < (lhs: BPAppVersion, rhs: BPAppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            // Prerelease is older than the final release of the same version
            return true
        case (nil, .some):
            return false
        case (.some(let lPre), .some(let rPre)):
            return lPre.localizedStandardCompare(rPre) == .orderedAscending
        }
    }
}

public struct BPAppUpdateRelease: Equatable, Sendable {
    public let version: BPAppVersion
    public let title: String
    public let releaseNotes: String
    public let downloadURL: URL
    public let sha256Hex: String
    public let ed25519SignatureBase64: String?
    public let publishedAt: String?

    public init(version: BPAppVersion,
                title: String,
                releaseNotes: String,
                downloadURL: URL,
                sha256Hex: String,
                ed25519SignatureBase64: String? = nil,
                publishedAt: String? = nil) {
        self.version = version
        self.title = title
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.sha256Hex = sha256Hex.lowercased()
        self.ed25519SignatureBase64 = ed25519SignatureBase64
        self.publishedAt = publishedAt
    }

    public var canonicalSignedPayload: Data {
        let string = "\(version.raw)\n\(downloadURL.absoluteString)\n\(sha256Hex.lowercased())"
        return Data(string.utf8)
    }
}

public enum BPAppUpdateFeedError: Error, Equatable, Sendable {
    case invalidJSON
    case invalidVersion
    case insecureDownloadURL
    case invalidSHA256
    case missingSignature
    case invalidSignature
}

public enum BPAppUpdateVerifier: Sendable {
    public static func isValidSHA256Hex(_ hex: String) -> Bool {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count == 64 else { return false }
        for byte in trimmed.utf8 {
            let isDigit = (byte >= 48 && byte <= 57)
            let isLowerHex = (byte >= 97 && byte <= 102)
            let isUpperHex = (byte >= 65 && byte <= 70)
            if !(isDigit || isLowerHex || isUpperHex) {
                return false
            }
        }
        return true
    }

    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func verifySHA256(data: Data, expectedHex: String) -> Bool {
        let cleaned = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidSHA256Hex(cleaned) else { return false }
        return sha256Hex(of: data) == cleaned
    }

    public static func verifyEd25519Signature(release: BPAppUpdateRelease, publicKeyBase64: String) -> Bool {
        guard let signatureBase64 = release.ed25519SignatureBase64,
              let signatureData = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let keyData = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return false
        }
        return publicKey.isValidSignature(signatureData, for: release.canonicalSignedPayload)
    }

    public static func parseFeed(data: Data, publicKeyBase64: String? = nil) -> Result<BPAppUpdateRelease, BPAppUpdateFeedError> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidJSON)
        }
        guard let versionString = json["version"] as? String,
              let version = BPAppVersion(parsing: versionString) else {
            return .failure(.invalidVersion)
        }
        guard let urlString = json["downloadURL"] as? String,
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return .failure(.insecureDownloadURL)
        }
        guard let sha256 = json["sha256"] as? String,
              isValidSHA256Hex(sha256) else {
            return .failure(.invalidSHA256)
        }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseNotes = (json["releaseNotes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let signature = (json["ed25519Signature"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let publishedAt = (json["publishedAt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let release = BPAppUpdateRelease(
            version: version,
            title: (title?.isEmpty == false) ? title! : "Cakebrew \(version.raw)",
            releaseNotes: releaseNotes,
            downloadURL: url,
            sha256Hex: sha256,
            ed25519SignatureBase64: signature,
            publishedAt: publishedAt)

        if let publicKeyBase64, !publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let signature, !signature.isEmpty else {
                return .failure(.missingSignature)
            }
            guard verifyEd25519Signature(release: release, publicKeyBase64: publicKeyBase64) else {
                return .failure(.invalidSignature)
            }
        }

        return .success(release)
    }
}

public struct BPAppUpdateState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate(latestVersion: String)
        case updateAvailable(release: BPAppUpdateRelease, isCryptographicallyVerified: Bool)
        case feedUnavailable
        case failed(message: String)
    }

    public static let defaultReleasesURL = URL(string: "https://github.com/scottdensmore/Cakebrew/releases")!

    public private(set) var currentVersion: BPAppVersion
    public private(set) var phase: Phase = .idle
    public private(set) var releasesPageURL: URL
    public private(set) var requestGeneration: UInt64 = 0

    public init(currentVersionString: String = "1.0.0",
                releasesPageURL: URL = BPAppUpdateState.defaultReleasesURL) {
        self.currentVersion = BPAppVersion(parsing: currentVersionString) ?? BPAppVersion(major: 1, minor: 0, patch: 0, raw: currentVersionString)
        self.releasesPageURL = releasesPageURL
    }

    @discardableResult
    public mutating func beginCheck(currentVersionString: String? = nil) -> UInt64 {
        if let currentVersionString, !currentVersionString.isEmpty {
            self.currentVersion = BPAppVersion(parsing: currentVersionString) ?? BPAppVersion(major: 1, minor: 0, patch: 0, raw: currentVersionString)
        }
        requestGeneration += 1
        phase = .checking
        return requestGeneration
    }

    @discardableResult
    public mutating func receiveFeedData(_ data: Data,
                                         publicKeyBase64: String? = nil,
                                         generation: UInt64) -> Bool {
        guard generation == requestGeneration else { return false }
        let hasPublicKey = (publicKeyBase64?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        switch BPAppUpdateVerifier.parseFeed(data: data, publicKeyBase64: publicKeyBase64) {
        case .success(let release):
            if release.version > currentVersion {
                phase = .updateAvailable(release: release, isCryptographicallyVerified: hasPublicKey)
            } else {
                phase = .upToDate(latestVersion: release.version.raw)
            }
        case .failure(let error):
            switch error {
            case .invalidJSON, .invalidVersion:
                phase = .failed(message: "Invalid update feed format.")
            case .insecureDownloadURL:
                phase = .failed(message: "Update download URL must use HTTPS.")
            case .invalidSHA256:
                phase = .failed(message: "Update feed is missing a valid SHA-256 digest.")
            case .missingSignature, .invalidSignature:
                phase = .failed(message: "Update signature verification failed.")
            }
        }
        return true
    }

    @discardableResult
    public mutating func receiveFeedUnavailable(generation: UInt64) -> Bool {
        guard generation == requestGeneration else { return false }
        phase = .feedUnavailable
        return true
    }

    @discardableResult
    public mutating func receiveError(_ message: String, generation: UInt64) -> Bool {
        guard generation == requestGeneration else { return false }
        phase = .failed(message: message)
        return true
    }
}

// MARK: - SwiftUI Tahoe Surface State Models

public struct BPEmptyStateModel: Equatable, Sendable {
    public let symbolName: String
    public let title: String
    public let message: String

    public init(symbolName: String, title: String, message: String) {
        self.symbolName = symbolName.isEmpty ? "tray" : symbolName
        self.title = title
        self.message = message
    }

    public var combinedAccessibilityLabel: String {
        "\(title). \(message)"
    }
}

public struct BPDisabledRecoveryState: Equatable, Sendable {
    public var title: String
    public var message: String
    public var retryEnabled: Bool
    public var isChecking: Bool

    public init(title: String = "",
                message: String = "",
                retryEnabled: Bool = true,
                isChecking: Bool = false) {
        self.title = title
        self.message = message
        self.retryEnabled = retryEnabled
        self.isChecking = isChecking
    }
}

public enum BPConsoleDiagnosticSeverity: Int, Equatable, Sendable {
    case idle = 0
    case running = 1
    case healthy = 2
    case warnings = 3
    case errors = 4
}

private func BPSplitLogLines(_ text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    var lines = text.components(separatedBy: .newlines)
    while lines.last == "" {
        lines.removeLast()
    }
    return lines
}

private func BPFilterLogLines(_ lines: [String], query: String) -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return lines }
    return lines.filter { $0.localizedCaseInsensitiveContains(trimmed) }
}

public struct BPConsoleToolState: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    public var runButtonTitle: String
    public var clearButtonTitle: String
    public var isRunning: Bool
    public var logText: String
    public var filterQuery: String

    public init(title: String = "",
                subtitle: String? = nil,
                runButtonTitle: String = "",
                clearButtonTitle: String = "",
                isRunning: Bool = false,
                logText: String = "",
                filterQuery: String = "") {
        self.title = title
        self.subtitle = subtitle
        self.runButtonTitle = runButtonTitle
        self.clearButtonTitle = clearButtonTitle
        self.isRunning = isRunning
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }

    public var warningCount: Int {
        allLines.reduce(into: 0) { count, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "warning:", options: [.caseInsensitive, .anchored]) != nil {
                count += 1
            }
        }
    }

    public var errorCount: Int {
        allLines.reduce(into: 0) { count, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "error:", options: [.caseInsensitive, .anchored]) != nil {
                count += 1
            }
        }
    }

    public var diagnosticSeverity: BPConsoleDiagnosticSeverity {
        if isRunning {
            return .running
        }
        if logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .idle
        }
        if errorCount > 0 {
            return .errors
        }
        if warningCount > 0 {
            return .warnings
        }
        return .healthy
    }

    public var diagnosticSummaryText: String {
        switch diagnosticSeverity {
        case .idle:
            return ""
        case .running:
            return NSLocalizedString("VoiceOver_Operation_Progress", comment: "")
        case .healthy:
            return NSLocalizedString("Homebrew_Task_Finished", comment: "")
        case .warnings:
            return "\(warningCount) \(NSLocalizedString("Generic_Attention", comment: ""))"
        case .errors:
            return "\(errorCount) \(NSLocalizedString("Generic_Error", comment: ""))"
        }
    }
}

public struct BPAutoremoveSheetState: Equatable, Sendable {
    public var statusText: String
    public var warningText: String
    public var removeButtonTitle: String
    public var cancelButtonTitle: String
    public var removeEnabled: Bool
    public var cancelEnabled: Bool
    public var isBusy: Bool
    public var candidateCount: Int
    public var logText: String
    public var filterQuery: String

    public init(statusText: String = "",
                warningText: String = "",
                removeButtonTitle: String = "",
                cancelButtonTitle: String = "",
                removeEnabled: Bool = false,
                cancelEnabled: Bool = true,
                isBusy: Bool = true,
                candidateCount: Int = 0,
                logText: String = "",
                filterQuery: String = "") {
        self.statusText = statusText
        self.warningText = warningText
        self.removeButtonTitle = removeButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
        self.removeEnabled = removeEnabled
        self.cancelEnabled = cancelEnabled
        self.isBusy = isBusy
        self.candidateCount = candidateCount
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }
}

public enum BPBundleOperationMode: Int, Equatable, Sendable {
    case importing = 0
    case exporting = 1
}

public struct BPBundleSheetState: Equatable, Sendable {
    public var mode: BPBundleOperationMode
    public var headerTitle: String
    public var subtitleText: String
    public var statusText: String
    public var detailText: String
    public var actionButtonTitle: String
    public var actionEnabled: Bool
    public var isRunning: Bool
    public var hasFinished: Bool
    public var succeeded: Bool
    public var logText: String
    public var filterQuery: String

    public init(mode: BPBundleOperationMode = .importing,
                headerTitle: String = "",
                subtitleText: String = "",
                statusText: String = "",
                detailText: String = "",
                actionButtonTitle: String = "",
                actionEnabled: Bool = true,
                isRunning: Bool = true,
                hasFinished: Bool = false,
                succeeded: Bool = false,
                logText: String = "",
                filterQuery: String = "") {
        self.mode = mode
        self.headerTitle = headerTitle
        self.subtitleText = subtitleText
        self.statusText = statusText
        self.detailText = detailText
        self.actionButtonTitle = actionButtonTitle
        self.actionEnabled = actionEnabled
        self.isRunning = isRunning
        self.hasFinished = hasFinished
        self.succeeded = succeeded
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }
}

public struct BPFormulaOptionRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let explanation: String
    public var isApplied: Bool

    public init(name: String, explanation: String, isApplied: Bool = false) {
        self.id = name
        self.name = name
        self.explanation = explanation
        self.isApplied = isApplied
    }
}

public struct BPFormulaOptionsSheetState: Equatable, Sendable {
    public var formulaName: String
    public var headerTitle: String
    public var helpText: String
    public var optionsColumnTitle: String
    public var descriptionPlaceholder: String
    public var cancelTitle: String
    public var installTitle: String
    public var options: [BPFormulaOptionRow]
    public var selectedOptionID: String?
    public var filterQuery: String

    public init(formulaName: String = "",
                headerTitle: String = "",
                helpText: String = "",
                optionsColumnTitle: String = "",
                descriptionPlaceholder: String = "",
                cancelTitle: String = "",
                installTitle: String = "",
                options: [BPFormulaOptionRow] = [],
                selectedOptionID: String? = nil,
                filterQuery: String = "") {
        self.formulaName = formulaName
        self.headerTitle = headerTitle
        self.helpText = helpText
        self.optionsColumnTitle = optionsColumnTitle
        self.descriptionPlaceholder = descriptionPlaceholder
        self.cancelTitle = cancelTitle
        self.installTitle = installTitle
        self.options = options
        self.selectedOptionID = selectedOptionID ?? options.first?.id
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var filteredOptions: [BPFormulaOptionRow] {
        let query = trimmedFilterQuery
        guard !query.isEmpty else { return options }
        return options.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.explanation.localizedCaseInsensitiveContains(query)
        }
    }

    public var selectedOptionNames: [String] {
        options.filter(\.isApplied).map(\.name)
    }

    public var appliedOptionCount: Int {
        options.reduce(into: 0) { count, row in
            if row.isApplied { count += 1 }
        }
    }

    public var selectedOptionDescription: String {
        guard let selectedOptionID,
              let row = options.first(where: { $0.id == selectedOptionID }),
              !row.explanation.isEmpty else {
            return descriptionPlaceholder
        }
        return row.explanation
    }

    public mutating func setApplied(_ applied: Bool, forOptionID id: String) {
        guard let index = options.firstIndex(where: { $0.id == id }) else { return }
        options[index].isApplied = applied
        selectedOptionID = id
    }

    public mutating func clearAllApplied() {
        for index in options.indices {
            options[index].isApplied = false
        }
    }
}

public enum BPServiceStatusFilter: Int, Equatable, Sendable {
    case all = 0
    case running = 1
    case stopped = 2
    case error = 3
}

public struct BPServicesState: Equatable, Sendable {
    public var statusFilter: BPServiceStatusFilter
    public var filterQuery: String
    public var runningCount: Int
    public var stoppedCount: Int
    public var errorCount: Int
    public var serviceFilePath: String
    public var logFilePath: String

    public init(statusFilter: BPServiceStatusFilter = .all,
                filterQuery: String = "",
                runningCount: Int = 0,
                stoppedCount: Int = 0,
                errorCount: Int = 0,
                serviceFilePath: String = "",
                logFilePath: String = "") {
        self.statusFilter = statusFilter
        self.filterQuery = filterQuery
        self.runningCount = runningCount
        self.stoppedCount = stoppedCount
        self.errorCount = errorCount
        self.serviceFilePath = serviceFilePath
        self.logFilePath = logFilePath
    }

    public var totalCount: Int {
        runningCount + stoppedCount + errorCount
    }
}

public struct BPInstallationSheetState: Equatable, Sendable {
    public var windowTitle: String
    public var formulaNamesText: String
    public var okTitle: String
    public var cancelTitle: String
    public var isRunning: Bool
    public var okEnabled: Bool
    public var cancelEnabled: Bool
    public var logText: String
    public var filterQuery: String

    public init(windowTitle: String = "",
                formulaNamesText: String = "",
                okTitle: String = "",
                cancelTitle: String = "",
                isRunning: Bool = true,
                okEnabled: Bool = false,
                cancelEnabled: Bool = true,
                logText: String = "",
                filterQuery: String = "") {
        self.windowTitle = windowTitle
        self.formulaNamesText = formulaNamesText
        self.okTitle = okTitle
        self.cancelTitle = cancelTitle
        self.isRunning = isRunning
        self.okEnabled = okEnabled
        self.cancelEnabled = cancelEnabled
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }
}

// MARK: - SwiftUI Tahoe About, Brewfile Review & Command Palette State Models

public enum BPAboutWindowTab: Int, Equatable, Sendable {
    case credits = 0
    case acknowledgements = 1
}

public struct BPAboutWindowState: Equatable, Sendable {
    public var appName: String
    public var appVersion: String
    public var appCopyright: String
    public var selectedTab: BPAboutWindowTab
    public var hasAcknowledgements: Bool

    public init(appName: String = "Cakebrew",
                appVersion: String = "",
                appCopyright: String = "",
                selectedTab: BPAboutWindowTab = .credits,
                hasAcknowledgements: Bool = true) {
        self.appName = appName
        self.appVersion = appVersion
        self.appCopyright = appCopyright
        self.selectedTab = selectedTab
        self.hasAcknowledgements = hasAcknowledgements
    }

    public var versionClipboardSummary: String {
        if appVersion.isEmpty {
            return appName
        }
        return "\(appName) (\(appVersion))"
    }
}

public enum BPBrewfileEntryFilter: Int, Equatable, Sendable {
    case all = 0
    case installed = 1
    case missing = 2
}

public struct BPBrewfileReviewState: Equatable, Sendable {
    public var fileName: String
    public var installedCount: Int
    public var missingCount: Int
    public var notCheckedCount: Int
    public var formulaCount: Int
    public var caskCount: Int
    public var tapCount: Int
    public var otherCount: Int
    public var canInstall: Bool
    public var summaryText: String
    public var statusFilter: BPBrewfileEntryFilter
    public var filterQuery: String

    public init(fileName: String = "Brewfile",
                installedCount: Int = 0,
                missingCount: Int = 0,
                notCheckedCount: Int = 0,
                formulaCount: Int = 0,
                caskCount: Int = 0,
                tapCount: Int = 0,
                otherCount: Int = 0,
                canInstall: Bool = false,
                summaryText: String = "",
                statusFilter: BPBrewfileEntryFilter = .all,
                filterQuery: String = "") {
        self.fileName = fileName
        self.installedCount = installedCount
        self.missingCount = missingCount
        self.notCheckedCount = notCheckedCount
        self.formulaCount = formulaCount
        self.caskCount = caskCount
        self.tapCount = tapCount
        self.otherCount = otherCount
        self.canInstall = canInstall
        self.summaryText = summaryText
        self.statusFilter = statusFilter
        self.filterQuery = filterQuery
    }

    public var totalEntryCount: Int {
        formulaCount + caskCount + tapCount + otherCount
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isFiltering: Bool {
        statusFilter != .all || !trimmedFilterQuery.isEmpty
    }

    public var filteredSummaryLines: [String] {
        let lines = BPSplitLogLines(summaryText)
        guard isFiltering else { return lines }
        let installedToken = NSLocalizedString("Installed", comment: "")
        let missingToken = NSLocalizedString("Missing", comment: "")
        let query = trimmedFilterQuery
        return lines.filter { line in
            guard line.contains(" — ") || line.contains("[") else { return false }
            let matchesStatus: Bool
            switch statusFilter {
            case .all:
                matchesStatus = true
            case .installed:
                matchesStatus = line.localizedCaseInsensitiveContains(installedToken)
                    || line.localizedCaseInsensitiveContains("Installed")
            case .missing:
                matchesStatus = line.localizedCaseInsensitiveContains(missingToken)
                    || line.localizedCaseInsensitiveContains("Missing")
            }
            guard matchesStatus else { return false }
            guard !query.isEmpty else { return true }
            return line.localizedCaseInsensitiveContains(query)
        }
    }

    public var filteredSummaryText: String {
        isFiltering ? filteredSummaryLines.joined(separator: "\n") : summaryText
    }

    public var matchingEntryCount: Int {
        if !isFiltering {
            return totalEntryCount
        }
        return filteredSummaryLines.count
    }
}

public enum BPCommandPaletteItemKind: Int, Equatable, Sendable {
    case navigation = 0
    case action = 1
    case package = 2
}

public struct BPCommandPaletteItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbolName: String
    public let shortcutHint: String?
    public let kind: BPCommandPaletteItemKind
    public let sidebarRow: Int
    public let actionIdentifier: String?
    public let packageName: String?
    public let isCask: Bool

    public init(id: String,
                title: String,
                subtitle: String = "",
                symbolName: String = "sparkle.magnifyingglass",
                shortcutHint: String? = nil,
                kind: BPCommandPaletteItemKind,
                sidebarRow: Int = -1,
                actionIdentifier: String? = nil,
                packageName: String? = nil,
                isCask: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.shortcutHint = shortcutHint
        self.kind = kind
        self.sidebarRow = sidebarRow
        self.actionIdentifier = actionIdentifier
        self.packageName = packageName
        self.isCask = isCask
    }
}

public struct BPCommandPaletteState: Equatable, Sendable {
    public var query: String = "" {
        didSet {
            normalizeSelection()
        }
    }
    public var items: [BPCommandPaletteItem] = [] {
        didSet {
            normalizeSelection()
        }
    }
    public var selectedItemID: String?

    public init(query: String = "",
                items: [BPCommandPaletteItem] = [],
                selectedItemID: String? = nil) {
        self.query = query
        self.items = items
        self.selectedItemID = selectedItemID
        normalizeSelection()
    }

    public var filteredItems: [BPCommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items
        }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
                || item.subtitle.localizedCaseInsensitiveContains(trimmed)
                || (item.packageName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    public var selectedItem: BPCommandPaletteItem? {
        let current = filteredItems
        if let selectedItemID, let match = current.first(where: { $0.id == selectedItemID }) {
            return match
        }
        return current.first
    }

    public mutating func normalizeSelection() {
        let current = filteredItems
        if let selectedItemID, current.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = current.first?.id
    }

    public mutating func moveSelection(delta: Int) {
        let current = filteredItems
        guard !current.isEmpty else {
            selectedItemID = nil
            return
        }
        guard let selectedItemID,
              let index = current.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = current.first?.id
            return
        }
        let nextIndex = max(0, min(current.count - 1, index + delta))
        self.selectedItemID = current[nextIndex].id
    }
}

public struct BPStatusBarState: Equatable, Sendable {
    public var message: String
    public var isBusy: Bool
    public var installedCount: Int
    public var outdatedCount: Int
    public var pinnedCount: Int

    public init(message: String = "",
                isBusy: Bool = false,
                installedCount: Int = 0,
                outdatedCount: Int = 0,
                pinnedCount: Int = 0) {
        self.message = message
        self.isBusy = isBusy
        self.installedCount = installedCount
        self.outdatedCount = outdatedCount
        self.pinnedCount = pinnedCount
    }
}

public struct BPSidebarRowState: Identifiable, Equatable, Sendable {
    public let id: String
    public let rowIndex: Int
    public let title: String
    public let groupTitle: String
    public let symbolName: String
    public var badgeCount: Int
    public let accessibilityIdentifier: String
    public var accessibilityLabel: String

    public init(rowIndex: Int,
                title: String,
                groupTitle: String,
                symbolName: String,
                badgeCount: Int = -1,
                accessibilityIdentifier: String,
                accessibilityLabel: String = "") {
        self.id = accessibilityIdentifier.isEmpty ? "row.\(rowIndex)" : accessibilityIdentifier
        self.rowIndex = rowIndex
        self.title = title
        self.groupTitle = groupTitle
        self.symbolName = symbolName
        self.badgeCount = badgeCount
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct BPSidebarSectionState: Identifiable, Equatable, Sendable {
    public let id: String
    public let rowIndex: Int
    public let title: String
    public var rows: [BPSidebarRowState]

    public init(rowIndex: Int, title: String, rows: [BPSidebarRowState] = []) {
        self.id = "section.\(rowIndex)"
        self.rowIndex = rowIndex
        self.title = title
        self.rows = rows
    }
}

public struct BPSidebarState: Equatable, Sendable {
    public var sections: [BPSidebarSectionState]
    public var selectedRowIndex: Int

    public init(sections: [BPSidebarSectionState] = [], selectedRowIndex: Int = 1) {
        self.sections = sections
        self.selectedRowIndex = selectedRowIndex
    }

    public var allRows: [BPSidebarRowState] {
        sections.flatMap(\.rows)
    }

    public var selectedRow: BPSidebarRowState? {
        allRows.first(where: { $0.rowIndex == selectedRowIndex })
    }

    public func badgeCount(forRowIndex rowIndex: Int) -> Int {
        allRows.first(where: { $0.rowIndex == rowIndex })?.badgeCount ?? -1
    }
}

public struct BPTapInputState: Equatable, Sendable {
    public var repositoryName: String

    public init(repositoryName: String = "") {
        self.repositoryName = repositoryName
    }

    public var trimmedName: String {
        repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValidFormat: Bool {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
}

public struct BPCleanupPreviewState: Equatable, Sendable {
    public var itemCount: Int
    public var reclaimableBytes: UInt64
    public var formattedByteCount: String
    public var samplePaths: [String]

    public init(itemCount: Int = 0,
                reclaimableBytes: UInt64 = 0,
                formattedByteCount: String = "",
                samplePaths: [String] = []) {
        self.itemCount = itemCount
        self.reclaimableBytes = reclaimableBytes
        self.formattedByteCount = formattedByteCount
        self.samplePaths = samplePaths
    }
}

// MARK: - Swift 6 Core Models & Utilities

@objc(BPAutoremovePreview)
public final class BPAutoremovePreview: NSObject, @unchecked Sendable {
    @objc public private(set) var valid: Bool = false
    @objc public private(set) var names: [String] = []
    @objc public private(set) var rawOutput: String = ""

    @objc(previewWithOutput:succeeded:)
    public static func preview(withOutput output: String?, succeeded: Bool) -> BPAutoremovePreview {
        let preview = BPAutoremovePreview()
        preview.rawOutput = output ?? ""
        preview.names = []
        guard succeeded, let output else { return preview }
        let text = output.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            preview.valid = true
            return preview
        }
        let lines = text.components(separatedBy: "\n")
        guard let header = try? NSRegularExpression(pattern: "^==> Would autoremove ([1-9][0-9]*) unneeded formula(e)?:$", options: []) else {
            return preview
        }
        let firstLine = lines[0] as NSString
        guard let match = header.firstMatch(in: lines[0], options: [], range: NSRange(location: 0, length: firstLine.length)) else {
            return preview
        }
        let countString = firstLine.substring(with: match.range(at: 1))
        guard let count = Int(countString), count > 0 else { return preview }
        let pluralAbsent = (match.range(at: 2).location == NSNotFound)
        if count != lines.count - 1 || (count == 1) != pluralAbsent {
            return preview
        }
        guard let namePattern = try? NSRegularExpression(pattern: "^(?:[a-zA-Z0-9][a-zA-Z0-9_.+-]*/[a-zA-Z0-9][a-zA-Z0-9_.+-]*/)?[a-zA-Z0-9][a-zA-Z0-9_.+@-]*$", options: []) else {
            return preview
        }
        var orderedNames: [String] = []
        var seen = Set<String>()
        for name in lines[1...count] {
            let nsName = name as NSString
            if namePattern.firstMatch(in: name, options: [], range: NSRange(location: 0, length: nsName.length)) == nil || seen.contains(name) {
                return preview
            }
            seen.insert(name)
            orderedNames.append(name)
        }
        preview.names = orderedNames
        preview.valid = true
        return preview
    }
}

@objc(BPFormulaOption)
public final class BPFormulaOption: NSObject, NSSecureCoding, NSCopying {
    private static let nameKey = "formulaOptionName"
    private static let explanationKey = "formulaOptionExplanation"

    @objc public var explanation: String?
    @objc public var name: String?

    @objc public static var supportsSecureCoding: Bool { true }

    public override init() {
        super.init()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init()
        self.name = aDecoder.decodeObject(of: NSString.self, forKey: Self.nameKey) as String?
        self.explanation = aDecoder.decodeObject(of: NSString.self, forKey: Self.explanationKey) as String?
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(name as NSString?, forKey: Self.nameKey)
        aCoder.encode(explanation as NSString?, forKey: Self.explanationKey)
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let option = BPFormulaOption()
        option.name = self.name
        option.explanation = self.explanation
        return option
    }
}

@objc(BPTimedDispatch)
public final class BPTimedDispatch: NSObject, @unchecked Sendable {
    private var scheduledBlock: (() -> Void)?
    private var dispatchTimer: Timer?
    private var dispatchQueue: DispatchQueue = .main

    @objc(scheduleDispatchAfterTimeInterval:ofBlock:)
    public func scheduleDispatch(afterTimeInterval interval: TimeInterval, of block: @escaping () -> Void) {
        scheduleDispatch(afterTimeInterval: interval, in: .main, of: block)
    }

    @objc(scheduleDispatchAfterTimeInterval:inQueue:ofBlock:)
    public func scheduleDispatch(afterTimeInterval interval: TimeInterval, in queue: DispatchQueue, of block: @escaping () -> Void) {
        scheduledBlock = block
        dispatchQueue = queue
        dispatchTimer?.invalidate()
        dispatchTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(dispatchBlockTimerDidFire(_:)),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func dispatchBlockTimerDidFire(_ sender: Timer) {
        nonisolated(unsafe) let localBlock = scheduledBlock
        scheduledBlock = nil
        let queue = dispatchQueue
        queue.async {
            localBlock?()
        }
    }
}

@objc(BPSearchCoordinator)
public final class BPSearchCoordinator: NSObject, @unchecked Sendable {
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let performSearch: (String) -> Void
    private let cancelSearch: () -> Void

    @objc(isSearching) public private(set) var searching: Bool = false
    @objc public private(set) var originalSidebarRow: Int = 0
    @objc public private(set) var generation: UInt = 0

    @objc(initWithPerformSearch:cancelSearch:)
    public convenience init(performSearch: @escaping (String) -> Void, cancelSearch: @escaping () -> Void) {
        let timedDispatch = BPTimedDispatch()
        self.init(
            schedule: { delay, work in
                timedDispatch.scheduleDispatch(afterTimeInterval: delay, in: .main, of: work)
            },
            performSearch: performSearch,
            cancelSearch: cancelSearch
        )
    }

    @objc(initWithSchedule:performSearch:cancelSearch:)
    public init(schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
                performSearch: @escaping (String) -> Void,
                cancelSearch: @escaping () -> Void) {
        self.schedule = schedule
        self.performSearch = performSearch
        self.cancelSearch = cancelSearch
        super.init()
    }

    @objc(scheduleQuery:)
    public func scheduleQuery(_ query: String) {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        precondition(!query.isEmpty)
        let currentGeneration = self.generation
        schedule(0.15) { [weak self] in
            guard let self, currentGeneration == self.generation else { return }
            self.performSearch(query)
        }
    }

    @objc(didReceiveResultsForSidebarRow:)
    public func didReceiveResults(forSidebarRow row: Int) {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        if !searching {
            originalSidebarRow = row
        }
        searching = true
    }

    @discardableResult
    @objc(endSearchReturningSidebarRow)
    public func endSearchReturningSidebarRow() -> Int {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        generation &+= 1
        searching = false
        cancelSearch()
        return originalSidebarRow
    }

    @objc(cancelForNavigation)
    public func cancelForNavigation() {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        generation &+= 1
        searching = false
        cancelSearch()
    }
}

@objc(BPBrewError)
public final class BPBrewError: NSObject {
    public static let errorDomain = "com.brunophilipe.Cakebrew.ErrorDomain"
    public static let exitStatusKey = "BPBrewErrorExitStatus"
    private static let maximumReportedLines = 12
    private static let maximumReportedLength = 1500

    private static func tail(of output: String) -> String {
        var lines: [String] = []
        (output as NSString).enumerateLines { line, _ in
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(line)
            }
        }
        if lines.count > maximumReportedLines {
            lines.removeFirst(lines.count - maximumReportedLines)
        }
        let joined = lines.joined(separator: "\n") as NSString
        if joined.length > maximumReportedLength {
            return joined.substring(from: joined.length - maximumReportedLength)
        }
        return joined as String
    }

    @objc(errorForExitStatus:output:)
    public static func error(forExitStatus status: Int32, output: String?) -> NSError? {
        if status == 0 {
            return nil
        }
        let code = (status < 0) ? 1 : 2 // BPBrewErrorLaunchFailed = 1, BPBrewErrorNonZeroExit = 2
        let tailText = tail(of: output ?? "")
        let description: String
        if !tailText.isEmpty {
            description = tailText
        } else {
            description = String(format: NSLocalizedString("Error_Brew_Failed_No_Output", comment: ""), status)
        }
        return NSError(
            domain: errorDomain,
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: description,
                exitStatusKey: NSNumber(value: status)
            ]
        )
    }
}

@objc(BPCleanupPreview)
public final class BPCleanupPreview: NSObject, @unchecked Sendable {
    private static let wouldRemovePrefix = "Would remove: "

    @objc public private(set) var itemCount: UInt = 0
    @objc public private(set) var reclaimableBytes: UInt64 = 0
    @objc public private(set) var paths: [String] = []

    @objc(isEmpty)
    public var empty: Bool {
        itemCount == 0 && reclaimableBytes == 0
    }

    @objc(previewFromOutput:)
    public static func preview(fromOutput output: String?) -> BPCleanupPreview {
        let preview = BPCleanupPreview()
        preview.paths = paths(fromOutput: output)
        preview.itemCount = UInt(preview.paths.count)
        preview.reclaimableBytes = reclaimableBytes(fromOutput: output)
        return preview
    }

    private static func paths(fromOutput output: String?) -> [String] {
        guard let output, !output.isEmpty else { return [] }
        var result: [String] = []
        let prefixLength = (wouldRemovePrefix as NSString).length
        (output as NSString).enumerateLines { line, _ in
            guard line.hasPrefix(wouldRemovePrefix) else { return }
            let rawPath = (line as NSString).substring(from: prefixLength)
                .trimmingCharacters(in: .whitespaces)
            let stripped = pathByStrippingSizeSuffix(rawPath)
            if !stripped.isEmpty {
                result.append(stripped)
            }
        }
        return result
    }

    private static func pathByStrippingSizeSuffix(_ path: String) -> String {
        guard path.hasSuffix(")") else { return path }
        let nsPath = path as NSString
        let open = nsPath.range(of: " (", options: .backwards)
        guard open.location != NSNotFound else { return path }
        return nsPath.substring(to: open.location)
    }

    private static func reclaimableBytes(fromOutput output: String?) -> UInt64 {
        guard let output, !output.isEmpty else { return 0 }
        guard let expression = try? NSRegularExpression(
            pattern: "would free approximately ([0-9]+(?:\\.[0-9]+)?)\\s*(TB|GB|MB|KB|B)\\b",
            options: [.caseInsensitive]
        ) else {
            return 0
        }
        let nsOutput = output as NSString
        guard let match = expression.firstMatch(in: output, options: [], range: NSRange(location: 0, length: nsOutput.length)) else {
            return 0
        }
        let number = nsOutput.substring(with: match.range(at: 1))
        let unit = nsOutput.substring(with: match.range(at: 2)).uppercased()
        let value = NSDecimalNumber(string: number, locale: Locale(identifier: "en_US_POSIX"))
        if value == NSDecimalNumber.notANumber {
            return 0
        }
        let multiplier: UInt64
        switch unit {
        case "KB": multiplier = 1024
        case "MB": multiplier = 1024 * 1024
        case "GB": multiplier = 1024 * 1024 * 1024
        case "TB": multiplier = 1024 * 1024 * 1024 * 1024
        default:   multiplier = 1
        }
        return UInt64(value.doubleValue * Double(multiplier))
    }
}

@objc(BPBrewfile)
public final class BPBrewfile: NSObject {
    private static let brewfileName = "Brewfile"

    @objc public static func defaultFilename() -> String {
        brewfileName
    }

    @objc(isBrewfileURL:)
    public static func isBrewfileURL(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        let name = url.lastPathComponent
        guard !name.isEmpty else { return false }
        if name.caseInsensitiveCompare(brewfileName) == .orderedSame {
            return true
        }
        let suffix = "." + brewfileName
        let nsName = name as NSString
        let nsSuffix = suffix as NSString
        guard nsName.length > nsSuffix.length else { return false }
        let tail = nsName.substring(from: nsName.length - nsSuffix.length)
        return tail.caseInsensitiveCompare(suffix) == .orderedSame
    }

    @objc(brewfileURLsFrom:)
    public static func brewfileURLs(from urls: [URL]?) -> [URL] {
        guard let urls, !urls.isEmpty else { return [] }
        return urls.filter { isBrewfileURL($0) }
    }
}

@objc(BPBrewfileEntry)
public final class BPBrewfileEntry: NSObject {
    @objc public internal(set) var kind: String = ""
    @objc public internal(set) var name: String = ""
    @objc public internal(set) var status: String = ""
    @objc public var appStoreID: String?
}

@objc(BPBrewfilePlan)
public final class BPBrewfilePlan: NSObject, @unchecked Sendable {
    @objc public private(set) var entries: [BPBrewfileEntry] = []
    @objc public private(set) var diagnostics: [String] = []
    @objc public private(set) var canonicalContents: String?

    @objc public var canInstall: Bool {
        guard let canonicalContents, !canonicalContents.isEmpty else { return false }
        return diagnostics.isEmpty
    }

    @objc public var reviewText: String {
        var installed: UInt = 0
        var missing: UInt = 0
        var unchecked: UInt = 0
        for entry in entries {
            if entry.status == "Installed" {
                installed += 1
            } else if entry.status == "Missing" {
                missing += 1
            } else {
                unchecked += 1
            }
        }
        var text = String(
            format: NSLocalizedString("%lu installed • %lu missing • %lu not checked", comment: ""),
            installed, missing, unchecked
        ) + "\n\n"

        let kinds = ["brew", "cask", "tap", "mas", "vscode"]
        let titles = [
            NSLocalizedString("Formulae", comment: ""),
            NSLocalizedString("Casks", comment: ""),
            NSLocalizedString("Taps", comment: ""),
            NSLocalizedString("Mac App Store", comment: ""),
            NSLocalizedString("VS Code", comment: "")
        ]
        for (index, kind) in kinds.enumerated() {
            var lines: [String] = []
            for entry in entries where entry.kind == kind {
                let status: String
                if entry.status == "Installed" {
                    status = NSLocalizedString("Installed", comment: "")
                } else if entry.status == "Missing" {
                    status = NSLocalizedString("Missing", comment: "")
                } else {
                    status = NSLocalizedString("Not checked", comment: "")
                }
                let displayName: String
                if let appStoreID = entry.appStoreID {
                    displayName = "\(entry.name) (id: \(appStoreID))"
                } else {
                    displayName = entry.name
                }
                lines.append("\(displayName) — \(status)")
            }
            if !lines.isEmpty {
                text += "\(titles[index])\n\(lines.joined(separator: "\n"))\n\n"
            }
        }
        if !diagnostics.isEmpty {
            text += diagnostics.joined(separator: "\n")
        } else if entries.isEmpty {
            text += NSLocalizedString("No supported package entries. Nothing will be installed.", comment: "")
        }
        return text
    }

    private static func matches(_ string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let nsString = string as NSString
        return regex.numberOfMatches(in: string, options: [], range: NSRange(location: 0, length: nsString.length)) == 1
    }

    @objc(planWithURL:inventories:error:)
    public static func plan(with url: URL?, inventories: [String: [String]]?) throws -> BPBrewfilePlan {
        let limit = 1024 * 1024
        var descriptor: Int32 = -1
        if let url, url.isFileURL {
            descriptor = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }
                return Darwin.open(path, O_RDONLY | O_NONBLOCK)
            }
        }
        var info = stat()
        let data = NSMutableData()
        var valid = descriptor >= 0 && fstat(descriptor, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_size <= limit
        if valid {
            var buffer = [UInt8](repeating: 0, count: 8192)
            var count: Int = -1
            while data.length <= limit {
                count = buffer.withUnsafeMutableBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                    return Darwin.read(descriptor, baseAddress, rawBuffer.count)
                }
                if count > 0 {
                    data.append(buffer, length: count)
                } else {
                    break
                }
            }
            valid = (count == 0 && data.length <= limit)
        }
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        guard valid, let contents = String(data: data as Data, encoding: .utf8) else {
            throw NSError(
                domain: "Cakebrew.Brewfile",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Choose a readable UTF-8 Brewfile smaller than 1 MiB. Nothing was installed.", comment: "")
                ]
            )
        }
        return plan(withString: contents, inventories: inventories)
    }

    @objc(planWithString:inventories:)
    public static func plan(withString contents: String, inventories: [String: [String]]?) -> BPBrewfilePlan {
        let plan = BPBrewfilePlan()
        var parsedEntries: [BPBrewfileEntry] = []
        var parsedDiagnostics: [String] = []
        var canonical = ""
        let literal = try? NSRegularExpression(
            pattern: "\\A[ \\t]*(brew|cask|tap|mas|vscode)[ \\t]+(['\"])([^'\"\\\\\\r\\n]+)\\2(?:[ \\t]*,[ \\t]*id:[ \\t]*([1-9][0-9]*))?[ \\t]*(?:#[^\\r\\n]*)?\\z",
            options: []
        )
        let lines = contents.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if matches(line, pattern: "\\A[ \\t]*(?:#[^\\r\\n]*)?\\z") {
                continue
            }
            let nsLine = line as NSString
            let match = literal?.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
            let kind = match.map { nsLine.substring(with: $0.range(at: 1)) }
            let name = match.map { nsLine.substring(with: $0.range(at: 3)) }
            let identifier: String?
            if let match, match.range(at: 4).location != NSNotFound {
                identifier = nsLine.substring(with: match.range(at: 4))
            } else {
                identifier = nil
            }
            var valid = (match != nil)
            if kind == "mas" {
                if let identifier, let name {
                    valid = valid && identifier.count <= 18 && matches(name, pattern: "\\A[A-Za-z0-9][A-Za-z0-9 ._()+&:!-]*\\z")
                } else {
                    valid = false
                }
            } else if let kind, let name {
                valid = valid && (identifier == nil)
                let component = "[a-zA-Z0-9][a-zA-Z0-9_+@.-]*"
                let pattern: String
                if kind == "tap" {
                    pattern = "\\A\(component)/\(component)\\z"
                } else if kind == "vscode" {
                    pattern = "\\A[a-zA-Z0-9][a-zA-Z0-9-]*\\.[a-zA-Z0-9][a-zA-Z0-9-]*\\z"
                } else {
                    pattern = "\\A\(component)(?:/\(component)/\(component))?\\z"
                }
                valid = valid && matches(name, pattern: pattern)
            } else {
                valid = false
            }

            guard valid, let kind, let name else {
                parsedDiagnostics.append(
                    String.localizedStringWithFormat(
                        NSLocalizedString("Line %lu: unsupported syntax or invalid package name. Nothing will be installed.", comment: ""),
                        UInt(index + 1)
                    )
                )
                continue
            }

            let entry = BPBrewfileEntry()
            entry.kind = kind
            entry.name = name
            entry.appStoreID = identifier
            let inventory = inventories?[kind]
            let qualified = (kind != "tap" && name.contains("/"))
            if inventory == nil || kind == "mas" || kind == "vscode" || qualified {
                entry.status = "Not checked"
            } else if inventory?.contains(name) == true {
                entry.status = "Installed"
            } else {
                entry.status = "Missing"
            }
            parsedEntries.append(entry)
            let idSuffix = identifier.map { ", id: \($0)" } ?? ""
            canonical += "\(kind) '\(name)'\(idSuffix)\n"
        }

        plan.entries = parsedEntries
        plan.diagnostics = parsedDiagnostics
        if !parsedEntries.isEmpty && parsedDiagnostics.isEmpty {
            plan.canonicalContents = canonical
        }
        return plan
    }

    @objc(createSnapshotWithError:)
    public func createSnapshot() throws -> URL {
        guard canInstall, let canonicalContents else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil)
        }
        let template = (NSTemporaryDirectory() as NSString).appendingPathComponent("cakebrew-reviewed-XXXXXX")
        var buffer = template.utf8CString
        let directoryPath: String? = buffer.withUnsafeMutableBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress, mkdtemp(baseAddress) != nil else { return nil }
            return String(cString: baseAddress)
        }
        guard let directoryPath else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let url = directoryURL.appendingPathComponent("Brewfile")
        let data = canonicalContents.data(using: .utf8)
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o400]) else {
            Self.removeSnapshot(url)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil)
        }
        return url
    }

    @objc(removeSnapshot:)
    public static func removeSnapshot(_ snapshot: URL?) {
        guard let snapshot,
              snapshot.lastPathComponent == "Brewfile",
              snapshot.deletingLastPathComponent().lastPathComponent.hasPrefix("cakebrew-reviewed-") else {
            return
        }
        try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent())
    }
}

@objc(BPPreferences)
public final class BPPreferences: NSObject {
    public static let backgroundCheckEnabledKey = "BPBackgroundCheckEnabled"
    public static let backgroundCheckIntervalKey = "BPBackgroundCheckInterval"
    public static let greedyCaskUpgradesKey = "BPGreedyCaskUpgrades"
    public static let lastSelectedSidebarRowKey = "BPLastSelectedSidebarRow"
    public static let sortColumnIdentifierKey = "BPSortColumnIdentifier"
    public static let sortAscendingKey = "BPSortAscending"
    public static let zapCasksOnUninstallKey = "BPZapCasksOnUninstall"
    public static let automaticAppUpdateCheckEnabledKey = "BPAutomaticAppUpdateCheckEnabled"
    public static let showMenuBarExtraKey = "BPShowMenuBarExtra"

    @objc public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            backgroundCheckEnabledKey: true,
            backgroundCheckIntervalKey: 21600.0,
            greedyCaskUpgradesKey: false,
            lastSelectedSidebarRowKey: 1,
            sortAscendingKey: true,
            zapCasksOnUninstallKey: false,
            automaticAppUpdateCheckEnabledKey: true,
            showMenuBarExtraKey: false
        ])
    }

    @objc public static var backgroundCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: backgroundCheckEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundCheckEnabledKey) }
    }

    @objc public static var backgroundCheckInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: backgroundCheckIntervalKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundCheckIntervalKey) }
    }

    @objc public static var lastSelectedSidebarRow: Int {
        get { UserDefaults.standard.integer(forKey: lastSelectedSidebarRowKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSelectedSidebarRowKey) }
    }

    @objc public static var sortColumnIdentifier: String? {
        get { UserDefaults.standard.string(forKey: sortColumnIdentifierKey) }
        set {
            guard let newValue, !newValue.isEmpty else {
                UserDefaults.standard.removeObject(forKey: sortColumnIdentifierKey)
                return
            }
            UserDefaults.standard.set(newValue, forKey: sortColumnIdentifierKey)
        }
    }

    @objc public static var sortAscending: Bool {
        get { UserDefaults.standard.bool(forKey: sortAscendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: sortAscendingKey) }
    }

    @objc public static var zapCasksOnUninstall: Bool {
        get { UserDefaults.standard.bool(forKey: zapCasksOnUninstallKey) }
        set { UserDefaults.standard.set(newValue, forKey: zapCasksOnUninstallKey) }
    }

    @objc public static var greedyCaskUpgrades: Bool {
        get { UserDefaults.standard.bool(forKey: greedyCaskUpgradesKey) }
        set { UserDefaults.standard.set(newValue, forKey: greedyCaskUpgradesKey) }
    }

    @objc public static var automaticAppUpdateCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: automaticAppUpdateCheckEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: automaticAppUpdateCheckEnabledKey) }
    }

    @objc public static var showMenuBarExtra: Bool {
        get { UserDefaults.standard.bool(forKey: showMenuBarExtraKey) }
        set { UserDefaults.standard.set(newValue, forKey: showMenuBarExtraKey) }
    }
}

@objc(BPLoadingStatus)
public final class BPLoadingStatus: NSObject {
    @objc(localizationKeyForListMode:)
    public static func localizationKey(forListMode mode: Int) -> String? {
        switch mode {
        case 1: return "Loading_Status_Installed"
        case 3: return "Loading_Status_Outdated"
        case 2: return "Loading_Status_Leaves"
        case 6: return "Loading_Status_Pinned"
        case 5: return "Loading_Status_Repositories"
        case 7: return "Loading_Status_InstalledCasks"
        case 8: return "Loading_Status_OutdatedCasks"
        case 0: return "Loading_Status_AllFormulae"
        case 9: return "Loading_Status_AllCasks"
        default: return nil
        }
    }

    @objc(statusForListMode:)
    public static func status(forListMode mode: Int) -> String {
        let key = localizationKey(forListMode: mode) ?? "Loading_Status_Default"
        return NSLocalizedString(key, comment: "")
    }

    @objc(isSlowListMode:)
    public static func isSlowListMode(_ mode: Int) -> Bool {
        return mode == 0 || mode == 9
    }
}

@objc(BPEmptyState)
public final class BPEmptyState: NSObject {
    @objc public let symbolName: String
    @objc public let titleKey: String
    @objc public let messageKey: String

    public init(symbolName: String, titleKey: String, messageKey: String) {
        self.symbolName = symbolName
        self.titleKey = titleKey
        self.messageKey = messageKey
        super.init()
    }

    @objc(stateForSidebarRow:searching:)
    public static func state(forSidebarRow row: Int, searching: Bool) -> BPEmptyState {
        if searching {
            return BPEmptyState(
                symbolName: "magnifyingglass",
                titleKey: "Empty_Search_Title",
                messageKey: "Empty_Search_Message"
            )
        }
        switch row {
        case 2, 15:
            return BPEmptyState(
                symbolName: "checkmark.circle",
                titleKey: "Empty_Outdated_Title",
                messageKey: "Empty_Outdated_Message"
            )
        case 9:
            return BPEmptyState(
                symbolName: "checkmark.circle",
                titleKey: "Empty_OutdatedCasks_Title",
                messageKey: "Empty_OutdatedCasks_Message"
            )
        case 5:
            return BPEmptyState(
                symbolName: "pin",
                titleKey: "Empty_Pinned_Title",
                messageKey: "Empty_Pinned_Message"
            )
        case 14:
            return BPEmptyState(
                symbolName: "gearshape.2",
                titleKey: "Empty_Services_Title",
                messageKey: "Empty_Services_Message"
            )
        case 8:
            return BPEmptyState(
                symbolName: "macwindow",
                titleKey: "Empty_Casks_Title",
                messageKey: "Empty_Casks_Message"
            )
        case 4:
            return BPEmptyState(
                symbolName: "leaf",
                titleKey: "Empty_Leaves_Title",
                messageKey: "Empty_Leaves_Message"
            )
        default:
            return BPEmptyState(
                symbolName: "tray",
                titleKey: "Empty_Generic_Title",
                messageKey: "Empty_Generic_Message"
            )
        }
    }

    @objc(shouldShowForRowCount:loading:)
    public static func shouldShow(forRowCount rowCount: Int, loading: Bool) -> Bool {
        return rowCount == 0 && !loading
    }
}

@objc(BPServiceStatus)
public enum BPServiceStatus: Int, Sendable {
    case none = 0
    case started = 1
    case stopped = 2
    case error = 3
    case scheduled = 4
    case unknown = 5
}

@objc(BPService)
public final class BPService: NSObject, @unchecked Sendable {
    @objc public var name: String?
    @objc public var user: String?
    @objc public var pid: NSNumber?
    @objc public var status: BPServiceStatus = .none
    @objc public var statusString: String?

    @objc(localizationKeyForStatus:)
    public static func localizationKey(for status: BPServiceStatus) -> String {
        switch status {
        case .none:      return "Services_Status_None"
        case .started:   return "Services_Status_Started"
        case .stopped:   return "Services_Status_Stopped"
        case .error:     return "Services_Status_Error"
        case .scheduled: return "Services_Status_Scheduled"
        case .unknown:   return "Services_Status_Unknown"
        @unknown default: return "Services_Status_Unknown"
        }
    }

    @objc(localizedNameForStatus:)
    public static func localizedName(for status: BPServiceStatus) -> String {
        return NSLocalizedString(localizationKey(for: status), comment: "")
    }

    @objc(statusFromString:)
    public static func status(from status: String?) -> BPServiceStatus {
        switch status {
        case "none":      return .none
        case "started":   return .started
        case "stopped":   return .stopped
        case "error":     return .error
        case "scheduled": return .scheduled
        default:          return .unknown
        }
    }

    @objc(validatedServicesFromJSONString:)
    public static func validatedServices(fromJSONString output: String?) -> [BPService]? {
        guard let data = output?.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let entries = parsed as? [Any] else {
            return nil
        }
        var services: [BPService] = []
        for entry in entries {
            guard let dict = entry as? [String: Any] else { return nil }
            for key in ["user", "status", "pid"] {
                if let value = dict[key], !(value is NSNull) {
                    if key == "pid" {
                        guard value is NSNumber else { return nil }
                    } else {
                        guard value is NSString else { return nil }
                    }
                }
            }
            guard let service = service(withDictionary: dict) else { return nil }
            services.append(service)
        }
        return services
    }

    @objc(servicesFromJSONString:)
    public static func services(fromJSONString output: String?) -> [BPService] {
        guard let data = output?.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let entries = parsed as? [Any] else {
            return []
        }
        var services: [BPService] = []
        for entry in entries {
            guard let dict = entry as? [String: Any] else { continue }
            if let service = service(withDictionary: dict) {
                services.append(service)
            }
        }
        return services
    }

    private static func service(withDictionary dict: [String: Any]) -> BPService? {
        guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
        let service = BPService()
        service.name = name
        service.user = dict["user"] as? String
        service.statusString = dict["status"] as? String
        service.status = status(from: service.statusString)
        if let pid = dict["pid"] as? NSNumber {
            service.pid = pid
        }
        return service
    }
}

@objc(BPServiceDetails)
public final class BPServiceDetails: NSObject, @unchecked Sendable {
    @objc public private(set) var available: Bool = false
    @objc public private(set) var service: BPService?
    @objc public private(set) var rawOutput: String = ""
    @objc public private(set) var serviceFile: String?
    @objc public private(set) var loadedFile: String?
    @objc public private(set) var logPath: String?
    @objc public private(set) var errorLogPath: String?
    @objc public private(set) var exitCode: NSNumber?

    @objc(readableFileURLForPath:)
    public static func readableFileURL(forPath path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let nsPath = path as NSString
        if nsPath.rangeOfCharacter(from: .controlCharacters).location != NSNotFound {
            return nil
        }
        if path.hasPrefix("//") || (!path.hasPrefix("/") && !path.hasPrefix("~/")) {
            return nil
        }
        let resolved = ((nsPath.expandingTildeInPath as NSString).standardizingPath as NSString).resolvingSymlinksInPath
        let files = FileManager.default
        guard let attributes = try? files.attributesOfItem(atPath: resolved),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              files.isReadableFile(atPath: resolved) else {
            return nil
        }
        return URL(fileURLWithPath: resolved)
    }

    @objc(detailsForName:output:succeeded:)
    public static func details(forName name: String?, output: String?, succeeded: Bool) -> BPServiceDetails {
        let result = BPServiceDetails()
        result.rawOutput = output ?? ""
        guard succeeded, let name, !name.isEmpty,
              let data = result.rawOutput.data(using: .utf8),
              let records = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [Any],
              records.count == 1,
              let record = records.first as? [String: Any],
              (record["name"] as? String) == name else {
            return result
        }
        result.service = BPService.services(fromJSONString: output).first
        result.serviceFile = record["file"] as? String
        result.loadedFile = record["loaded_file"] as? String
        result.logPath = record["log_path"] as? String
        result.errorLogPath = record["error_log_path"] as? String
        result.exitCode = integerOrNil(record["exit_code"])
        let pid = integerOrNil(record["pid"])
        result.service?.pid = (pid?.int64Value ?? 0) > 0 ? pid : nil
        result.available = (result.service != nil)
        return result
    }

    private static func integerOrNil(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID() else {
            return nil
        }
        return number.doubleValue == Double(number.int64Value) ? number : nil
    }
}

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

@objc(BPBrewfileImportOperation)
public final class BPBrewfileImportOperation: NSObject, @unchecked Sendable {
    @objc public private(set) var running: Bool = false
    @objc public func isRunning() -> Bool { running }

    private let plan: BPBrewfilePlan?
    private let interfaceObject: AnyObject?
    private let progress: Progress
    private let stateLock = NSLock()
    private var started: Bool = false

    @objc(initWithPlan:interface:)
    public init(plan: BPBrewfilePlan?, interface: Any?) {
        self.plan = plan
        self.interfaceObject = interface as AnyObject?
        self.progress = Progress(totalUnitCount: 1)
        super.init()
    }

    @objc(startWithOutput:completion:)
    public func start(
        withOutput output: (@Sendable (String) -> Void)?,
        completion: (@Sendable (Bool, Bool, NSError?) -> Void)?
    ) {
        stateLock.lock()
        if started {
            stateLock.unlock()
            return
        }
        started = true
        running = true
        stateLock.unlock()

        let plan = self.plan
        nonisolated(unsafe) let iface = self.interfaceObject
        let progress = self.progress

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSError?
            var snapshot: URL?
            var success = false

            if let bridge = bpAsHomebrewInterface(iface) {
                if bridge.brewTransport != 0 {
                    error = NSError(
                        domain: "Cakebrew.Brewfile",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString(
                                "Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.",
                                comment: ""
                            )
                        ]
                    )
                } else if !progress.isCancelled && (plan?.canInstall == true) {
                    do {
                        snapshot = try plan?.createSnapshot()
                    } catch let err as NSError {
                        error = err
                    }
                    if let snapshot, !progress.isCancelled {
                        success = bridge.runBrewImportTool(withPath: snapshot.path, progress: progress) { chunk in
                            if let output {
                                DispatchQueue.main.async {
                                    output(chunk)
                                }
                            }
                        }
                    }
                }
            }

            BPBrewfilePlan.removeSnapshot(snapshot)
            DispatchQueue.main.async {
                self?.running = false
                let cancelled = progress.isCancelled
                completion?(success && !cancelled, cancelled, error)
            }
        }
    }

    @objc public func cancel() {
        stateLock.lock()
        let shouldCancel = !started || running
        stateLock.unlock()
        if shouldCancel {
            progress.cancel()
        }
    }
}

@objc(BPAutoremoveOperation)
public final class BPAutoremoveOperation: NSObject, @unchecked Sendable {
    @objc public private(set) var running: Bool = false
    @objc public func isRunning() -> Bool { running }

    private let preview: BPAutoremovePreview?
    private let interfaceObject: AnyObject?
    private let progress: Progress
    private let stateLock = NSLock()
    private var started: Bool = false
    private var workerFinished: Bool = false

    @objc(initWithPreview:interface:)
    public init(preview: BPAutoremovePreview?, interface: Any?) {
        self.preview = preview
        self.interfaceObject = interface as AnyObject?
        self.progress = Progress(totalUnitCount: 1)
        super.init()
    }

    @objc(startWithOutput:completion:)
    public func start(
        withOutput output: (@Sendable (String) -> Void)?,
        completion: (@Sendable (Bool, Bool, Bool, String) -> Void)?
    ) {
        stateLock.lock()
        if started {
            stateLock.unlock()
            return
        }
        started = true
        running = true
        stateLock.unlock()

        let preview = self.preview
        nonisolated(unsafe) let iface = self.interfaceObject
        let progress = self.progress

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var success = false
            var attempted = false
            var message = NSLocalizedString(
                "The unused dependency list changed or could not be verified. Nothing was removed. Close this window and review a new preview.",
                comment: ""
            )

            if let bridge = bpAsHomebrewInterface(iface),
               let preview,
               bridge.brewTransport == 0,
               preview.valid,
               !preview.names.isEmpty,
               !progress.isCancelled {
                let fresh = bridge.previewAutoremove(withProgress: progress)
                if let output, let raw = fresh?.rawOutput, !raw.isEmpty {
                    DispatchQueue.main.async {
                        output(raw)
                    }
                }
                if let fresh,
                   fresh.valid,
                   Set(fresh.names) == Set(preview.names),
                   !progress.isCancelled {
                    attempted = true
                    success = bridge.removeUnusedFormulae(preview.names, progress: progress) { chunk in
                        if let output {
                            DispatchQueue.main.async {
                                output(chunk)
                            }
                        }
                    }
                    message = success
                        ? NSLocalizedString("Reviewed unused dependencies were removed.", comment: "")
                        : NSLocalizedString("Removal failed. Packages may have been partially removed. The formula and service lists will be refreshed.", comment: "")
                }
            }

            var cancelled = false
            if let self {
                self.stateLock.lock()
                self.workerFinished = true
                cancelled = progress.isCancelled
                self.stateLock.unlock()
            } else {
                cancelled = progress.isCancelled
            }

            if cancelled {
                message = attempted
                    ? NSLocalizedString("Removal cancelled. Packages may have been partially removed. The formula and service lists will be refreshed.", comment: "")
                    : NSLocalizedString("Cancelled before removal. Nothing was removed.", comment: "")
            }

            DispatchQueue.main.async {
                self?.running = false
                completion?(success && !cancelled, cancelled, attempted, message)
            }
        }
    }

    @objc public func cancel() {
        stateLock.lock()
        if !workerFinished {
            progress.cancel()
        }
        stateLock.unlock()
    }
}

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

@objc(BPUpgradeBatchStatus)
public enum BPUpgradeBatchStatus: UInt {
    @objc(BPUpgradeBatchUnattempted) case unattempted = 0
    @objc(BPUpgradeBatchSucceeded) case succeeded = 1
    @objc(BPUpgradeBatchFailed) case failed = 2
    @objc(BPUpgradeBatchCancelled) case cancelled = 3
}

@objc(BPUpgradeBatchResult)
public final class BPUpgradeBatchResult: NSObject, @unchecked Sendable {
    @objc public internal(set) var arguments: [String] = []
    @objc public internal(set) var status: BPUpgradeBatchStatus = .unattempted
}

@objc(BPUpgradeResult)
public final class BPUpgradeResult: NSObject, @unchecked Sendable {
    @objc public internal(set) var batches: [BPUpgradeBatchResult] = []
    @objc public internal(set) var cancelled: Bool = false

    @objc public var succeeded: Bool {
        guard !batches.isEmpty && !cancelled else { return false }
        for batch in batches where batch.status != .succeeded {
            return false
        }
        return true
    }

    @objc public var attempted: Bool {
        for batch in batches where batch.status != .unattempted {
            return true
        }
        return false
    }
}

@objc(BPUpgradePlan)
public final class BPUpgradePlan: NSObject, Sendable {
    private let batches: [[String]]

    @objc(initWithSelection:)
    public init(selection: [Any]?) {
        var formulae = ["upgrade", "--formula"]
        var casks = ["upgrade", "--cask"]
        var valid = true

        for element in selection ?? [] {
            guard let formula = bpAsFormula(element),
                  let rawName = formula.name else {
                valid = false
                break
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                valid = false
                break
            }
            if formula.cask {
                casks.append(name)
            } else {
                formulae.append(name)
            }
        }

        if valid {
            var planned: [[String]] = []
            if formulae.count > 2 { planned.append(formulae) }
            if casks.count > 2 { planned.append(casks) }
            self.batches = planned
        } else {
            self.batches = []
        }
        super.init()
    }

    @discardableResult
    @objc(executeWithProgress:runner:)
    public func execute(withProgress progress: Progress?, runner: ([String]) -> Bool) -> Bool {
        executeReporting(withProgress: progress, runner: runner).succeeded
    }

    @objc(executeReportingWithProgress:runner:)
    public func executeReporting(withProgress progress: Progress?, runner: ([String]) -> Bool) -> BPUpgradeResult {
        var results: [BPUpgradeBatchResult] = []
        var stopped = (progress?.isCancelled == true)
        for arguments in batches {
            let batch = BPUpgradeBatchResult()
            batch.arguments = arguments
            batch.status = .unattempted
            if !stopped && progress?.isCancelled != true {
                let succeeded = runner(arguments)
                batch.status = (progress?.isCancelled == true) ? .cancelled : (succeeded ? .succeeded : .failed)
                stopped = (batch.status != .succeeded)
            }
            results.append(batch)
        }
        let result = BPUpgradeResult()
        result.batches = results
        result.cancelled = (progress?.isCancelled == true)
        return result
    }
}

@objc(FormulaeSideBarItem)
public enum FormulaeSideBarItem: UInt {
    @objc(FormulaeSideBarItemFormulaeCategory) case formulaeCategory = 0
    @objc(FormulaeSideBarItemInstalled) case installed = 1
    @objc(FormulaeSideBarItemOutdated) case outdated = 2
    @objc(FormulaeSideBarItemAll) case all = 3
    @objc(FormulaeSideBarItemLeaves) case leaves = 4
    @objc(FormulaeSideBarItemPinned) case pinned = 5
    @objc(FormulaeSideBarItemRepositories) case repositories = 6
    @objc(FormulaeSideBarItemCasksCategory) case casksCategory = 7
    @objc(FormulaeSideBarItemInstalledCasks) case installedCasks = 8
    @objc(FormulaeSideBarItemOutdatedCasks) case outdatedCasks = 9
    @objc(FormulaeSideBarItemAllCasks) case allCasks = 10
    @objc(FormulaeSideBarItemToolsCategory) case toolsCategory = 11
    @objc(FormulaeSideBarItemDoctor) case doctor = 12
    @objc(FormulaeSideBarItemUpdate) case update = 13
    @objc(FormulaeSideBarItemServices) case services = 14
    @objc(FormulaeSideBarItemUnifiedUpdates) case unifiedUpdates = 15
}

@objc(BPFormulaInfoType)
public enum BPFormulaInfoType: Int {
    @objc(kBPFormulaInfoTypeGeneral) case general = 0
    @objc(kBPFormulaInfoTypeInstalledDependents) case installedDependents = 1
    @objc(kBPFormulaInfoTypeAllDependents) case allDependents = 2
}

@objc(BPFormulaeTableAction)
public enum BPFormulaeTableAction: Int {
    @objc(BPFormulaeTableActionNone) case none = 0
    @objc(BPFormulaeTableActionInstall) case install = 1
    @objc(BPFormulaeTableActionUpgrade) case upgrade = 2
    @objc(BPFormulaeTableActionInfo) case info = 3
    @objc(BPFormulaeTableActionUninstall) case uninstall = 4
}

@objc(BPFormulaeTableActions)
public final class BPFormulaeTableActions: NSObject {
    // BPListMode raw constants
    private static let modeAll = 0
    private static let modeInstalled = 1
    private static let modeLeaves = 2
    private static let modeOutdated = 3
    private static let modeSearch = 4
    private static let modeRepositories = 5
    private static let modePinned = 6
    private static let modeInstalledCasks = 7
    private static let modeOutdatedCasks = 8
    private static let modeAllCasks = 9

    // BPFormulaStatus raw constants
    private static let statusNotInstalled = 0
    private static let statusInstalled = 1
    private static let statusOutdated = 2

    // BPFormulaeTableRequest raw constants
    private static let requestPrimary = 0
    private static let requestUninstall = 1

    @objc(actionForRequest:mode:formulae:statuses:)
    public static func action(
        forRequest request: Int,
        mode: Int,
        formulae: [Any]?,
        statuses: [Any]?
    ) -> BPFormulaeTableAction {
        guard let formulae, let statuses,
              !formulae.isEmpty,
              formulae.count == statuses.count,
              mode >= modeAll,
              mode <= modeAllCasks,
              mode != modeRepositories else {
            return .none
        }

        let outdatedList = (mode == modeOutdated || mode == modeOutdatedCasks)
        let installedList = (mode == modeInstalled || mode == modeInstalledCasks || mode == modeLeaves || mode == modePinned)
        let caskList = (mode == modeAllCasks || mode == modeInstalledCasks || mode == modeOutdatedCasks)

        var parsedStatuses: [Int] = []
        parsedStatuses.reserveCapacity(formulae.count)

        for index in 0..<formulae.count {
            guard let formula = bpAsFormula(formulae[index]),
                  let name = formula.name, !name.isEmpty,
                  let number = statuses[index] as? NSNumber else {
                return .none
            }
            let status = number.intValue
            if status < statusNotInstalled || status > statusOutdated
                || (mode != modeSearch && formula.cask != caskList)
                || (outdatedList && status != statusOutdated)
                || (installedList && status == statusNotInstalled) {
                return .none
            }
            parsedStatuses.append(status)
        }

        if request == requestUninstall {
            return (formulae.count == 1 && parsedStatuses[0] != statusNotInstalled) ? .uninstall : .none
        }
        if request != requestPrimary {
            return .none
        }
        if outdatedList {
            return .upgrade
        }
        if formulae.count != 1 {
            return .none
        }
        if mode == modeInstalled || mode == modeInstalledCasks {
            return .info
        }
        if (mode == modeAll || mode == modeAllCasks) && parsedStatuses[0] == statusNotInstalled {
            return .install
        }
        return .none
    }

    @objc(toolbarModeForSidebarRow:selectedCount:selectedFormulaStatus:)
    public static func toolbarMode(
        forSidebarRow sidebarRow: Int,
        selectedCount: UInt,
        selectedFormulaStatus status: Int
    ) -> BPToolbarMode {
        if sidebarRow == Int(FormulaeSideBarItem.repositories.rawValue) {
            return selectedCount > 0 ? .untap : .tap
        }
        if sidebarRow == Int(FormulaeSideBarItem.unifiedUpdates.rawValue) {
            if selectedCount == 0 {
                return .default
            }
            return selectedCount > 1 ? .updateMany : .updateSingle
        }
        if sidebarRow == Int(FormulaeSideBarItem.installedCasks.rawValue)
            || sidebarRow == Int(FormulaeSideBarItem.outdatedCasks.rawValue)
            || sidebarRow == Int(FormulaeSideBarItem.allCasks.rawValue) {
            if selectedCount == 0 {
                return .default
            }
            if sidebarRow == Int(FormulaeSideBarItem.outdatedCasks.rawValue) {
                return selectedCount > 1 ? .updateMany : .updateSingle
            }
            if sidebarRow == Int(FormulaeSideBarItem.allCasks.rawValue) {
                return status == statusNotInstalled ? .install : .uninstall
            }
            return .uninstall
        }
        if selectedCount == 0 || sidebarRow < 0 || sidebarRow > Int(FormulaeSideBarItem.toolsCategory.rawValue) {
            return .default
        }
        if selectedCount > 1 {
            return .updateMany
        }
        switch status {
        case statusInstalled:
            return .uninstall
        case statusOutdated:
            return sidebarRow == Int(FormulaeSideBarItem.outdated.rawValue) ? .updateSingle : .uninstall
        case statusNotInstalled:
            return .install
        default:
            return .default
        }
    }

    @objc(shouldShowFormulaInfoForSidebarRow:)
    public static func shouldShowFormulaInfo(forSidebarRow sidebarRow: Int) -> Bool {
        sidebarRow != Int(FormulaeSideBarItem.repositories.rawValue)
    }

    @objc(footerLocalizationKeyForSidebarRow:searching:)
    public static func footerLocalizationKey(forSidebarRow sidebarRow: Int, searching: Bool) -> String? {
        if searching {
            return "Sidebar_Info_SearchResults"
        }
        return sidebarInfoKey(forRow: sidebarRow)
    }

    @objc(sidebarInfoKeyForRow:)
    public static func sidebarInfoKey(forRow row: Int) -> String? {
        guard row >= 0, let item = FormulaeSideBarItem(rawValue: UInt(row)) else { return nil }
        switch item {
        case .installed:      return "Sidebar_Info_Installed"
        case .outdated:       return "Sidebar_Info_Outdated"
        case .all:            return "Sidebar_Info_All"
        case .leaves:         return "Sidebar_Info_Leaves"
        case .pinned:         return "Sidebar_Info_Pinned"
        case .repositories:   return "Sidebar_Info_Repos"
        case .installedCasks: return "Sidebar_Info_Casks"
        case .outdatedCasks:  return "Sidebar_Info_OutdatedCasks"
        case .allCasks:       return "Sidebar_Info_AllCasks"
        case .doctor:         return "Sidebar_Info_Doctor"
        case .update:         return "Sidebar_Info_Update"
        case .services:       return "Sidebar_Info_Services"
        case .unifiedUpdates: return "Sidebar_Info_Unified_Updates"
        case .formulaeCategory, .casksCategory, .toolsCategory:
            return nil
        }
    }

    @objc(shouldRefreshVisibleListForPublishedMode:activeMode:isLoading:)
    public static func shouldRefreshVisibleList(
        forPublishedMode publishedMode: Int,
        activeMode: Int,
        isLoading: Bool
    ) -> Bool {
        !isLoading && activeMode == publishedMode
    }

    @objc(shouldSyncInstalledHostMetadataForPublishedMode:activeMode:isLoading:isUsingInstalledHost:)
    public static func shouldSyncInstalledHostMetadata(
        forPublishedMode publishedMode: Int,
        activeMode: Int,
        isLoading: Bool,
        isUsingInstalledHost: Bool
    ) -> Bool {
        !isLoading
            && isUsingInstalledHost
            && activeMode != publishedMode
            && (publishedMode == modePinned
                || publishedMode == modeOutdated
                || publishedMode == modeOutdatedCasks)
    }

    @objc(shouldSyncUnifiedUpdatesForPublishedMode:isLoading:isUsingUnifiedUpdatesHost:)
    public static func shouldSyncUnifiedUpdates(
        forPublishedMode publishedMode: Int,
        isLoading: Bool,
        isUsingUnifiedUpdatesHost: Bool
    ) -> Bool {
        !isLoading
            && isUsingUnifiedUpdatesHost
            && (publishedMode == modeOutdated
                || publishedMode == modeOutdatedCasks
                || publishedMode == modePinned)
    }
}

@_silgen_name("objc_sync_enter")
private func bpObjCSyncEnter(_ obj: AnyObject) -> Int32

@_silgen_name("objc_sync_exit")
private func bpObjCSyncExit(_ obj: AnyObject) -> Int32

internal func bpSynchronized<T>(_ obj: AnyObject?, _ body: () throws -> T) rethrows -> T {
    if let obj {
        _ = bpObjCSyncEnter(obj)
    }
    defer {
        if let obj {
            _ = bpObjCSyncExit(obj)
        }
    }
    return try body()
}

private final class BPUTF8StreamRelay: @unchecked Sendable {
    private let lock = NSLock()
    private let accumulated = NSMutableData()
    private let undecoded = NSMutableData()
    private let sink: @Sendable (String) -> Void

    init(sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        accumulated.append(data)
        undecoded.append(data)
        guard let chunk = String(data: undecoded as Data, encoding: .utf8) else {
            return
        }
        undecoded.length = 0
        if !chunk.isEmpty {
            sink(chunk)
        }
    }

    var accumulatedOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: accumulated as Data, encoding: .utf8) ?? ""
    }
}

private enum BPProcessTreeSwift {
    static func descendants(ofProcess pid: pid_t) -> [NSNumber] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", "\(pid)"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()

        do {
            try pgrep.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        var pids: [NSNumber] = []
        for line in output.components(separatedBy: .newlines) {
            if let child = pid_t(line.trimmingCharacters(in: .whitespaces)), child > 0 {
                pids.append(contentsOf: descendants(ofProcess: child))
                pids.append(NSNumber(value: child))
            }
        }
        return pids
    }

    static func terminateProcesses(_ pids: [NSNumber]) {
        for pid in pids {
            Darwin.kill(pid.int32Value, SIGTERM)
        }
    }
}

@objc(BPTaskCompleted)
public protocol BPTaskCompleted: NSObjectProtocol {
    @objc(task:didFinishWithOutput:error:)
    func task(_ task: BPTask, didFinishWithOutput output: String, error: String)
}

@objc(BPTask)
public final class BPTask: NSObject, @unchecked Sendable {
    public static let didBeginBackgroundActivityNotification = Notification.Name("DidBeginBackgroundActivityNotification")
    public static let didEndBackgroundActivityNotification = Notification.Name("DidEndBackgroundActivityNotification")

    @objc public var task: Process?
    @objc public private(set) var output: String = ""
    @objc public private(set) var error: String = ""
    @objc public private(set) var wasCancelled: Bool = false
    @objc public var cancellationProgress: Progress?
    @objc public var updateBlock: (@Sendable (String) -> Void)?
    @objc public weak var delegate: (any BPTaskCompleted)?

    private var activity: NSObjectProtocol?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputFileHandle: FileHandle?
    private var errorFileHandle: FileHandle?
    private var outputRelay: BPUTF8StreamRelay?
    private var errorRelay: BPUTF8StreamRelay?
    private let deliveryQueue = DispatchQueue(label: "com.brunophilipe.Cakebrew.BPTask.Delivery")

    @objc(initWithPath:arguments:)
    public init(path: String?, arguments: [Any]) {
        super.init()
        if let path, !path.isEmpty {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = arguments.compactMap { $0 as? String }
            self.task = proc
        }
    }

    private func makeRelayForwardingToUpdateBlock() -> BPUTF8StreamRelay {
        let queue = self.deliveryQueue
        return BPUTF8StreamRelay { [weak self] chunk in
            let strongSelf = self
            queue.async {
                guard let strongSelf else { return }
                if let update = strongSelf.updateBlock, !chunk.isEmpty {
                    update(chunk)
                }
            }
        }
    }

    private func configurePipes() {
        let outPipe = Pipe()
        let errPipe = Pipe()
        self.outputPipe = outPipe
        self.errorPipe = errPipe
        task?.standardOutput = outPipe
        task?.standardError = errPipe
        task?.standardInput = FileHandle.nullDevice

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        self.outputFileHandle = outHandle
        self.errorFileHandle = errHandle

        let outRelay = makeRelayForwardingToUpdateBlock()
        let errRelay = makeRelayForwardingToUpdateBlock()
        self.outputRelay = outRelay
        self.errorRelay = errRelay

        outHandle.readabilityHandler = { handle in
            outRelay.append(handle.availableData)
        }
        errHandle.readabilityHandler = { handle in
            errRelay.append(handle.availableData)
        }
    }

    private func finishReading() {
        outputFileHandle?.readabilityHandler = nil
        errorFileHandle?.readabilityHandler = nil

        if let remainingOut = outputFileHandle?.readDataToEndOfFile() {
            outputRelay?.append(remainingOut)
        }
        if let remainingErr = errorFileHandle?.readDataToEndOfFile() {
            errorRelay?.append(remainingErr)
        }

        self.output = outputRelay?.accumulatedOutput ?? ""
        self.error = errorRelay?.accumulatedOutput ?? ""
    }

    private func deliverPendingChunks() {
        deliveryQueue.sync {}
    }

    @discardableResult
    @objc public func execute() -> Int32 {
        guard let proc = self.task else {
            cleanup()
            return -1
        }
        configurePipes()
        beginActivity()
        do {
            var cancelledBeforeLaunch = false
            try bpSynchronized(self) {
                try bpSynchronized(self.cancellationProgress) {
                    cancelledBeforeLaunch = self.wasCancelled || (self.cancellationProgress?.isCancelled == true)
                    if cancelledBeforeLaunch {
                        self.wasCancelled = true
                    } else {
                        try proc.run()
                    }
                }
            }
            if cancelledBeforeLaunch {
                cleanup()
                taskDidFinish()
                return -1
            }
            proc.waitUntilExit()
            finishReading()
            deliverPendingChunks()
            let status = proc.terminationStatus
            taskDidFinish()
            return status
        } catch {
            cleanup()
            return -1
        }
    }

    private func taskDidFinish() {
        endActivity()
        delegate?.task(self, didFinishWithOutput: self.output, error: self.error)
    }

    private func beginActivity() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: NSLocalizedString("Homebrew_AppNap_Task_Reason", comment: "")
        )
        NotificationCenter.default.post(name: Self.didBeginBackgroundActivityNotification, object: self)
    }

    private func endActivity() {
        if let act = activity {
            ProcessInfo.processInfo.endActivity(act)
            activity = nil
            NotificationCenter.default.post(name: Self.didEndBackgroundActivityNotification, object: self)
        }
    }

    @objc public func cancel() {
        let runningProc: Process? = bpSynchronized(self) {
            self.wasCancelled = true
            guard let proc = self.task, proc.isRunning else {
                return nil
            }
            return proc
        }
        guard let runningProc else { return }
        let descendants = BPProcessTreeSwift.descendants(ofProcess: runningProc.processIdentifier)
        runningProc.terminate()
        BPProcessTreeSwift.terminateProcesses(descendants)
    }

    @objc public func cleanup() {
        outputFileHandle?.readabilityHandler = nil
        errorFileHandle?.readabilityHandler = nil
        if let proc = self.task, proc.isRunning {
            proc.terminate()
        }
        endActivity()
    }

    deinit {
        updateBlock = nil
        cleanup()
    }
}

@objc(BPHomebrewDiscoveryResult)
public enum BPHomebrewDiscoveryResult: Int, Sendable {
    @objc(BPHomebrewDiscoveryUnknown) case unknown = 0
    @objc(BPHomebrewDiscoveryAvailable) case available = 1
    @objc(BPHomebrewDiscoveryMissing) case missing = 2
    @objc(BPHomebrewDiscoveryInvalidShell) case invalidShell = 3
    @objc(BPHomebrewDiscoveryCheckFailed) case checkFailed = 4
}

@objc(BPBrewTransport)
public enum BPBrewTransport: Int, Sendable {
    @objc(kBPBrewTransportDirect) case direct = 0
    @objc(kBPBrewTransportHelper) case helper = 1
}

@objc(BPListMode)
public enum BPListMode: Int, Sendable {
    @objc(kBPListAll) case all = 0
    @objc(kBPListInstalled) case installed = 1
    @objc(kBPListLeaves) case leaves = 2
    @objc(kBPListOutdated) case outdated = 3
    @objc(kBPListSearch) case search = 4
    @objc(kBPListRepositories) case repositories = 5
    @objc(kBPListPinned) case pinned = 6
    @objc(kBPListInstalledCasks) case installedCasks = 7
    @objc(kBPListOutdatedCasks) case outdatedCasks = 8
    @objc(kBPListAllCasks) case allCasks = 9
}

@objc(BPFormulaDataProvider)
public protocol BPFormulaDataProvider: NSObjectProtocol {
    @objc(informationForFormulaName:)
    func information(forFormulaName name: String?) -> String?

    @objc(informationForCaskName:)
    optional func information(forCaskName name: String?) -> String?
}

@objc(BPFormula)
open class BPFormula: NSObject, NSSecureCoding, NSCopying, BPFormulaObjCBridge, @unchecked Sendable {
    public static let didUpdateNotification = Notification.Name("BPFormulaDidUpdateNotification")

    nonisolated(unsafe) private static var kvoContext: UInt8 = 0

    private static let encodeFormulaName = "BP_ENCODE_FORMULA_NAME"
    private static let encodeFormulaIver = "BP_ENCODE_FORMULA_IVER"
    private static let encodeFormulaLver = "BP_ENCODE_FORMULA_LVER"
    private static let encodeFormulaPath = "BP_ENCODE_FORMULA_PATH"
    private static let encodeFormulaWurl = "BP_ENCODE_FORMULA_WURL"
    private static let encodeFormulaDeps = "BP_ENCODE_FORMULA_DEPS"
    private static let encodeFormulaInst = "BP_ENCODE_FORMULA_INST"
    private static let encodeFormulaCask = "BP_ENCODE_FORMULA_CASK"
    private static let encodeFormulaCnfl = "BP_ENCODE_FORMULA_CNFL"
    private static let encodeFormulaSdsc = "BP_ENCODE_FORMULA_SDSC"
    private static let encodeFormulaInfo = "BP_ENCODE_FORMULA_INFO"
    private static let encodeFormulaOptn = "BP_ENCODE_FORMULA_OPTN"

    private static let identifierDependencies = "==> Dependencies"
    private static let identifierOptions = "==> Options"
    private static let identifierCaveats = "==> Caveats"

    @objc open var name: String?
    @objc open var version: String?
    @objc open var latestVersion: String?
    @objc open var installPath: String?
    @objc open var dependencies: String?
    @objc open var conflicts: String?
    @objc open var shortDescription: String?
    @objc open var information: String?
    @objc open var website: URL?
    @objc open var options: [Any]?
    @objc open var cask: Bool = false
    @objc public var observerAdded: Bool = false
    @objc public var customDataProvider: (any BPFormulaDataProvider)?

    private var isObservingNeedsInformation: Bool = false
    private var isSuppressingNeedsInformationKVO: Bool = false

    @objc dynamic open var needsInformation: Bool = false

    @objc open class var defaultDataProviderClass: AnyClass? {
        nil
    }

    public static var supportsSecureCoding: Bool {
        true
    }

    public required override init() {
        super.init()
    }

    @objc(formulaWithName:version:andLatestVersion:)
    open class func formula(withName name: String?, version: String?, andLatestVersion latestVersion: String?) -> Self {
        let formula = self.init()
        formula.name = name
        formula.version = version
        formula.latestVersion = latestVersion
        formula.commonInit()
        return formula
    }

    @objc(formulaWithName:andVersion:)
    open class func formula(withName name: String?, andVersion version: String?) -> Self {
        return self.formula(withName: name, version: version, andLatestVersion: nil)
    }

    @objc(formulaWithName:)
    open class func formula(withName name: String?) -> Self {
        return self.formula(withName: name, andVersion: nil)
    }

    @objc(namesFromListOutput:)
    open class func names(fromListOutput output: String?) -> [String] {
        guard let output else { return [] }
        let separators = CharacterSet.whitespacesAndNewlines
        return output.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    open func encode(with aCoder: NSCoder) {
        if let name { aCoder.encode(name, forKey: Self.encodeFormulaName) }
        if let version { aCoder.encode(version, forKey: Self.encodeFormulaIver) }
        if let latestVersion { aCoder.encode(latestVersion, forKey: Self.encodeFormulaLver) }
        if let installPath { aCoder.encode(installPath, forKey: Self.encodeFormulaPath) }
        if let website { aCoder.encode(website, forKey: Self.encodeFormulaWurl) }
        if let dependencies { aCoder.encode(dependencies, forKey: Self.encodeFormulaDeps) }
        if let conflicts { aCoder.encode(conflicts, forKey: Self.encodeFormulaCnfl) }
        if let shortDescription { aCoder.encode(shortDescription, forKey: Self.encodeFormulaSdsc) }
        if let information { aCoder.encode(information, forKey: Self.encodeFormulaInfo) }
        if let options { aCoder.encode(options, forKey: Self.encodeFormulaOptn) }
        aCoder.encode(NSNumber(value: isInstalled()), forKey: Self.encodeFormulaInst)
        aCoder.encode(cask, forKey: Self.encodeFormulaCask)
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init()
        self.name = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaName) as String?
        self.version = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaIver) as String?
        self.latestVersion = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaLver) as String?
        self.installPath = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaPath) as String?
        self.website = aDecoder.decodeObject(of: NSURL.self, forKey: Self.encodeFormulaWurl) as URL?
        self.dependencies = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaDeps) as String?
        self.conflicts = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaCnfl) as String?
        self.shortDescription = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaSdsc) as String?
        self.information = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaInfo) as String?
        self.options = aDecoder.decodeObject(of: [NSArray.self, BPFormulaOption.self], forKey: Self.encodeFormulaOptn) as? [Any]
        self.cask = aDecoder.decodeBool(forKey: Self.encodeFormulaCask)
        commonInit()
    }

    @objc open func commonInit() {
        if !isObservingNeedsInformation {
            isObservingNeedsInformation = true
            self.addObserver(self, forKeyPath: "needsInformation", options: [.new], context: &Self.kvoContext)
        }
    }

    open override func addObserver(
        _ observer: NSObject,
        forKeyPath keyPath: String,
        options: NSKeyValueObservingOptions = [],
        context: UnsafeMutableRawPointer?
    ) {
        observerAdded = true
        super.addObserver(observer, forKeyPath: keyPath, options: options, context: context)
    }

    open func copy(with zone: NSZone? = nil) -> Any {
        let formula = type(of: self).init()
        formula.name = self.name
        formula.version = self.version
        formula.latestVersion = self.latestVersion
        formula.installPath = self.installPath
        formula.website = self.website
        formula.dependencies = self.dependencies
        formula.conflicts = self.conflicts
        formula.shortDescription = self.shortDescription
        formula.information = self.information
        formula.options = self.options
        formula.cask = self.cask
        formula.commonInit()
        return formula
    }

    @objc open func installedName() -> String? {
        guard let name else { return nil }
        let nsName = name as NSString
        let slashRange = nsName.range(of: "/", options: .backwards)
        if slashRange.location != NSNotFound {
            return nsName.substring(from: slashRange.location + 1)
        }
        return name
    }

    open override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if context == &Self.kvoContext {
            if let obj = object as? BPFormula, obj === self, keyPath == "needsInformation" {
                if !isSuppressingNeedsInformationKVO && self.needsInformation {
                    _ = getInformation()
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func resetNeedsInformationFlag() {
        isSuppressingNeedsInformationKVO = true
        self.needsInformation = false
        isSuppressingNeedsInformationKVO = false
    }

    private static func lineLooksLikeWebsite(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("://")
    }

    @objc(preprocessedCaskInformation:)
    open class func preprocessedCaskInformation(_ output: String?) -> String? {
        guard let output else { return nil }
        var lines = output.components(separatedBy: "\n")
        guard !lines.isEmpty else { return output }

        var header = lines[0]
        if header.hasPrefix("==> ") {
            header = String(header.dropFirst(4))
        }
        header = header.replacingOccurrences(of: " (auto_updates)", with: "")
        lines[0] = header

        for i in 1..<lines.count {
            let line = lines[i]
            if line == "Installed" || line.hasPrefix("Installed (") {
                lines.remove(at: i)
                break
            }
            if line == "Not installed" {
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    @objc(installLocationFromLines:startingAtIndex:)
    open class func installLocation(fromLines lines: [String]?, startingAtIndex startIndex: UInt) -> String? {
        guard let lines else { return nil }
        let installedVersionsHeading = "==> Installed Versions"
        let start = Int(startIndex)
        guard start >= 0 && start < lines.count else { return nil }

        for index in start..<lines.count {
            let line = lines[index]
            if line.hasPrefix("Aliases:") || line.hasPrefix("From:") || line.hasPrefix("License:") {
                continue
            }
            if line == "Not installed" {
                return nil
            }
            if line.hasPrefix("Installed") {
                if index + 1 < lines.count {
                    for versionIndex in (index + 1)..<lines.count {
                        if lines[versionIndex] != installedVersionsHeading {
                            continue
                        }
                        if versionIndex + 1 < lines.count {
                            for buildIndex in (versionIndex + 1)..<lines.count {
                                let build = lines[buildIndex]
                                if !build.isEmpty {
                                    return build.hasPrefix("==>") ? nil : build
                                }
                            }
                        }
                        return nil
                    }
                }
                return nil
            }
            if line.hasPrefix("==>") {
                return nil
            }
            if line.isEmpty {
                return (index + 1 < lines.count) ? lines[index + 1] : nil
            }
            return line
        }
        return nil
    }

    @discardableResult
    @objc open func getInformation() -> Bool {
        if self.information == nil {
            guard let provider = self.dataProvider() else {
                resetNeedsInformationFlag()
                return false
            }
            let infoSelector = self.cask
                ? NSSelectorFromString("informationForCaskName:")
                : NSSelectorFromString("informationForFormulaName:")
            guard (provider as AnyObject).responds(to: infoSelector) else {
                resetNeedsInformationFlag()
                return false
            }
            let fetchedInfo: String?
            if self.cask {
                fetchedInfo = provider.information?(forCaskName: self.name)
            } else {
                fetchedInfo = provider.information(forFormulaName: self.name)
            }
            guard let fetchedInfo, (fetchedInfo as NSString).range(of: "\n").location != NSNotFound else {
                return false
            }
            self.information = fetchedInfo
        }

        guard var output = self.information else {
            resetNeedsInformationFlag()
            return false
        }

        if output.isEmpty {
            resetNeedsInformationFlag()
            return true
        }

        if output.hasPrefix("Error") {
            NSLog("Error parsing formula with name: %@", self.name ?? "")
            resetNeedsInformationFlag()
            self.information = nil
            self.latestVersion = nil
            self.version = nil
            self.shortDescription = nil
            return true
        }

        if self.cask, let preprocessed = Self.preprocessedCaskInformation(output) {
            output = preprocessed
        }

        var lines = output.components(separatedBy: "\n")
        if !lines.isEmpty && lines[0].hasPrefix("==> ") {
            lines[0] = String(lines[0].dropFirst(4))
        }

        parseInformationBody(lines: lines, output: output)

        resetNeedsInformationFlag()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
        return true
    }

    private func parseInformationBody(lines: [String], output: String) {
        guard !lines.isEmpty else { return }
        let line0 = lines[0] as NSString
        let colonRange = line0.range(of: ":")
        guard colonRange.location != NSNotFound, colonRange.location + 2 <= line0.length else {
            return
        }
        self.latestVersion = line0.substring(from: colonRange.location + 2)

        var lineIndex = 1
        guard lineIndex < lines.count else { return }
        var line = lines[lineIndex]

        if Self.lineLooksLikeWebsite(line) {
            self.website = URL(string: line)
        } else {
            self.shortDescription = line
            lineIndex = 2
            guard lineIndex < lines.count else { return }
            line = lines[lineIndex]
            self.website = URL(string: line)
        }

        lineIndex += 1
        guard lineIndex < lines.count else { return }
        line = lines[lineIndex]
        if (line as NSString).range(of: "Conflicts with:").location != NSNotFound {
            if line == "Conflicts with:" {
                var conflictList: [String] = []
                repeat {
                    lineIndex += 1
                    guard lineIndex < lines.count else { return }
                    line = lines[lineIndex]
                    if line.hasPrefix("  ") {
                        conflictList.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } while line.hasPrefix("  ")
                self.conflicts = conflictList.joined(separator: ", ")
            } else {
                let nsLine = line as NSString
                guard 16 <= nsLine.length else { return }
                self.conflicts = nsLine.substring(from: 16)
                lineIndex += 1
            }
        }

        self.installPath = Self.installLocation(fromLines: lines, startingAtIndex: UInt(max(0, lineIndex)))

        let nsOutput = output as NSString
        var rangeDeps = nsOutput.range(of: Self.identifierDependencies)
        let rangeOpts = nsOutput.range(of: Self.identifierOptions)
        var rangeCvts = nsOutput.range(of: Self.identifierCaveats)

        if rangeDeps.location != NSNotFound {
            let startLoc = rangeDeps.length + rangeDeps.location + 1
            let depLen: Int
            if rangeOpts.location != NSNotFound {
                depLen = rangeOpts.location - startLoc
            } else if rangeCvts.location != NSNotFound {
                depLen = rangeCvts.location - startLoc
            } else {
                depLen = nsOutput.length - startLoc
            }
            guard startLoc >= 0, depLen >= 0, startLoc + depLen <= nsOutput.length else {
                return
            }
            rangeDeps = NSRange(location: startLoc, length: depLen)
            var deps: [String] = []
            let finishedTitle = NSLocalizedString("Homebrew_Task_Finished", comment: "")
            nsOutput.enumerateSubstrings(in: rangeDeps, options: .byLines) { substring, _, _, _ in
                if let substring, (substring as NSString).range(of: finishedTitle).location == NSNotFound {
                    deps.append(substring)
                }
            }
            self.dependencies = deps.joined(separator: "; ")
        } else {
            self.dependencies = nil
        }

        if rangeOpts.location != NSNotFound {
            let startLoc = rangeOpts.length + rangeOpts.location + 1
            guard startLoc >= 0, startLoc <= nsOutput.length else { return }
            var optionsString = nsOutput.substring(from: startLoc) as NSString
            var parsedOptions: [BPFormulaOption] = []
            rangeCvts = optionsString.range(of: Self.identifierCaveats)
            if rangeCvts.location != NSNotFound {
                optionsString = optionsString.substring(to: rangeCvts.location) as NSString
            }
            var currentOption: BPFormulaOption?
            (optionsString as String).enumerateLines { optLine, stop in
                if optLine.hasPrefix("--") {
                    let opt = BPFormulaOption()
                    opt.name = optLine
                    currentOption = opt
                } else if let opt = currentOption {
                    opt.explanation = optLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    parsedOptions.append(opt)
                    currentOption = nil
                } else {
                    stop = true
                }
            }
            self.options = parsedOptions
        } else {
            self.options = nil
        }
    }

    @objc open func isInstalled() -> Bool {
        guard let mgr = bpSharedHomebrewManager() else { return false }
        return mgr.status(forFormula: self) != 0
    }

    @objc open func isOutdated() -> Bool {
        guard let mgr = bpSharedHomebrewManager() else { return false }
        return mgr.status(forFormula: self) == 2
    }

    open override var description: String {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        return "\(NSStringFromClass(type(of: self))) <\(ptr)> name:\(name ?? "(null)") version:\(version ?? "(null)") latestVerson:\(latestVersion ?? "(null)")"
    }

    @objc open var shortLatestVersion: String? {
        guard let latestVersion else { return nil }
        let components = latestVersion.components(separatedBy: " ")
        if components.count == 3 || components.count == 4 {
            return components[1]
        }
        return latestVersion
    }

    @objc open func dataProvider() -> (any BPFormulaDataProvider)? {
        if let customDataProvider {
            return customDataProvider
        }
        if let providerClass = type(of: self).defaultDataProviderClass as? NSObject.Type {
            return providerClass.init() as? any BPFormulaDataProvider
        }
        return bpSharedHomebrewInterface() as? any BPFormulaDataProvider
    }

    deinit {
        if isObservingNeedsInformation {
            super.removeObserver(self, forKeyPath: "needsInformation", context: &Self.kvoContext)
        }
    }
}

@objc(BPCustomFormula)
public final class BPCustomFormula: BPFormula, @unchecked Sendable {
    public override class var defaultDataProviderClass: AnyClass? {
        NSClassFromString("BPFormulaTestDataProvider")
    }
}

@objc(BPInformationCachedFormula)
public final class BPInformationCachedFormula: BPFormula, @unchecked Sendable {
    public override var information: String? {
        get { "cached mock information" }
        set { super.information = newValue }
    }
}

@objc(BPModernFormula)
public final class BPModernFormula: BPFormula, @unchecked Sendable {
    public override class var defaultDataProviderClass: AnyClass? {
        NSClassFromString("BPModernInfoDataProvider")
    }
}

@objc(BPCompatFormula)
public final class BPCompatFormula: BPFormula, @unchecked Sendable {
    @objc public var provider: (any BPFormulaDataProvider)? {
        get { customDataProvider }
        set { customDataProvider = newValue }
    }
}

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

@objc private protocol BPHelperClientClassBridge: NSObjectProtocol {
    @objc(sharedClient)
    func sharedClient() -> AnyObject?
}

@objc private protocol BPHelperClientInstanceBridge: NSObjectProtocol {
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
private func bpSharedHelperClient() -> BPHelperClientInstanceBridge? {
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

@objc(BPHomebrewInterface)
open class BPHomebrewInterface: NSObject, BPFormulaDataProvider, BPTaskCompleted, @unchecked Sendable {
    private static let cakebrewOutputIdentifier = "+++++Cakebrew+++++"
    private static let kDebugWarningFormat = "User Shell: %@\nCommand: %@\nOS X Version: %@\n\nThe outputs are going to be different if run from Xcode!!\nInstalling and upgrading formulas is not advised in DEBUG mode!\n\n"

    #if DEBUG
    nonisolated(unsafe) private static var sTestingSharedInterface: BPHomebrewInterface?
    #endif
    nonisolated(unsafe) private static var sDefaultSharedInterface: BPHomebrewInterface?

    // All stored properties have zero-byte defaults so class_createInstance(Cls, 0) works safely.
    @objc public weak var delegate: (any BPHomebrewInterfaceDelegate)?
    @objc public var brewTransport: BPBrewTransport = .direct
    private var _pathShellStorage: NSString?
    private var _tasksStorage: NSMutableDictionary?
    private var _taskOperationsQueueStorage: DispatchQueue?
    private var _currentOperationTaskStorage: BPTask?

    @objc public var path_shell: String? {
        get { _pathShellStorage as String? }
        set { _pathShellStorage = (newValue as NSString?)?.copy() as? NSString }
    }

    @objc public var currentOperationTask: BPTask? {
        get { _currentOperationTaskStorage }
        set { _currentOperationTaskStorage = newValue }
    }

    @objc public var tasks: NSMutableDictionary {
        get {
            bpSynchronized(self) {
                if let existing = _tasksStorage {
                    return existing
                }
                let created = NSMutableDictionary()
                _tasksStorage = created
                return created
            }
        }
        set {
            bpSynchronized(self) {
                _tasksStorage = newValue
            }
        }
    }

    @objc public var taskOperationsQueue: DispatchQueue {
        get {
            bpSynchronized(self) {
                if let existing = _taskOperationsQueueStorage {
                    return existing
                }
                let created = DispatchQueue(
                    label: "com.brunophilipe.Cakebrew.BPHomebrewInterface.Tasks",
                    qos: .userInitiated,
                    attributes: .concurrent
                )
                _taskOperationsQueueStorage = created
                return created
            }
        }
        set {
            bpSynchronized(self) {
                _taskOperationsQueueStorage = newValue
            }
        }
    }

    #if DEBUG
    @objc(setSharedInterfaceForTesting:)
    public class func setSharedInterfaceForTesting(_ interface: BPHomebrewInterface?) {
        bpSynchronized(self) {
            sTestingSharedInterface = interface
        }
    }
    #endif

    @objc public class func sharedInterface() -> BPHomebrewInterface {
        bpSynchronized(self) {
            #if DEBUG
            if let testing = sTestingSharedInterface {
                return testing
            }
            #endif
            if let existing = sDefaultSharedInterface {
                return existing
            }
            let instance: BPHomebrewInterface
            if ProcessInfo.processInfo.arguments.contains("-BPMockBrew"),
               let mockClass = NSClassFromString("BPMockHomebrewInterface") as? BPHomebrewInterface.Type {
                instance = mockClass.init(uniqueInstance: ())
            } else {
                instance = BPHomebrewInterface(uniqueInstance: ())
            }
            sDefaultSharedInterface = instance
            return instance
        }
    }

    @objc(initUniqueInstance)
    public required init(uniqueInstance: Void = ()) {
        super.init()
        _tasksStorage = NSMutableDictionary()
        _taskOperationsQueueStorage = DispatchQueue(
            label: "com.brunophilipe.Cakebrew.BPHomebrewInterface.Tasks",
            qos: .userInitiated,
            attributes: .concurrent
        )
        brewTransport = Self.defaultTransport(whenSandboxed: Self.isRunningSandboxed())
    }

    public override init() {
        super.init()
        _tasksStorage = NSMutableDictionary()
        _taskOperationsQueueStorage = DispatchQueue(
            label: "com.brunophilipe.Cakebrew.BPHomebrewInterface.Tasks",
            qos: .userInitiated,
            attributes: .concurrent
        )
        brewTransport = Self.defaultTransport(whenSandboxed: Self.isRunningSandboxed())
    }

    @objc open func cleanup() {
        let dict = self.tasks
        let snapshot: [BPTask] = bpSynchronized(dict) {
            (dict.allValues as? [BPTask]) ?? []
        }
        for task in snapshot {
            task.cleanup()
        }
    }

    @objc open func cancelAllRunningTasks() {
        let dict = self.tasks
        let snapshot: [BPTask] = bpSynchronized(dict) {
            (dict.allValues as? [BPTask]) ?? []
        }
        for task in snapshot {
            task.cancel()
        }
        currentOperationTask?.cancel()
    }

    @objc open func cancelCurrentOperation() {
        if brewTransport == .helper {
            bpSharedHelperClient()?.cancelCurrentCommand()
            return
        }
        currentOperationTask?.cancel()
    }

    @objc open var hasCancellableOperation: Bool {
        if brewTransport == .helper {
            return true
        }
        return currentOperationTask != nil
    }

    @objc public class func installationURL() -> URL {
        URL(string: "https://brew.sh")!
    }

    @objc(discoveryResultForOutput:exitStatus:)
    public class func discoveryResult(forOutput output: String?, exitStatus status: Int32) -> BPHomebrewDiscoveryResult {
        guard let output else { return .checkFailed }
        let start = output.components(separatedBy: "+++++Cakebrew Discovery+++++\n")
        guard start.count == 2, let last = start.last else { return .checkFailed }
        let end = last.components(separatedBy: "+++++Cakebrew Discovery End+++++\n")
        guard end.count == 2, let first = end.first else { return .checkFailed }
        let path = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 1 && path.isEmpty {
            return .missing
        }
        let nsPath = path as NSString
        if status != 0 || !nsPath.isAbsolutePath || nsPath.rangeOfCharacter(from: .newlines).location != NSNotFound {
            return .checkFailed
        }
        var directory: ObjCBool = false
        let files = FileManager.default
        let isExec = files.fileExists(atPath: path, isDirectory: &directory)
            && !directory.boolValue
            && files.isExecutableFile(atPath: path)
        return isExec ? .available : .checkFailed
    }

    @objc open func discoverHomebrew() -> BPHomebrewDiscoveryResult {
        self.path_shell = getValidUserShellPath()
        guard let shell = self.path_shell else { return .invalidShell }
        let command = "printf '\\n+++++Cakebrew Discovery+++++\\n'; command -v brew; cakebrew_status=$?; printf '+++++Cakebrew Discovery End+++++\\n'; exit \"$cakebrew_status\""
        let task = BPTask(path: shell, arguments: ["-l", "-c", command])
        let status = task.execute()
        return Self.discoveryResult(forOutput: task.output, exitStatus: status)
    }

    @objc open func getValidUserShellPath() -> String? {
        guard let userShell = ProcessInfo.processInfo.environment["SHELL"], !userShell.isEmpty else {
            return nil
        }
        var isValidShell = false
        if let shellsContent = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) {
            for validShell in shellsContent.components(separatedBy: .newlines) {
                if validShell.trimmingCharacters(in: .whitespacesAndNewlines) == userShell {
                    isValidShell = true
                    break
                }
            }
        }
        guard isValidShell, FileManager.default.isExecutableFile(atPath: userShell) else {
            return nil
        }
        #if DEBUG
        NSLog("shell: %@", userShell)
        #endif
        return userShell
    }

    @objc(formatArguments:sendOutputId:)
    open func formatArguments(_ extraArguments: [Any]?, sendOutputId sendOutputID: Bool) -> [Any] {
        let command = sendOutputID
            ? "echo \"\(Self.cakebrewOutputIdentifier)\";brew \"$@\""
            : "brew \"$@\""
        var arguments: [Any] = ["-l", "-c", command, "brew"]
        if let extraArguments {
            arguments.append(contentsOf: extraArguments)
        }
        return arguments
    }

    @objc(task:didFinishWithOutput:error:)
    open func task(_ task: BPTask, didFinishWithOutput output: String, error: String) {
        let dict = self.tasks
        let key = String(format: "%p", Int(bitPattern: Unmanaged.passUnretained(task).toOpaque()))
        bpSynchronized(dict) {
            dict.removeObject(forKey: key)
        }
    }

    @objc(formatAutoremoveArguments:)
    open func formatAutoremoveArguments(_ arguments: [Any]) -> [Any] {
        var result: [Any] = [
            "-l",
            "-c",
            "printf '\\n+++++Cakebrew Autoremove+++++\\n'; /usr/bin/env HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew \"$@\"",
            "brew"
        ]
        result.append(contentsOf: arguments)
        return result
    }

    @objc(executeAutoremoveArguments:progress:output:)
    open func executeAutoremoveArguments(
        _ arguments: [Any],
        progress: Progress?,
        output: (@Sendable (String) -> Void)?
    ) -> Int32 {
        guard brewTransport == .direct, let shell = path_shell, progress?.isCancelled != true else {
            return -1
        }
        let task = BPTask(path: shell, arguments: formatAutoremoveArguments(arguments))
        task.delegate = self
        let preview = (arguments.first as? String) == "autoremove"
        task.updateBlock = preview ? nil : output
        task.cancellationProgress = progress
        progress?.cancellationHandler = {
            DispatchQueue.global(qos: .userInitiated).async {
                task.cancel()
            }
        }
        if progress?.isCancelled == true {
            task.cancel()
        }
        let dict = self.tasks
        let key = String(format: "%p", Int(bitPattern: Unmanaged.passUnretained(task).toOpaque()))
        bpSynchronized(dict) {
            dict[key] = task
        }
        let status = task.execute()
        progress?.cancellationHandler = nil
        task.cancellationProgress = nil
        if preview {
            let nsOut = task.output as NSString
            let marker = nsOut.range(of: "+++++Cakebrew Autoremove+++++\n")
            let clean = marker.location == NSNotFound
                ? task.output
                : nsOut.substring(from: marker.location + marker.length)
            if let output {
                let sep = task.error.isEmpty ? "" : "\n"
                output("\(clean)\(sep)\(task.error)")
            }
            if marker.location == NSNotFound {
                return -1
            }
        }
        return status
    }

    @objc(previewAutoremoveWithProgress:)
    open func previewAutoremove(withProgress progress: Progress?) -> BPAutoremovePreview {
        if brewTransport != .direct {
            return BPAutoremovePreview.preview(
                withOutput: NSLocalizedString(
                    "Unused dependency removal requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.",
                    comment: ""
                ),
                succeeded: false
            )
        }
        nonisolated(unsafe) let raw = NSMutableString()
        let status = executeAutoremoveArguments(["autoremove", "--dry-run"], progress: progress) { chunk in
            raw.append(chunk)
        }
        return BPAutoremovePreview.preview(
            withOutput: raw as String,
            succeeded: status == 0 && progress?.isCancelled != true
        )
    }

    @objc(removeUnusedFormulae:progress:output:)
    open func removeUnusedFormulae(
        _ names: [String]?,
        progress: Progress?,
        output: (@Sendable (String) -> Void)?
    ) -> Bool {
        let count = names?.count ?? 0
        let suffix = count == 1 ? "" : "e"
        let header = String(format: "==> Would autoremove %lu unneeded formula%@:\n", UInt(count), suffix)
        let body = (names ?? []).joined(separator: "\n")
        let validated = BPAutoremovePreview.preview(withOutput: header + body, succeeded: true)
        guard validated.valid, count > 0, progress?.isCancelled != true, brewTransport == .direct else {
            return false
        }
        let args: [Any] = ["uninstall", "--formula"] + validated.names
        let status = executeAutoremoveArguments(args, progress: progress, output: output)
        output?(String(format: NSLocalizedString("\nHomebrew exit status: %d\n", comment: ""), status))
        return status == 0 && progress?.isCancelled != true
    }

    @objc(performBrewCommandWithArguments:dataReturnBlock:)
    open func performBrewCommand(
        withArguments arguments: [Any]?,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(withArguments: arguments, wrapsSynchronousRequest: false, dataReturnBlock: block)
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(
            withArguments: arguments,
            wrapsSynchronousRequest: isSynchronous,
            progress: nil,
            dataReturnBlock: block
        )
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:progress:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        progress: Progress?,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(
            withArguments: arguments,
            wrapsSynchronousRequest: isSynchronous,
            progress: progress,
            includesCompletionMessage: true,
            dataReturnBlock: block
        )
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:includesCompletionMessage:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        includesCompletionMessage: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(
            withArguments: arguments,
            wrapsSynchronousRequest: isSynchronous,
            progress: nil,
            includesCompletionMessage: includesCompletionMessage,
            dataReturnBlock: block
        )
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:progress:includesCompletionMessage:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        progress: Progress?,
        includesCompletionMessage: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        if brewTransport == .helper {
            guard let client = bpSharedHelperClient() else { return false }
            return client.runBrew(
                withArguments: arguments ?? [],
                outputMarker: isSynchronous ? Self.cakebrewOutputIdentifier : nil,
                outputBlock: block
            )
        }

        let formattedArgs = formatArguments(arguments, sendOutputId: isSynchronous)
        guard let shell = path_shell, !formattedArgs.isEmpty else {
            return false
        }

        let task = BPTask(path: shell, arguments: formattedArgs)
        task.delegate = self
        task.updateBlock = block
        if let progress {
            task.cancellationProgress = progress
            progress.cancellationHandler = {
                DispatchQueue.global(qos: .userInitiated).async {
                    task.cancel()
                }
            }
            if progress.isCancelled {
                task.cancel()
            }
        }

        if !isSynchronous {
            currentOperationTask = task
        }

        let dict = self.tasks
        let key = String(format: "%p", Int(bitPattern: Unmanaged.passUnretained(task).toOpaque()))
        bpSynchronized(dict) {
            dict[key] = task
        }

        #if DEBUG
        if !isSynchronous {
            let joined = formattedArgs.compactMap { $0 as? String }.joined(separator: " ")
            let warning = String(
                format: Self.kDebugWarningFormat,
                shell,
                joined,
                ProcessInfo.processInfo.operatingSystemVersionString
            )
            invokeOutputBlock(block, withString: warning)
        }
        #endif

        let status = task.execute()
        progress?.cancellationHandler = nil
        task.cancellationProgress = nil

        if currentOperationTask === task {
            currentOperationTask = nil
        }

        let taskDoneString = String(
            format: "%@: (%d) %@ %@!",
            NSLocalizedString("Homebrew_Task_Finished", comment: ""),
            status,
            NSLocalizedString("Homebrew_Task_Finished_At", comment: ""),
            DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        )
        if includesCompletionMessage {
            invokeOutputBlock(block, withString: taskDoneString)
        }

        return status == 0
    }

    @objc(invokeOutputBlock:withString:)
    open func invokeOutputBlock(_ block: ((String) -> Void)?, withString string: String) {
        block?(string)
    }

    @objc open func isRunningBackgroundTask() -> Bool {
        let dict = self.tasks
        return bpSynchronized(dict) {
            dict.count > 0
        }
    }

    @objc(performSyncBrewCommandWithArguments:)
    open func performSyncBrewCommand(withArguments arguments: [Any]?) -> String? {
        var finalOutput: String?
        let queue = self.taskOperationsQueue
        queue.sync {
            nonisolated(unsafe) let output = NSMutableString()
            _ = self.performAsyncBrewCommand(withArguments: arguments, wrapsSynchronousRequest: true) { partialOutput in
                output.append(partialOutput)
            }
            finalOutput = output.copy() as? String
        }
        return removeLoginShellOutput(fromString: finalOutput)
    }

    @objc(defaultTransportWhenSandboxed:)
    public class func defaultTransport(whenSandboxed sandboxed: Bool) -> BPBrewTransport {
        sandboxed ? .helper : .direct
    }

    @objc public class func isRunningSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    @objc(isValidTapName:)
    public class func isValidTapName(_ name: String?) -> Bool {
        guard let name else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"
        let nsTrimmed = trimmed as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return regex.numberOfMatches(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length)) == 1
    }

    @objc open func listPinnedCasks() -> [BPFormula]? {
        let call = BPHomebrewInterfaceListCallPinnedCasks()
        var output: NSString?
        let succeeded = performCleanReadOnlyBrewCommand(withArguments: call.arguments, output: &output)
        guard succeeded, let output else { return nil }
        return call.parseData(output as String)
    }

    @objc(listMode:)
    open func listMode(_ mode: BPListMode) -> [BPFormula]? {
        let listCall: BPHomebrewInterfaceListCall
        switch mode {
        case .installed:
            listCall = BPHomebrewInterfaceListCallInstalled()
        case .all:
            listCall = BPHomebrewInterfaceListCallAll()
        case .leaves:
            listCall = BPHomebrewInterfaceListCallLeaves()
        case .outdated:
            listCall = BPHomebrewInterfaceListCallUpgradeable()
        case .repositories:
            listCall = BPHomebrewInterfaceListCallRepositories()
        case .pinned:
            listCall = BPHomebrewInterfaceListCallPinned()
        case .installedCasks:
            listCall = BPHomebrewInterfaceListCallInstalledCasks()
        case .outdatedCasks:
            listCall = BPHomebrewInterfaceListCallOutdatedCasks()
        case .allCasks:
            listCall = BPHomebrewInterfaceListCallAllCasks()
        default:
            return nil
        }

        if mode == .outdated || mode == .outdatedCasks || mode == .pinned {
            var output: NSString?
            let succeeded = performCleanReadOnlyBrewCommand(withArguments: listCall.arguments, output: &output)
            guard succeeded, let output else { return nil }
            return listCall.parseData(output as String)
        }

        guard let string = performSyncBrewCommand(withArguments: listCall.arguments) else {
            return nil
        }
        return listCall.parseData(string)
    }

    @objc(informationForFormulaName:)
    open func information(forFormulaName name: String?) -> String? {
        guard let name else { return nil }
        return performSyncBrewCommand(withArguments: ["info", name])
    }

    @objc(listModeForRemovalRefresh:)
    open func listMode(forRemovalRefresh mode: BPListMode) -> [BPFormula]? {
        guard brewTransport == .direct else { return nil }
        let listCall: BPHomebrewInterfaceListCall
        switch mode {
        case .installed:
            listCall = BPHomebrewInterfaceListCallInstalled()
        case .leaves:
            listCall = BPHomebrewInterfaceListCallLeaves()
        case .outdated:
            listCall = BPHomebrewInterfaceListCallUpgradeable()
        default:
            return nil
        }
        var output: NSString?
        guard performCleanReadOnlyBrewCommand(withArguments: listCall.arguments, output: &output),
              let output else {
            return nil
        }
        return listCall.parseData(output as String)
    }

    @objc open func listServicesForRemovalRefresh() -> [BPService]? {
        guard brewTransport == .direct else { return nil }
        var output: NSString?
        guard performCleanReadOnlyBrewCommand(withArguments: ["services", "list", "--json"], output: &output) else {
            return nil
        }
        return BPService.validatedServices(fromJSONString: output as String?)
    }

    @objc(informationForCaskName:)
    open func information(forCaskName name: String?) -> String? {
        guard let name else { return nil }
        return performSyncBrewCommand(withArguments: ["info", "--cask", name])
    }

    @objc(serviceDetailsForName:)
    open func serviceDetails(forName name: String?) -> BPServiceDetails {
        guard let name, !name.isEmpty, !name.hasPrefix("-") else {
            return BPServiceDetails.details(forName: name, output: "", succeeded: false)
        }
        if brewTransport == .helper {
            return BPServiceDetails.details(
                forName: name,
                output: NSLocalizedString("Services_Details_Helper_Unavailable", comment: ""),
                succeeded: false
            )
        }
        var output: NSString?
        let succeeded = performCleanReadOnlyBrewCommand(
            withArguments: ["services", "info", "--json", name],
            output: &output
        )
        return BPServiceDetails.details(forName: name, output: output as String?, succeeded: succeeded)
    }

    @objc(performCleanReadOnlyBrewCommandWithArguments:output:)
    open func performCleanReadOnlyBrewCommand(
        withArguments arguments: [Any]?,
        output result: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        var succeeded = false
        var transcript: String?
        let queue = self.taskOperationsQueue
        queue.sync {
            nonisolated(unsafe) let output = NSMutableString()
            succeeded = self.performAsyncBrewCommand(
                withArguments: arguments,
                wrapsSynchronousRequest: true,
                includesCompletionMessage: false
            ) { chunk in
                output.append(chunk)
            }
            transcript = self.removeLoginShellOutput(fromString: output as String)
        }
        result?.pointee = transcript as NSString?
        return succeeded
    }

    @objc open func listServices() -> [BPService] {
        if brewTransport == .direct {
            var output: NSString?
            let succeeded = performCleanReadOnlyBrewCommand(
                withArguments: ["services", "list", "--json"],
                output: &output
            )
            return succeeded ? BPService.services(fromJSONString: output as String?) : []
        }
        let output = performSyncBrewCommand(withArguments: ["services", "list", "--json"])
        return output != nil ? BPService.services(fromJSONString: output) : []
    }

    @objc(startService:withReturnBlock:)
    open func startService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let name else { return false }
        return performBrewCommand(withArguments: ["services", "start", name], dataReturnBlock: block)
    }

    @objc(stopService:withReturnBlock:)
    open func stopService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let name else { return false }
        return performBrewCommand(withArguments: ["services", "stop", name], dataReturnBlock: block)
    }

    @objc(restartService:withReturnBlock:)
    open func restartService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let name else { return false }
        return performBrewCommand(withArguments: ["services", "restart", name], dataReturnBlock: block)
    }

    @objc(dependantsForFormulaName:onlyInstalled:)
    open func dependants(forFormulaName name: String?, onlyInstalled: Bool) -> String? {
        guard let name else { return nil }
        var arguments = ["uses"]
        if onlyInstalled {
            arguments.append("--installed")
        }
        arguments.append(name)
        return performSyncBrewCommand(withArguments: arguments)
    }

    @objc(removeLoginShellOutputFromString:)
    open func removeLoginShellOutput(fromString string: String?) -> String? {
        guard let string else { return nil }
        let nsString = string as NSString
        let range = nsString.range(of: Self.cakebrewOutputIdentifier)
        if range.location != NSNotFound && range.location + range.length + 1 <= nsString.length {
            return nsString.substring(from: range.location + range.length + 1)
        }
        return string
    }

    @objc(updateWithReturnBlock:)
    open func update(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(withArguments: ["update"], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "update")
        return val
    }

    private class func upgradeArguments(withPrefix prefix: [String], names: [Any]?) -> [String] {
        var arguments = prefix
        if let names {
            for raw in names {
                if let name = raw as? String {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        arguments.append(trimmed)
                    }
                }
            }
        }
        return arguments
    }

    @objc(argumentsForUpgradingFormulae:)
    public class func arguments(forUpgradingFormulae formulae: [Any]?) -> [String] {
        upgradeArguments(withPrefix: ["upgrade"], names: formulae)
    }

    @objc(argumentsForUpgradingCasks:)
    public class func arguments(forUpgradingCasks casks: [Any]?) -> [String] {
        upgradeArguments(withPrefix: ["upgrade", "--cask"], names: casks)
    }

    @objc(upgradeFormulae:withReturnBlock:)
    open func upgradeFormulae(_ formulae: [Any]?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(
            withArguments: Self.arguments(forUpgradingFormulae: formulae),
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "upgrade")
        return val
    }

    @objc(upgradeSelectedFormulae:progress:withReturnBlock:)
    open func upgradeSelectedFormulae(
        _ formulae: [BPFormula]?,
        progress: Progress?,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        upgradeSelectionReporting(formulae, progress: progress, withReturnBlock: block).succeeded
    }

    @objc(upgradeSelectionReporting:progress:withReturnBlock:)
    open func upgradeSelectionReporting(
        _ formulae: [BPFormula]?,
        progress: Progress?,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> BPUpgradeResult {
        let plan = BPUpgradePlan(selection: formulae)
        var attempted = false
        let result = plan.executeReporting(withProgress: progress) { [weak self] arguments in
            guard let self else { return false }
            attempted = true
            return self.performAsyncBrewCommand(
                withArguments: arguments,
                wrapsSynchronousRequest: false,
                progress: progress,
                dataReturnBlock: block
            )
        }
        if attempted {
            sendDelegateFormulaeUpdatedCall(forCommand: "upgrade")
        }
        return result
    }

    @objc(upgradeCasks:withReturnBlock:)
    open func upgradeCasks(_ casks: [Any]?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(
            withArguments: Self.arguments(forUpgradingCasks: casks),
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "upgrade")
        return val
    }

    @objc(installFormula:withOptions:andReturnBlock:)
    open func installFormula(
        _ formula: String?,
        withOptions options: [Any]?,
        andReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        guard let formula else { return false }
        var params: [Any] = ["install", formula]
        if let options {
            params.append(contentsOf: options)
        }
        let val = performBrewCommand(withArguments: params, dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "install")
        return val
    }

    @objc(installCask:withReturnBlock:)
    open func installCask(_ cask: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let cask else { return false }
        let val = performBrewCommand(withArguments: ["install", "--cask", cask], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "install")
        return val
    }

    @objc(uninstallFormula:withReturnBlock:)
    open func uninstallFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let formula else { return false }
        let val = performBrewCommand(withArguments: ["uninstall", formula], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "uninstall")
        return val
    }

    @objc(argumentsForUninstallingCask:zap:)
    public class func arguments(forUninstallingCask cask: String?, zap: Bool) -> [String] {
        var arguments = ["uninstall", "--cask"]
        if zap {
            arguments.append("--zap")
        }
        if let token = cask?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            arguments.append(token)
        }
        return arguments
    }

    @objc(uninstallCask:withReturnBlock:)
    open func uninstallCask(_ cask: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        uninstallCask(cask, zap: false, withReturnBlock: block)
    }

    @objc(uninstallCask:zap:withReturnBlock:)
    open func uninstallCask(
        _ cask: String?,
        zap: Bool,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        let val = performBrewCommand(
            withArguments: Self.arguments(forUninstallingCask: cask, zap: zap),
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "uninstall")
        return val
    }

    @objc(tapRepository:withReturnsBlock:)
    open func tapRepository(_ repository: String?, withReturnsBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let repository else { return false }
        let val = performBrewCommand(withArguments: ["tap", repository], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "tap")
        return val
    }

    @objc(untapRepository:withReturnsBlock:)
    open func untapRepository(_ repository: String?, withReturnsBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let repository else { return false }
        let val = performBrewCommand(withArguments: ["untap", repository], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "untap")
        return val
    }

    @objc(pinFormula:withReturnBlock:)
    open func pinFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let formula else { return false }
        let val = performBrewCommand(withArguments: ["pin", formula], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "pin")
        return val
    }

    @objc(unpinFormula:withReturnBlock:)
    open func unpinFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let formula else { return false }
        let val = performBrewCommand(withArguments: ["unpin", formula], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "unpin")
        return val
    }

    @objc(runCleanupWithReturnBlock:)
    open func runCleanup(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        performBrewCommand(withArguments: ["cleanup"], dataReturnBlock: block)
    }

    @objc public class func argumentsForCleanupDryRun() -> [String] {
        ["cleanup", "--dry-run"]
    }

    @objc open func previewCleanup() -> BPCleanupPreview {
        let output = performSyncBrewCommand(withArguments: Self.argumentsForCleanupDryRun())
        return BPCleanupPreview.preview(fromOutput: output)
    }

    @objc(runDoctorWithReturnBlock:)
    open func runDoctor(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(withArguments: ["doctor"], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "doctor")
        return val
    }

    @objc(runBrewExportToolWithPath:)
    open func runBrewExportTool(withPath path: String?) -> NSError? {
        guard let path else {
            return NSError(
                domain: "Cakebrew.Brewfile.Export",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        "Homebrew could not export the Brewfile. Check the destination and try again.",
                        comment: ""
                    )
                ]
            )
        }
        nonisolated(unsafe) let output = NSMutableString()
        let succeeded = performAsyncBrewCommand(
            withArguments: ["bundle", "dump", "--force", "--file=\(path)"],
            wrapsSynchronousRequest: false,
            includesCompletionMessage: false
        ) { chunk in
            output.append(chunk)
            if output.length > 1500 {
                output.deleteCharacters(in: NSRange(location: 0, length: output.length - 1500))
            }
        }
        if succeeded {
            return nil
        }
        var description = (output as String).trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            description = NSLocalizedString(
                "Homebrew could not export the Brewfile. Check the destination and try again.",
                comment: ""
            )
        }
        return NSError(
            domain: "Cakebrew.Brewfile.Export",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    @objc(runBrewImportToolWithPath:withReturnsBlock:)
    open func runBrewImportTool(
        withPath path: String?,
        withReturnsBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        guard let path else { return false }
        let arguments = ["bundle", "--file=\(path)"]
        let result = performBrewCommand(withArguments: arguments, dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "bundle")
        return result
    }

    @objc(runBrewImportToolWithPath:progress:withReturnsBlock:)
    open func runBrewImportTool(
        withPath path: String?,
        progress: Progress?,
        withReturnsBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        guard let path, brewTransport == .direct, progress?.isCancelled != true else {
            return false
        }
        let result = performAsyncBrewCommand(
            withArguments: ["bundle", "--file=\(path)"],
            wrapsSynchronousRequest: false,
            progress: progress,
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "bundle")
        return result && progress?.isCancelled != true
    }

    private static let catalogChangingCommands: Set<String> = ["update", "tap", "untap", "bundle"]

    @objc(brewCommandChangesCatalogMembership:)
    public class func brewCommandChangesCatalogMembership(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else { return false }
        return catalogChangingCommands.contains(command.lowercased())
    }

    @objc(sendDelegateFormulaeUpdatedCallForCommand:)
    open func sendDelegateFormulaeUpdatedCall(forCommand command: String?) {
        let rebuildCatalogs = Self.brewCommandChangesCatalogMembership(command)
        guard let delegate = self.delegate else { return }
        DispatchQueue.main.async {
            delegate.homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs(rebuildCatalogs)
        }
    }
}

#if DEBUG
@objc(BPMockHomebrewInterface)
open class BPMockHomebrewInterface: BPHomebrewInterface, @unchecked Sendable {
    // All stored properties have zero-byte defaults so class_createInstance(Cls, 0) works safely.
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
        []
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
            return [
                BPFormula.formula(withName: "mockwget", andVersion: "1.0.0"),
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
        get { bpSynchronized(self) { _pinnedFormulaeStorage as? [BPFormula] } }
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
              !formula.cask,
              let installedName = formula.installedName(),
              !installedName.isEmpty else {
            return false
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

