import CryptoKit
import Darwin
import Foundation

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
