//
//  BPHelperOutputRelay.swift
//  Cakebrew
//

import Foundation

@objc(BPHelperOutputRelay)
open class BPHelperOutputRelay: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var accumulated = Data()
    private var undecoded = Data()
    private let sink: (@Sendable (String) -> Void)?

    @objc(initWithSink:)
    public init(sink: (@Sendable (String) -> Void)?) {
        self.sink = sink
        super.init()
    }

    @objc(appendData:)
    public func appendData(_ data: Data?) {
        guard let data, !data.isEmpty else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        accumulated.append(data)
        undecoded.append(data)
        guard let chunk = String(data: undecoded, encoding: .utf8) else {
            return
        }
        undecoded.removeAll(keepingCapacity: true)
        if let sink, !chunk.isEmpty {
            sink(chunk)
        }
    }

    @objc public var accumulatedOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: accumulated, encoding: .utf8) ?? ""
    }
}
