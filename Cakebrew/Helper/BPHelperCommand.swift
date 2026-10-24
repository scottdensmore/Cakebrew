//
//  BPHelperCommand.swift
//  Cakebrew
//

import Foundation

@objc(BPHelperCommand)
open class BPHelperCommand: NSObject {
    @objc(shellArgumentsForBrewArguments:outputMarker:)
    public class func shellArguments(forBrewArguments arguments: [String]?, outputMarker marker: String?) -> [String] {
        var argv: [String]
        if let marker, !marker.isEmpty {
            argv = [
                "-l",
                "-c",
                "printf '%s\\n' \"$1\"; shift; brew \"$@\"",
                "brew",
                marker
            ]
        } else {
            argv = ["-l", "-c", "brew \"$@\"", "brew"]
        }
        if let arguments {
            argv.append(contentsOf: arguments)
        }
        return argv
    }
}
