//
//  BPProcessTree.swift
//  Cakebrew
//

import Foundation
import Darwin

@objc(BPProcessTree)
open class BPProcessTree: NSObject {
    @objc(descendantsOfProcess:)
    public class func descendants(ofProcess pid: pid_t) -> [NSNumber] {
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
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let child = Int32(trimmed), child > 0 {
                pids.append(contentsOf: descendants(ofProcess: child))
                pids.append(NSNumber(value: child))
            }
        }
        return pids
    }

    @objc(terminateProcesses:)
    public class func terminateProcesses(_ pids: [NSNumber]) {
        for pid in pids {
            kill(pid_t(pid.int32Value), SIGTERM)
        }
    }
}
