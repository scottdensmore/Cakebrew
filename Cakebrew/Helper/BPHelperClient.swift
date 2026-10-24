//
//  BPHelperClient.swift
//  Cakebrew
//

import Foundation

@objc(BPHelperSink)
final class BPHelperSink: NSObject, BPHelperOutputSink, @unchecked Sendable {
    private let lock = NSLock()
    var block: (@Sendable (String) -> Void)?
    private var _deliveredLength: Int = 0

    var deliveredLength: Int {
        lock.lock()
        defer { lock.unlock() }
        return _deliveredLength
    }

    func helperDidProduceOutput(_ output: String) {
        let length = (output as NSString).length
        guard length > 0 else {
            return
        }
        lock.lock()
        _deliveredLength += length
        lock.unlock()
        block?(output)
    }
}

@objc(BPHelperClient)
open class BPHelperClient: NSObject, @unchecked Sendable {
    private static let sharedInstance = BPHelperClient()
    private let lock = NSLock()
    private var currentConnection: NSXPCConnection?

    @objc public class func sharedClient() -> BPHelperClient {
        sharedInstance
    }

    @objc(undeliveredTailOfOutput:deliveredLength:)
    public class func undeliveredTail(ofOutput output: String?, deliveredLength: UInt) -> String? {
        guard let output else {
            return nil
        }
        let nsOutput = output as NSString
        let delivered = Int(deliveredLength)
        if nsOutput.length <= delivered {
            return nil
        }
        return nsOutput.substring(from: delivered)
    }

    @objc(runBrewWithArguments:outputMarker:outputBlock:)
    public func runBrew(
        withArguments arguments: [String]?,
        outputMarker marker: String?,
        outputBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        let sink = BPHelperSink()
        sink.block = block

        let connection = NSXPCConnection(machServiceName: BPHelperMachServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: BPHelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: BPHelperOutputSink.self)
        connection.exportedObject = sink
        connection.setCodeSigningRequirement(BPHelperSecurity.helperCodeSigningRequirement())
        connection.resume()

        lock.lock()
        currentConnection = connection
        lock.unlock()

        final class ReplyBox: @unchecked Sendable {
            var status: Int32 = -1
            var fullOutput: String?
        }
        let replyBox = ReplyBox()
        let finished = DispatchSemaphore(value: 0)

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("Cakebrew helper unavailable: %@", error.localizedDescription)
            finished.signal()
        } as? BPHelperProtocol

        if let proxy {
            proxy.runBrew(withArguments: arguments ?? [], outputMarker: marker) { replyStatus, output in
                replyBox.status = replyStatus
                replyBox.fullOutput = output
                finished.signal()
            }
            finished.wait()
        }

        let tail = Self.undeliveredTail(ofOutput: replyBox.fullOutput, deliveredLength: UInt(sink.deliveredLength))
        if let block, let tail, !tail.isEmpty {
            block(tail)
        }

        connection.invalidate()
        return replyBox.status == 0
    }

    @objc public func cancelCurrentCommand() {
        lock.lock()
        let connection = currentConnection
        lock.unlock()
        guard let connection else {
            return
        }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in } as? BPHelperProtocol
        proxy?.cancelBrew(reply: {})
    }
}
