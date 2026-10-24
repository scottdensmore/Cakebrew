import CryptoKit
import Darwin
import Foundation

@objc(BPCleanupPreview)
public final class BPCleanupPreview: NSObject, @unchecked Sendable {
    private static let wouldRemovePrefix = "Would remove: "

    @objc public private(set) var itemCount: UInt = 0
    @objc public private(set) var reclaimableBytes: UInt64 = 0
    @objc public private(set) var paths: [String] = []

    @objc(isEmpty)
    public var empty: Bool {
        itemCount == 0 && reclaimableBytes == 0
    }

    @objc(previewFromOutput:)
    public static func preview(fromOutput output: String?) -> BPCleanupPreview {
        let preview = BPCleanupPreview()
        preview.paths = paths(fromOutput: output)
        preview.itemCount = UInt(preview.paths.count)
        preview.reclaimableBytes = reclaimableBytes(fromOutput: output)
        return preview
    }

    private static func paths(fromOutput output: String?) -> [String] {
        guard let output, !output.isEmpty else { return [] }
        var result: [String] = []
        let prefixLength = (wouldRemovePrefix as NSString).length
        (output as NSString).enumerateLines { line, _ in
            guard line.hasPrefix(wouldRemovePrefix) else { return }
            let rawPath = (line as NSString).substring(from: prefixLength)
                .trimmingCharacters(in: .whitespaces)
            let stripped = pathByStrippingSizeSuffix(rawPath)
            if !stripped.isEmpty {
                result.append(stripped)
            }
        }
        return result
    }

    private static func pathByStrippingSizeSuffix(_ path: String) -> String {
        guard path.hasSuffix(")") else { return path }
        let nsPath = path as NSString
        let open = nsPath.range(of: " (", options: .backwards)
        guard open.location != NSNotFound else { return path }
        return nsPath.substring(to: open.location)
    }

    private static func reclaimableBytes(fromOutput output: String?) -> UInt64 {
        guard let output, !output.isEmpty else { return 0 }
        guard let expression = try? NSRegularExpression(
            pattern: "would free approximately ([0-9]+(?:\\.[0-9]+)?)\\s*(TB|GB|MB|KB|B)\\b",
            options: [.caseInsensitive]
        ) else {
            return 0
        }
        let nsOutput = output as NSString
        guard let match = expression.firstMatch(in: output, options: [], range: NSRange(location: 0, length: nsOutput.length)) else {
            return 0
        }
        let number = nsOutput.substring(with: match.range(at: 1))
        let unit = nsOutput.substring(with: match.range(at: 2)).uppercased()
        let value = NSDecimalNumber(string: number, locale: Locale(identifier: "en_US_POSIX"))
        if value == NSDecimalNumber.notANumber {
            return 0
        }
        let multiplier: UInt64
        switch unit {
        case "KB": multiplier = 1024
        case "MB": multiplier = 1024 * 1024
        case "GB": multiplier = 1024 * 1024 * 1024
        case "TB": multiplier = 1024 * 1024 * 1024 * 1024
        default:   multiplier = 1
        }
        return UInt64(value.doubleValue * Double(multiplier))
    }
}
