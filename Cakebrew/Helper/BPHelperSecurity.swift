//
//  BPHelperSecurity.swift
//  Cakebrew
//

import Foundation

public let BPHelperMachServiceName = "com.scottdensmore.Cakebrew.Helper"
public let BPHelperIdentifier = "com.scottdensmore.Cakebrew.Helper"

@objc(BPHelperSecurity)
open class BPHelperSecurity: NSObject {
    private static let appIdentifier = "com.scottdensmore.Cakebrew"
    private static let teamIdentifier = "27ZDER873F"

    private static func requirement(forIdentifier identifier: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    @objc public class func clientCodeSigningRequirement() -> String {
        requirement(forIdentifier: appIdentifier)
    }

    @objc public class func helperCodeSigningRequirement() -> String {
        requirement(forIdentifier: BPHelperIdentifier)
    }
}
