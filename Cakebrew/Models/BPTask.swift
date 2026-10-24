import CryptoKit
import Darwin
import Foundation

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
