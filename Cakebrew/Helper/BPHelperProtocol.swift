//
//  BPHelperProtocol.swift
//  Cakebrew
//

import Foundation

@objc(BPHelperOutputSink)
public protocol BPHelperOutputSink: NSObjectProtocol, Sendable {
    @objc(helperDidProduceOutput:)
    func helperDidProduceOutput(_ output: String)
}

@objc(BPHelperProtocol)
public protocol BPHelperProtocol: NSObjectProtocol, Sendable {
    @objc(runBrewWithArguments:outputMarker:reply:)
    func runBrew(
        withArguments arguments: [String],
        outputMarker marker: String?,
        reply: @escaping @Sendable (Int32, String?) -> Void
    )

    @objc(cancelBrewWithReply:)
    func cancelBrew(reply: @escaping @Sendable () -> Void)

    @objc(helperVersionWithReply:)
    func helperVersion(reply: @escaping @Sendable (String) -> Void)
}
