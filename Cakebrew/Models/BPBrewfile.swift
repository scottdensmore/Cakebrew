import CryptoKit
import Darwin
import Foundation

@objc(BPBrewfile)
public final class BPBrewfile: NSObject {
    private static let brewfileName = "Brewfile"

    @objc public static func defaultFilename() -> String {
        brewfileName
    }

    @objc(isBrewfileURL:)
    public static func isBrewfileURL(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        let name = url.lastPathComponent
        guard !name.isEmpty else { return false }
        if name.caseInsensitiveCompare(brewfileName) == .orderedSame {
            return true
        }
        let suffix = "." + brewfileName
        let nsName = name as NSString
        let nsSuffix = suffix as NSString
        guard nsName.length > nsSuffix.length else { return false }
        let tail = nsName.substring(from: nsName.length - nsSuffix.length)
        return tail.caseInsensitiveCompare(suffix) == .orderedSame
    }

    @objc(brewfileURLsFrom:)
    public static func brewfileURLs(from urls: [URL]?) -> [URL] {
        guard let urls, !urls.isEmpty else { return [] }
        return urls.filter { isBrewfileURL($0) }
    }
}
