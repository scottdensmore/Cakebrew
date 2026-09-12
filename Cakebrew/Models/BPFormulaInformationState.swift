import Foundation

/// Values crossing the Objective-C model / Swift UI boundary never retain BPFormula.
struct BPFormulaInformationIdentity: Equatable, Sendable {
    let name: String
    let cask: Bool
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

    mutating func begin(name: String, cask: Bool) -> BPFormulaInformationRequest {
        generation += 1
        let next = BPFormulaInformationRequest(
            identity: BPFormulaInformationIdentity(name: name, cask: cask), generation: generation)
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
