//
//  BPHelperRegistration.swift
//  Cakebrew
//

import AppKit
import Foundation
import ServiceManagement

@objc(BPHelperState)
public enum BPHelperState: Int {
    case notRequired = 0
    case ready = 1
    case needsApproval = 2
    case notRegistered = 3
    case unavailable = 4
}

@objc(BPHelperRegistration)
open class BPHelperRegistration: NSObject, @unchecked Sendable {
    private static let sharedInstance = BPHelperRegistration()

    @objc public class func sharedRegistration() -> BPHelperRegistration {
        sharedInstance
    }

    @objc public class func agentPlistName() -> String {
        (BPHelperIdentifier as NSString).appendingPathExtension("plist") ?? "\(BPHelperIdentifier).plist"
    }

    private class func service() -> SMAppService {
        SMAppService.agent(plistName: agentPlistName())
    }

    @objc public func currentState() -> BPHelperState {
        let transport = BPHomebrewInterface.sharedInterface().brewTransport
        return Self.state(forTransport: transport, serviceStatus: Self.service().status)
    }

    @objc(registerReturningError:)
    public func register() throws {
        try Self.service().register()
    }

    @objc public class func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc(stateForTransport:serviceStatus:)
    public class func state(forTransport transport: BPBrewTransport, serviceStatus status: SMAppService.Status) -> BPHelperState {
        if transport != .helper {
            return .notRequired
        }
        switch status {
        case .enabled:
            return .ready
        case .requiresApproval:
            return .needsApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    @objc(stateAllowsBrewOperations:)
    public class func stateAllowsBrewOperations(_ state: BPHelperState) -> Bool {
        state == .notRequired || state == .ready
    }

    @objc(stateOffersLoginItemsShortcut:)
    public class func stateOffersLoginItemsShortcut(_ state: BPHelperState) -> Bool {
        state == .needsApproval
    }

    @objc(localizedDescriptionForState:)
    public class func localizedDescription(forState state: BPHelperState) -> String {
        switch state {
        case .notRequired:
            return NSLocalizedString("Helper_State_Not_Required", comment: "")
        case .ready:
            return NSLocalizedString("Helper_State_Ready", comment: "")
        case .needsApproval:
            return NSLocalizedString("Helper_State_Needs_Approval", comment: "")
        case .notRegistered:
            return NSLocalizedString("Helper_State_Not_Registered", comment: "")
        case .unavailable:
            return NSLocalizedString("Helper_State_Unavailable", comment: "")
        }
    }
}
