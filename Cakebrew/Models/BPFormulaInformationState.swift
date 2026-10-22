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

    public var showsVersionColumn: Bool {
        self != .repositories
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

    public var selectedRowIndex: Int {
        guard let selectedID,
              let index = rowIndexByID[selectedID] else {
            return -1
        }
        return index
    }

    public mutating func setMode(_ mode: BPPackageListMode) {
        self.mode = mode
        self.isCaskList = mode.isCaskMode
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
        if let selectedID, rowIndexByID[selectedID] == nil {
            self.selectedID = nil
        }
    }

    public mutating func replaceRows(_ rows: [BPInstalledPackageRow], mode: BPPackageListMode) {
        self.mode = mode
        self.isCaskList = mode.isCaskMode
        self.sourceRows = rows
        rebuildDisplayedRows()
        if let selectedID, rowIndexByID[selectedID] == nil {
            self.selectedID = nil
        }
    }

    public mutating func setSort(column: BPInstalledPackageSortColumn?, ascending: Bool) {
        self.sortColumn = column
        self.sortAscending = ascending
        rebuildDisplayedRows()
    }

    public mutating func select(id: BPFormulaInformationIdentity?) {
        guard let id, rowIndexByID[id] != nil else {
            selectedID = nil
            return
        }
        selectedID = id
    }

    @discardableResult
    public mutating func select(name: String, cask: Bool) -> Bool {
        let candidate = BPFormulaInformationIdentity(name: name, cask: cask, mode: .general)
        guard rowIndexByID[candidate] != nil else {
            selectedID = nil
            return false
        }
        selectedID = candidate
        return true
    }

    @discardableResult
    public mutating func selectRow(at index: Int) -> Bool {
        guard index >= 0 && index < displayedRows.count else {
            selectedID = nil
            return false
        }
        selectedID = displayedRows[index].id
        return true
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
