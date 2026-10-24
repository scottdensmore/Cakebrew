import CryptoKit
import Darwin
import Foundation

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
