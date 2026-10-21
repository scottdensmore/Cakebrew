import Foundation

enum BPFormulaInformationMode: Int, Equatable, Sendable {
    case general = 0
    case installedDependents = 1
    case allDependents = 2

    init(rawInfoType: Int) {
        self = BPFormulaInformationMode(rawValue: rawInfoType) ?? .general
    }
}

/// Values crossing the Objective-C model / Swift UI boundary never retain BPFormula.
struct BPFormulaInformationIdentity: Equatable, Sendable {
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
