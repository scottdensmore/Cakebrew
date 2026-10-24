import CryptoKit
import Darwin
import Foundation

@objc(BPBrewfileEntry)
public final class BPBrewfileEntry: NSObject {
    @objc public internal(set) var kind: String = ""
    @objc public internal(set) var name: String = ""
    @objc public internal(set) var status: String = ""
    @objc public var appStoreID: String?
    @objc public var alreadyInstalled: Bool {
        status == "Installed"
    }
    @objc public func isAlreadyInstalled() -> Bool {
        alreadyInstalled
    }
}

@objc(BPBrewfilePlan)
public final class BPBrewfilePlan: NSObject, @unchecked Sendable {
    @objc public private(set) var entries: [BPBrewfileEntry] = []
    @objc public private(set) var diagnostics: [String] = []
    @objc public private(set) var canonicalContents: String?

    @objc public var canInstall: Bool {
        guard let canonicalContents, !canonicalContents.isEmpty else { return false }
        return diagnostics.isEmpty
    }

    @objc public var reviewText: String {
        var installed: UInt = 0
        var missing: UInt = 0
        var unchecked: UInt = 0
        for entry in entries {
            if entry.status == "Installed" {
                installed += 1
            } else if entry.status == "Missing" {
                missing += 1
            } else {
                unchecked += 1
            }
        }
        var text = String(
            format: NSLocalizedString("%lu installed • %lu missing • %lu not checked", comment: ""),
            installed, missing, unchecked
        ) + "\n\n"

        let kinds = ["brew", "cask", "tap", "mas", "vscode"]
        let titles = [
            NSLocalizedString("Formulae", comment: ""),
            NSLocalizedString("Casks", comment: ""),
            NSLocalizedString("Taps", comment: ""),
            NSLocalizedString("Mac App Store", comment: ""),
            NSLocalizedString("VS Code", comment: "")
        ]
        for (index, kind) in kinds.enumerated() {
            var lines: [String] = []
            for entry in entries where entry.kind == kind {
                let status: String
                if entry.status == "Installed" {
                    status = NSLocalizedString("Installed", comment: "")
                } else if entry.status == "Missing" {
                    status = NSLocalizedString("Missing", comment: "")
                } else {
                    status = NSLocalizedString("Not checked", comment: "")
                }
                let displayName: String
                if let appStoreID = entry.appStoreID {
                    displayName = "\(entry.name) (id: \(appStoreID))"
                } else {
                    displayName = entry.name
                }
                lines.append("\(displayName) — \(status)")
            }
            if !lines.isEmpty {
                text += "\(titles[index])\n\(lines.joined(separator: "\n"))\n\n"
            }
        }
        if !diagnostics.isEmpty {
            text += diagnostics.joined(separator: "\n")
        } else if entries.isEmpty {
            text += NSLocalizedString("No supported package entries. Nothing will be installed.", comment: "")
        }
        return text
    }

    private static func matches(_ string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let nsString = string as NSString
        return regex.numberOfMatches(in: string, options: [], range: NSRange(location: 0, length: nsString.length)) == 1
    }

    @objc(planWithURL:inventories:error:)
    public static func plan(with url: URL?, inventories: [String: [String]]?) throws -> BPBrewfilePlan {
        let limit = 1024 * 1024
        var descriptor: Int32 = -1
        if let url, url.isFileURL {
            descriptor = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }
                return Darwin.open(path, O_RDONLY | O_NONBLOCK)
            }
        }
        var info = stat()
        let data = NSMutableData()
        var valid = descriptor >= 0 && fstat(descriptor, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_size <= limit
        if valid {
            var buffer = [UInt8](repeating: 0, count: 8192)
            var count: Int = -1
            while data.length <= limit {
                count = buffer.withUnsafeMutableBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                    return Darwin.read(descriptor, baseAddress, rawBuffer.count)
                }
                if count > 0 {
                    data.append(buffer, length: count)
                } else {
                    break
                }
            }
            valid = (count == 0 && data.length <= limit)
        }
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        guard valid, let contents = String(data: data as Data, encoding: .utf8) else {
            throw NSError(
                domain: "Cakebrew.Brewfile",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Choose a readable UTF-8 Brewfile smaller than 1 MiB. Nothing was installed.", comment: "")
                ]
            )
        }
        return plan(withString: contents, inventories: inventories)
    }

    @objc(planWithString:inventories:)
    public static func plan(withString contents: String, inventories: [String: [String]]?) -> BPBrewfilePlan {
        let plan = BPBrewfilePlan()
        var parsedEntries: [BPBrewfileEntry] = []
        var parsedDiagnostics: [String] = []
        var canonical = ""
        let literal = try? NSRegularExpression(
            pattern: "\\A[ \\t]*(brew|cask|tap|mas|vscode)[ \\t]+(['\"])([^'\"\\\\\\r\\n]+)\\2(?:[ \\t]*,[ \\t]*id:[ \\t]*([1-9][0-9]*))?[ \\t]*(?:#[^\\r\\n]*)?\\z",
            options: []
        )
        let lines = contents.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if matches(line, pattern: "\\A[ \\t]*(?:#[^\\r\\n]*)?\\z") {
                continue
            }
            let nsLine = line as NSString
            let match = literal?.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
            let kind = match.map { nsLine.substring(with: $0.range(at: 1)) }
            let name = match.map { nsLine.substring(with: $0.range(at: 3)) }
            let identifier: String?
            if let match, match.range(at: 4).location != NSNotFound {
                identifier = nsLine.substring(with: match.range(at: 4))
            } else {
                identifier = nil
            }
            var valid = (match != nil)
            if kind == "mas" {
                if let identifier, let name {
                    valid = valid && identifier.count <= 18 && matches(name, pattern: "\\A[A-Za-z0-9][A-Za-z0-9 ._()+&:!-]*\\z")
                } else {
                    valid = false
                }
            } else if let kind, let name {
                valid = valid && (identifier == nil)
                let component = "[a-zA-Z0-9][a-zA-Z0-9_+@.-]*"
                let pattern: String
                if kind == "tap" {
                    pattern = "\\A\(component)/\(component)\\z"
                } else if kind == "vscode" {
                    pattern = "\\A[a-zA-Z0-9][a-zA-Z0-9-]*\\.[a-zA-Z0-9][a-zA-Z0-9-]*\\z"
                } else {
                    pattern = "\\A\(component)(?:/\(component)/\(component))?\\z"
                }
                valid = valid && matches(name, pattern: pattern)
            } else {
                valid = false
            }

            guard valid, let kind, let name else {
                parsedDiagnostics.append(
                    String.localizedStringWithFormat(
                        NSLocalizedString("Line %lu: unsupported syntax or invalid package name. Nothing will be installed.", comment: ""),
                        UInt(index + 1)
                    )
                )
                continue
            }

            let entry = BPBrewfileEntry()
            entry.kind = kind
            entry.name = name
            entry.appStoreID = identifier
            let inventory = inventories?[kind]
            let qualified = (kind != "tap" && name.contains("/"))
            if inventory == nil || kind == "mas" || kind == "vscode" || qualified {
                entry.status = "Not checked"
            } else if inventory?.contains(name) == true {
                entry.status = "Installed"
            } else {
                entry.status = "Missing"
            }
            parsedEntries.append(entry)
            let idSuffix = identifier.map { ", id: \($0)" } ?? ""
            canonical += "\(kind) '\(name)'\(idSuffix)\n"
        }

        plan.entries = parsedEntries
        plan.diagnostics = parsedDiagnostics
        if !parsedEntries.isEmpty && parsedDiagnostics.isEmpty {
            plan.canonicalContents = canonical
        }
        return plan
    }

    @objc(createSnapshotWithError:)
    public func createSnapshot() throws -> URL {
        guard canInstall, let canonicalContents else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil)
        }
        let template = (NSTemporaryDirectory() as NSString).appendingPathComponent("cakebrew-reviewed-XXXXXX")
        var buffer = template.utf8CString
        let directoryPath: String? = buffer.withUnsafeMutableBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress, mkdtemp(baseAddress) != nil else { return nil }
            return String(cString: baseAddress)
        }
        guard let directoryPath else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let url = directoryURL.appendingPathComponent("Brewfile")
        let data = canonicalContents.data(using: .utf8)
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o400]) else {
            Self.removeSnapshot(url)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil)
        }
        return url
    }

    @objc(removeSnapshot:)
    public static func removeSnapshot(_ snapshot: URL?) {
        guard let snapshot,
              snapshot.lastPathComponent == "Brewfile",
              snapshot.deletingLastPathComponent().lastPathComponent.hasPrefix("cakebrew-reviewed-") else {
            return
        }
        try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent())
    }
}
