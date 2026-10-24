//
//  main.swift
//  CakebrewHelper
//

import Foundation

@objc(BPHelperService)
final class BPHelperService: NSObject, NSXPCListenerDelegate, BPHelperProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var runningTask: Process?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: BPHelperProtocol.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: BPHelperOutputSink.self)
        connection.resume()
        return true
    }

    func runBrew(
        withArguments arguments: [String],
        outputMarker marker: String?,
        reply: @escaping @Sendable (Int32, String?) -> Void
    ) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        task.arguments = BPHelperCommand.shellArguments(forBrewArguments: arguments, outputMarker: marker)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let currentConn = NSXPCConnection.current()
        let sink = currentConn?.remoteObjectProxy as? BPHelperOutputSink
        let relay = BPHelperOutputRelay { chunk in
            sink?.helperDidProduceOutput(chunk)
        }

        let readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = { handle in
            relay.appendData(handle.availableData)
        }

        lock.lock()
        runningTask = task
        lock.unlock()

        do {
            try task.run()
        } catch {
            readHandle.readabilityHandler = nil
            lock.lock()
            runningTask = nil
            lock.unlock()
            reply(-1, error.localizedDescription)
            return
        }

        task.waitUntilExit()

        readHandle.readabilityHandler = nil
        relay.appendData(readHandle.readDataToEndOfFile())

        lock.lock()
        runningTask = nil
        lock.unlock()

        reply(task.terminationStatus, relay.accumulatedOutput)
    }

    func cancelBrew(reply: @escaping @Sendable () -> Void) {
        lock.lock()
        let task = runningTask
        lock.unlock()

        if let task, task.isRunning {
            let descendants = BPProcessTree.descendants(ofProcess: task.processIdentifier)
            task.terminate()
            BPProcessTree.terminateProcesses(descendants)
        }

        reply()
    }

    func helperVersion(reply: @escaping @Sendable (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        reply(version ?? "unknown")
    }
}

autoreleasepool {
    let service = BPHelperService()
    let listener = NSXPCListener(machServiceName: BPHelperMachServiceName)
    listener.delegate = service
    listener.setConnectionCodeSigningRequirement(BPHelperSecurity.clientCodeSigningRequirement())
    listener.resume()
    RunLoop.current.run()
}
