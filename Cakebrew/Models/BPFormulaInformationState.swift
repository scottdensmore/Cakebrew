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
public final class BPAutoremovePreview: NSObject {
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
        let localBlock = scheduledBlock
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
public final class BPCleanupPreview: NSObject {
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
public final class BPBrewfilePlan: NSObject {
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
public enum BPServiceStatus: Int {
    case none = 0
    case started = 1
    case stopped = 2
    case error = 3
    case scheduled = 4
    case unknown = 5
}

@objc(BPService)
public final class BPService: NSObject {
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
public final class BPServiceDetails: NSObject {
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
