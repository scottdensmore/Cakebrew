import CryptoKit
import Darwin
import Foundation

// MARK: - Swift 6 Core Models & Utilities

@objc(BPAutoremovePreview)
public final class BPAutoremovePreview: NSObject, @unchecked Sendable {
    @objc public private(set) var valid: Bool = false
    @objc public private(set) var names: [String] = []
    @objc public private(set) var rawOutput: String = ""

    @objc(previewWithOutput:succeeded:)
    public static func preview(withOutput output: String?, succeeded: Bool) -> BPAutoremovePreview {
        let preview = BPAutoremovePreview()
        preview.rawOutput = output ?? ""
        preview.names = []
        guard succeeded, let output else { return preview }
        let text = output.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            preview.valid = true
            return preview
        }
        let lines = text.components(separatedBy: "\n")
        guard let header = try? NSRegularExpression(pattern: "^==> Would autoremove ([1-9][0-9]*) unneeded formula(e)?:$", options: []) else {
            return preview
        }
        let firstLine = lines[0] as NSString
        guard let match = header.firstMatch(in: lines[0], options: [], range: NSRange(location: 0, length: firstLine.length)) else {
            return preview
        }
        let countString = firstLine.substring(with: match.range(at: 1))
        guard let count = Int(countString), count > 0 else { return preview }
        let pluralAbsent = (match.range(at: 2).location == NSNotFound)
        if count != lines.count - 1 || (count == 1) != pluralAbsent {
            return preview
        }
        guard let namePattern = try? NSRegularExpression(pattern: "^(?:[a-zA-Z0-9][a-zA-Z0-9_.+-]*/[a-zA-Z0-9][a-zA-Z0-9_.+-]*/)?[a-zA-Z0-9][a-zA-Z0-9_.+@-]*$", options: []) else {
            return preview
        }
        var orderedNames: [String] = []
        var seen = Set<String>()
        for name in lines[1...count] {
            let nsName = name as NSString
            if namePattern.firstMatch(in: name, options: [], range: NSRange(location: 0, length: nsName.length)) == nil || seen.contains(name) {
                return preview
            }
            seen.insert(name)
            orderedNames.append(name)
        }
        preview.names = orderedNames
        preview.valid = true
        return preview
    }
}
