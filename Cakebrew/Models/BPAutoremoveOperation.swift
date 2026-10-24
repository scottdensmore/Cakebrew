import CryptoKit
import Darwin
import Foundation

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
