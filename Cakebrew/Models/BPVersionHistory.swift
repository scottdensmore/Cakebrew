import Foundation
import CryptoKit

struct BPVersionHistorySource: Hashable, Codable, Sendable {
    let owner: String
    let repository: String
    let path: String

    init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard url.scheme == "https", url.host?.lowercased() == "github.com",
              parts.count >= 5, parts[2] == "blob", parts[1].lowercased().hasPrefix("homebrew-"),
              parts[0].range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              parts[1].range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
              !parts.contains(".."), parts.last?.hasSuffix(".rb") == true else { return nil }
        owner = parts[0]
        repository = parts[1]
        path = parts.dropFirst(4).joined(separator: "/")
    }

    var name: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    var tap: String { "\(owner.lowercased())/\(repository.dropFirst("homebrew-".count).lowercased())" }
    var formula: String { "\(tap)/\(name)" }
    var isCask: Bool { path.hasPrefix("Casks/") || tap == "homebrew/cask" }
    var paths: [String] {
        let legacy = "\(isCask ? "Casks" : "Formula")/\(name).rb"
        return ["homebrew/core", "homebrew/cask"].contains(tap) && path != legacy ? [path, legacy] : [path]
    }
    func url(commit: String, raw: Bool = false) -> URL {
        let host = raw ? "https://raw.githubusercontent.com" : "https://github.com"
        let prefix = raw ? "\(owner)/\(repository)/\(commit)" : "\(owner)/\(repository)/blob/\(commit)"
        return URL(string: host)!.appendingPathComponent(prefix).appendingPathComponent(path)
    }
}

struct BPVersionRelease: Identifiable, Hashable, Codable, Sendable {
    let version: String
    let commit: String
    let date: String
    let message: String
    let source: BPVersionHistorySource
    var id: String { "\(source.path):\(commit)" }
    var displayDate: String {
        guard let value = try? Date(date, strategy: .iso8601) else { return String(date.prefix(10)) }
        return DateFormatter.localizedString(from: value, dateStyle: .medium, timeStyle: .none)
    }
    var canInstall: Bool {
        BPVersionHistorySource(url: source.url(commit: "HEAD")) == source &&
        version.count <= 128 && version.range(of: source.isCask ? "^[0-9][A-Za-z0-9.,+_:-]*$" : "^[0-9]+(?:\\.[0-9]+)*$", options: .regularExpression) != nil &&
        commit.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil &&
        source.name.range(of: "^[A-Za-z0-9][A-Za-z0-9+_.@-]*$", options: .regularExpression) != nil
    }
    var destinationTap: String {
        if source.isCask {
            // Preserve the original token so Homebrew replaces and pins the same app.
            // Each historical definition is immutable and isolated by upstream revision.
            let digest = SHA256.hash(data: Data("\(source.formula):\(commit)".utf8)).map { String(format: "%02x", $0) }.joined()
            return "cakebrew/history-\(digest.prefix(20))"
        }
        guard source.tap != "homebrew/core" else { return "cakebrew/versions" }
        // Distinct upstream taps can define different software with the same name.
        let digest = SHA256.hash(data: Data(source.tap.utf8)).map { String(format: "%02x", $0) }.joined()
        return "cakebrew/versions-\(digest.prefix(16))"
    }
    var target: String {
        source.isCask ? "\(destinationTap)/\(source.name)" : "\(destinationTap)/\(source.name.components(separatedBy: "@")[0])@\(version)"
    }

    static func version(in message: String, name: String) -> String? {
        let title = String(message.split(separator: "\n").first ?? "")
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "^\(escaped)(?::)?\\s+(?:update to )?v?([0-9][A-Za-z0-9.,+_:-]*)(?: \\(#\\d+\\))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else { return nil }
        return String(title[range])
    }
}

enum BPVersionHistoryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct BPVersionHistoryPage: Sendable {
    let releases: [BPVersionRelease]
    let nextPath: Int
    let nextPage: Int
    let hasMore: Bool
}

/// Reads history and source as data. Historical Ruby is never evaluated to display information.
actor BPVersionHistoryClient {
    static let shared = BPVersionHistoryClient()
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private struct Commit: Decodable {
        let sha: String
        let commit: Details
        struct Details: Decodable {
            let message: String
            let committer: Author
            struct Author: Decodable { let date: String }
        }
    }

    private func data(at url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Cakebrew-Version-History", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw BPVersionHistoryError.message("The history server did not respond.") }
        if response.statusCode == 403 || response.statusCode == 429 {
            throw BPVersionHistoryError.message("GitHub’s history request limit was reached. Try again later.")
        }
        guard response.statusCode == 200 else {
            throw BPVersionHistoryError.message("Couldn’t load version history (HTTP \(response.statusCode)).")
        }
        guard data.count <= 2_000_000 else { throw BPVersionHistoryError.message("The history response is too large.") }
        return data
    }

    func history(source: BPVersionHistorySource, pathIndex: Int = 0, page: Int = 1) async throws -> BPVersionHistoryPage {
        guard source.paths.indices.contains(pathIndex), page > 0 else { throw BPVersionHistoryError.message("Invalid history page.") }
        var components = URLComponents(string: "https://api.github.com/repos/\(source.owner)/\(source.repository)/commits")!
        components.queryItems = [URLQueryItem(name: "path", value: source.paths[pathIndex]),
                                URLQueryItem(name: "per_page", value: "50"), URLQueryItem(name: "page", value: String(page))]
        let commits = try JSONDecoder().decode([Commit].self, from: await data(at: components.url!))
        let pageSource = BPVersionHistorySource(url: URL(string: "https://github.com/\(source.owner)/\(source.repository)/blob/HEAD")!.appendingPathComponent(source.paths[pathIndex]))!
        var seen = Set<String>()
        let releases = commits.compactMap { item -> BPVersionRelease? in
            guard item.sha.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
                  let version = BPVersionRelease.version(in: item.commit.message, name: source.name), seen.insert(version).inserted else { return nil }
            return BPVersionRelease(version: version, commit: item.sha, date: item.commit.committer.date,
                                    message: item.commit.message, source: pageSource)
        }
        let moreInPath = commits.count == 50
        return BPVersionHistoryPage(releases: releases, nextPath: moreInPath ? pathIndex : pathIndex + 1,
                                    nextPage: moreInPath ? page + 1 : 1,
                                    hasMore: moreInPath || pathIndex + 1 < source.paths.count)
    }

    func information(for release: BPVersionRelease) async throws -> BPHistoricalFormulaDetails {
        let content = try await data(at: release.source.url(commit: release.commit, raw: true))
        guard let source = String(data: content, encoding: .utf8) else { throw BPVersionHistoryError.message("The historical formula is not readable text.") }
        return BPHistoricalFormulaDetails(source: source)
    }
}

struct BPHistoricalFormulaDetails: Sendable {
    let source: String
    var description: String? { quotedValue("desc") }
    var homepage: String? { quotedValue("homepage") }
    var license: String? { quotedValue("license") }
    var explicitVersion: String? { quotedValue("version") }
    var dependencies: [String] {
        source.components(separatedBy: .newlines).compactMap { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return value.hasPrefix("depends_on ") ? String(value.dropFirst("depends_on ".count)) : nil
        }
    }
    private func quotedValue(_ key: String) -> String? {
        let pattern = "^\\s{0,2}\(key)\\s+[\\\"']([^\\\"']+)[\\\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }
}

struct BPVersionInstallResult: Sendable {
    let succeeded: Bool
    let message: String
}

struct BPVersionInstaller {
    typealias Read = @Sendable ([String]) -> (succeeded: Bool, output: String)
    typealias Run = @Sendable ([String]) -> Bool

    /// Install alongside the current keg; activation is an explicit, reversible choice.
    static func install(_ release: BPVersionRelease, makeActive: Bool, progress: Progress,
                        read: Read, run: Run, restore: Run? = nil, restoreRead: Read? = nil) -> BPVersionInstallResult {
        func failure(_ message: String) -> BPVersionInstallResult {
            BPVersionInstallResult(succeeded: false, message: progress.isCancelled ? "Operation cancelled. Review the output for completed steps." : message)
        }
        func command(_ arguments: [String]) -> Bool { !progress.isCancelled && run(arguments) }
        func formulaInfo(_ name: String) -> (Bool, [String: Any]?) {
            let result = read(["info", "--json=v2", "--formula", name])
            let object = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any]
            return (result.succeeded, (object?["formulae"] as? [[String: Any]])?.first)
        }
        func matchesSelectedVersion(_ value: String) -> Bool {
            value == release.version || value.range(of: "^\(NSRegularExpression.escapedPattern(for: release.version))_[0-9]+$",
                                                    options: .regularExpression) != nil
        }
        guard !release.source.isCask, release.canInstall, !progress.isCancelled else { return failure("This version cannot be installed automatically.") }
        let taps = read(["tap"])
        guard taps.succeeded else { return failure("Couldn’t check Homebrew taps. No installation was started.") }
        let installedTaps = Set(taps.output.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
        var wasLinked = false
        var originalVersion = ""
        if makeActive {
            let (succeeded, info) = formulaInfo(release.source.formula)
            guard succeeded, let info else { return failure("Couldn’t check the current installation. No installation was started.") }
            originalVersion = info["linked_keg"] as? String ?? ""
            wasLinked = !originalVersion.isEmpty
        }
        if !installedTaps.contains(release.destinationTap), !command(["tap-new", "--no-git", release.destinationTap]) {
            return failure("Couldn’t create the local versions tap.")
        }
        let existing = formulaInfo(release.target)
        if !existing.0 {
            if !installedTaps.contains(release.source.tap), !command(["tap", "--force", release.source.tap]) {
                return failure("Couldn’t download the source tap’s history.")
            }
            guard command(["extract", "--version=\(release.version)", "--git-revision=\(release.commit)", release.source.formula, release.destinationTap]) else {
                return failure("Couldn’t extract this release. Update Homebrew and its source tap, then review the command output before retrying.")
            }
        }
        let (_, extracted) = formulaInfo(release.target)
        guard let versions = extracted?["versions"] as? [String: Any], versions["stable"] as? String == release.version else {
            return failure("The extracted formula’s version does not match the selected release. Installation stopped.")
        }
        guard command(["install", "--formula", "--skip-link", release.target]) else {
            return failure("Installation failed. The current version’s links were kept.")
        }
        let (_, installedInfo) = formulaInfo(release.target)
        let installedVersions = (installedInfo?["installed"] as? [[String: Any]] ?? []).compactMap { $0["version"] as? String }
        guard !installedVersions.isEmpty, installedVersions.allSatisfy(matchesSelectedVersion) else {
            return failure("Homebrew did not confirm the selected installed version, or another version shares this formula name. No pin was changed and the original formula was not unlinked.")
        }
        guard command(["pin", release.target]) else {
            return failure("The selected version was installed, but pinning failed. The current version’s links were kept.")
        }
        let (_, pinnedInfo) = formulaInfo(release.target)
        guard pinnedInfo?["pinned"] as? Bool == true else {
            return failure("The selected version was installed, but Homebrew did not confirm its pin. The current version’s links were kept.")
        }
        if makeActive {
            if wasLinked, !command(["unlink", release.source.formula]) {
                return failure("The selected version is installed and pinned, but the current version could not be unlinked.")
            }
            let attemptedLink = !progress.isCancelled
            let linkSucceeded = command(["link", "--force", release.target])
            let (_, activeInfo) = linkSucceeded ? formulaInfo(release.target) : (false, nil)
            let activeVersion = activeInfo?["linked_keg"] as? String ?? ""
            if !linkSucceeded || !matchesSelectedVersion(activeVersion) {
                // Linking can fail after creating some symlinks. Remove only this
                // target's links before restoring the original, even after cancellation.
                func restoreCommand(_ arguments: [String]) -> Bool {
                    if let restore { return restore(arguments) }
                    return run(arguments)
                }
                let cleaned = !attemptedLink || restoreCommand(["unlink", release.target])
                let originalRestored = !wasLinked || restoreCommand(["link", "--force", release.source.formula])
                var versionRestored = !wasLinked
                if wasLinked, originalRestored {
                    let arguments = ["info", "--json=v2", "--formula", release.source.formula]
                    let response: (succeeded: Bool, output: String)
                    if let restoreRead { response = restoreRead(arguments) }
                    else { response = read(arguments) }
                    let json = try? JSONSerialization.jsonObject(with: Data(response.output.utf8)) as? [String: Any]
                    let previous = (json?["formulae"] as? [[String: Any]])?.first?["linked_keg"] as? String
                    versionRestored = response.succeeded && previous == originalVersion
                }
                let restored = cleaned && originalRestored && versionRestored
                return BPVersionInstallResult(succeeded: false, message: restored
                    ? "The selected version is installed and pinned, but activation failed. The previous links were preserved or restored."
                    : "The selected version is installed and pinned. Activation and restoring the previous links failed; review the output and restore the previous version’s links before continuing.")
            }
        }
        return BPVersionInstallResult(succeeded: true, message: makeActive
            ? "The selected version is installed, pinned, and active. The previous version remains installed."
            : "The selected version is installed and pinned alongside the current version. Its binaries are available in the versioned Homebrew opt directory.")
    }
}

/// Homebrew casks share app artifacts across releases. Keep their original token and
/// use native reinstall, rather than creating a second token that conflicts in /Applications.
struct BPVersionCaskInstaller {
    typealias Write = @Sendable (String, BPVersionRelease, String) throws -> Void

    static func saveDefinition(repository: String, release: BPVersionRelease, text: String) throws {
        let root = URL(fileURLWithPath: repository, isDirectory: true)
        guard repository.hasPrefix("/"),
              root.lastPathComponent == "homebrew-\(release.destinationTap.split(separator: "/").last!)",
              FileManager.default.fileExists(atPath: root.path) else {
            throw BPVersionHistoryError.message("Homebrew did not return the expected local history tap.")
        }
        let directory = root.appendingPathComponent("Casks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(release.source.name + ".rb")
        let data = Data(text.utf8)
        if FileManager.default.fileExists(atPath: file.path) {
            guard try Data(contentsOf: file) == data else {
                throw BPVersionHistoryError.message("An existing historical cask has different contents. It was not overwritten.")
            }
        } else {
            try data.write(to: file, options: .withoutOverwriting)
        }
    }

    static func install(_ release: BPVersionRelease, sourceText: String, progress: Progress,
                        read: BPVersionInstaller.Read, run: BPVersionInstaller.Run,
                        restore: BPVersionInstaller.Run, restoreRead: BPVersionInstaller.Read? = nil,
                        write: Write = { try saveDefinition(repository: $0, release: $1, text: $2) }) -> BPVersionInstallResult {
        func failure(_ message: String) -> BPVersionInstallResult { .init(succeeded: false, message: message) }
        func command(_ arguments: [String]) -> Bool { !progress.isCancelled && run(arguments) }
        func info(_ name: String) -> [String: Any]? {
            let response = read(["info", "--json=v2", "--cask", name])
            guard response.succeeded,
                  let json = try? JSONSerialization.jsonObject(with: Data(response.output.utf8)) as? [String: Any] else { return nil }
            return (json["casks"] as? [[String: Any]])?.first
        }
        func restorePin() -> Bool {
            guard restore(["pin", "--cask", release.source.formula]) else { return false }
            let arguments = ["info", "--json=v2", "--cask", release.source.formula]
            let response: (succeeded: Bool, output: String)
            if let restoreRead { response = restoreRead(arguments) }
            else { response = read(arguments) }
            guard response.succeeded,
                  let json = try? JSONSerialization.jsonObject(with: Data(response.output.utf8)) as? [String: Any],
                  let cask = (json["casks"] as? [[String: Any]])?.first,
                  let installed = cask["installed"] as? String, !installed.isEmpty else { return false }
            return cask["pinned"] as? Bool == true && cask["pinned_version"] as? String == installed
        }
        guard release.source.isCask, release.canInstall, !progress.isCancelled,
              BPHistoricalFormulaDetails(source: sourceText).explicitVersion == release.version else {
            return failure("This cask’s declared version does not match the selected release, or the operation was cancelled. No app was replaced.")
        }
        let token = NSRegularExpression.escapedPattern(for: release.source.name)
        guard sourceText.range(of: "(?m)^cask [\"']\(token)[\"'] do\\s*$", options: .regularExpression) != nil else {
            return failure("The historical cask token does not match this package. No app was replaced.")
        }
        guard let original = info(release.source.formula), let wasPinned = original["pinned"] as? Bool else {
            return failure("Couldn’t check the current cask and its pin support. Update Homebrew and try again. No app was replaced.")
        }
        let installed = original["installed"] as? String
        let wasInstalled = installed?.isEmpty == false
        let taps = read(["tap"])
        guard taps.succeeded else { return failure("Couldn’t check Homebrew taps. No app was replaced.") }
        if !taps.output.split(whereSeparator: \.isWhitespace).contains(Substring(release.destinationTap)),
           !command(["tap-new", "--no-git", release.destinationTap]) {
            return failure("Couldn’t create the local history tap. No app was replaced.")
        }
        let repository = read(["--repository", release.destinationTap])
        guard repository.succeeded, !progress.isCancelled else { return failure("Couldn’t locate the history tap, or the operation was cancelled. No app was replaced.") }
        do { try write(repository.output.trimmingCharacters(in: .whitespacesAndNewlines), release, sourceText) }
        catch { return failure(error.localizedDescription) }
        guard let recipe = info(release.target), recipe["version"] as? String == release.version,
              let checksum = recipe["sha256"] as? String,
              checksum.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
            return failure("The historical cask must declare the selected version and a SHA-256 checksum for this Mac. No app was replaced.")
        }
        // Fetch and verify the archive before removing the current app. Reject :no_check.
        guard command(["fetch", "--cask", release.target]) else {
            return failure("The historical download could not be verified, or the operation was cancelled. The current app and pin were kept.")
        }
        guard !progress.isCancelled else { return failure("Operation cancelled. The current app and pin were kept.") }
        if wasPinned, !command(["unpin", "--cask", release.source.formula]) {
            let restored = restorePin()
            return failure("Couldn’t temporarily unpin the installed cask. No app was replaced. " +
                           (restored ? "The previous pin policy was preserved or restored." : "Restoring the previous pin failed."))
        }
        let changed = command([wasInstalled ? "reinstall" : "install", "--cask", "--require-sha", release.target])
        guard changed, let actual = info(release.target), actual["installed"] as? String == release.version else {
            // Restore the prior upgrade policy even if cancellation disabled normal commands.
            let restoredPin = !wasPinned || restorePin()
            return failure("Cask replacement did not complete or the installed version could not be confirmed. Review the output; the app may need to be reinstalled. " +
                           (restoredPin ? "The previous pin policy was preserved or restored." : "Restoring the previous pin failed."))
        }
        let pinSucceeded = command(["pin", "--cask", release.target])
        let pinned = pinSucceeded ? info(release.target) : nil
        guard pinSucceeded, pinned?["pinned"] as? Bool == true,
              pinned?["pinned_version"] as? String == release.version else {
            return failure("The historical cask was installed, but its pin could not be confirmed. Review the output and pin it before upgrading.")
        }
        return .init(succeeded: true, message: "The selected cask version is installed and pinned. The app’s own updater can still update it outside Homebrew.")
    }
}

/// Remember upstream identity independently of the extracted recipe's local tap.
struct BPVersionReceipt: Codable, Sendable {
    let release: BPVersionRelease
    let installedAt: Date

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cakebrew/VersionHistory", isDirectory: true)
    }
    static func save(_ release: BPVersionRelease, directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data(release.target.utf8)).map { String(format: "%02x", $0) }.joined()
        try JSONEncoder().encode(Self(release: release, installedAt: Date()))
            .write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
    }
    static func find(name: String, cask: Bool, directory: URL = directory) -> BPVersionRelease? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url -> Self? in
            guard let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(Self.self, from: data),
                  receipt.release.canInstall, receipt.release.source.isCask == cask,
                  name == receipt.release.target || name == receipt.release.target.split(separator: "/").last.map(String.init) else { return nil }
            return receipt
        }.max { $0.installedAt < $1.installedAt }?.release
    }
}

struct BPVersionLatestInstaller {
    static func isInstalled(_ release: BPVersionRelease, read: BPVersionInstaller.Read) -> Bool {
        guard release.canInstall else { return false }
        let cask = release.source.isCask
        let result = read(["info", "--json=v2", cask ? "--cask" : "--formula", release.target])
        guard result.succeeded,
              let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
              let info = (json[cask ? "casks" : "formulae"] as? [[String: Any]])?.first else { return false }
        if cask { return info["installed"] as? String == release.version }
        let pattern = "^\(NSRegularExpression.escapedPattern(for: release.version))(?:_[0-9]+)?$"
        return (info["installed"] as? [[String: Any]] ?? []).contains {
            ($0["version"] as? String)?.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func install(_ release: BPVersionRelease, progress: Progress, read: BPVersionInstaller.Read,
                        run: BPVersionInstaller.Run, recover: BPVersionInstaller.Run,
                        recoverRead: BPVersionInstaller.Read) -> BPVersionInstallResult {
        install(BPVersionReturnPlan(release: release), progress: progress, read: read,
                run: run, recover: recover, recoverRead: recoverRead)
    }

    static func install(_ plan: BPVersionReturnPlan, progress: Progress, read: BPVersionInstaller.Read,
                        run: BPVersionInstaller.Run, recover: BPVersionInstaller.Run,
                        recoverRead: BPVersionInstaller.Read) -> BPVersionInstallResult {
        func failure(_ message: String) -> BPVersionInstallResult { .init(succeeded: false, message: message) }
        func command(_ args: [String]) -> Bool { !progress.isCancelled && run(args) }
        let kind = plan.cask ? "--cask" : "--formula"
        let upstream = plan.upstream
        let historical = plan.historical
        func metadata(_ name: String, recovery: Bool = false) -> [String: Any]? {
            let args = ["info", "--json=v2", kind, name]
            let result: (succeeded: Bool, output: String)
            if recovery { result = recoverRead(args) } else { result = read(args) }
            guard result.succeeded, let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any] else { return nil }
            return (json[plan.cask ? "casks" : "formulae"] as? [[String: Any]])?.first
        }
        func installed(_ info: [String: Any], version: String) -> Bool {
            if plan.cask { return info["installed"] as? String == version }
            return (info["installed"] as? [[String: Any]] ?? []).contains { $0["version"] as? String == version }
        }
        guard plan.isValid, !progress.isCancelled,
              let old = metadata(historical), let oldPinned = old["pinned"] as? Bool else {
            return failure("Couldn’t verify the historical installation. No version was switched.")
        }
        let oldVersions = (old["installed"] as? [[String: Any]] ?? []).compactMap { $0["version"] as? String }
        let selectedPattern = "^\(NSRegularExpression.escapedPattern(for: plan.version))(?:_[0-9]+)?$"
        guard plan.cask ? old["installed"] as? String == plan.version :
                oldVersions.contains(where: { $0.range(of: selectedPattern, options: .regularExpression) != nil }) else {
            return failure("This historical version is not installed. Select the installed older version and try again.")
        }
        guard command(["update"]), let latest = metadata(upstream), let latestPinned = latest["pinned"] as? Bool else {
            return failure("Couldn’t refresh Homebrew’s latest release information. The historical installation was kept.")
        }
        let stable = plan.cask ? latest["version"] as? String : (latest["versions"] as? [String: Any])?["stable"] as? String
        guard let stable, !stable.isEmpty, plan.cask || stable != "latest" else {
            return failure("Homebrew did not provide the latest release information. No version was switched.")
        }
        let revision = latest["revision"] as? Int ?? 0
        let expected = !plan.cask && revision > 0 ? "\(stable)_\(revision)" : stable
        guard command(["fetch", kind, upstream]) else {
            return failure("The latest release could not be downloaded, or the operation was cancelled. The historical version and pins were kept.")
        }
        var changedPins: [String] = []
        func unpin(_ name: String, required: Bool) -> Bool {
            guard required else { return true }
            // Record before running: cancellation can happen after Homebrew changes the pin.
            changedPins.append(name)
            guard command(["unpin", kind, name]) else { return false }
            return metadata(name)?["pinned"] as? Bool == false
        }
        func restorePins() -> Bool {
            var succeeded = true
            for name in changedPins.reversed() {
                let restored = recover(["pin", kind, name])
                let info = metadata(name, recovery: true)
                let pinned = info?["pinned"] as? Bool == true
                let exactCaskPin = !plan.cask || (info?["installed"] as? String != nil &&
                    info?["pinned_version"] as? String == info?["installed"] as? String)
                succeeded = restored && pinned && exactCaskPin && succeeded
            }
            return succeeded
        }
        if plan.cask {
            guard unpin(historical, required: oldPinned || latestPinned) else {
                let restored = restorePins()
                return failure(restored ? "Couldn’t unpin the cask. The previous pin policy was restored." : "Couldn’t unpin the cask or restore its pin. Review the output.")
            }
            guard command(["reinstall", "--cask", upstream]), let actual = metadata(upstream),
                  installed(actual, version: expected), actual["pinned"] as? Bool == false else {
                let restored = restorePins()
                return failure("Returning to the latest cask did not complete or could not be verified. The app may need to be reinstalled. " +
                               (restored ? "The previous pin policy was preserved or restored." : "Restoring the previous pin failed."))
            }
            return .init(succeeded: true, message: "The latest cask release is installed and unpinned. Normal Homebrew upgrades are available again.")
        }
        guard unpin(upstream, required: latestPinned),
              command(["install", "--formula", "--skip-link", upstream]),
              let actual = metadata(upstream), installed(actual, version: expected) else {
            let restored = restorePins()
            return failure("The latest formula could not be installed or verified. The historical command links were kept. " +
                           (restored ? "The previous pin policy was preserved or restored." : "Restoring the previous pin failed."))
        }
        let oldLinked = old["linked_keg"] as? String ?? ""
        let previousLatestLink = latest["linked_keg"] as? String ?? ""
        var attemptedLink = false
        func restoreLinksAndPins() -> BPVersionInstallResult {
            let cleaned = !attemptedLink || recover(["unlink", "--formula", upstream])
            var links = cleaned
            if !oldLinked.isEmpty {
                links = recover(["link", "--force", historical]) && links
                links = metadata(historical, recovery: true)?["linked_keg"] as? String == oldLinked && links
            } else if !previousLatestLink.isEmpty {
                links = recover(["link", "--force", upstream]) && links
                links = metadata(upstream, recovery: true)?["linked_keg"] as? String == previousLatestLink && links
            }
            let pins = restorePins()
            return failure(links && pins
                ? "Returning to the latest release failed. The previous command links and pin policy were preserved or restored."
                : "Returning to the latest release and restoring the previous state did not complete. Review the output before continuing.")
        }
        if historical != upstream, !oldLinked.isEmpty, !command(["unlink", "--formula", historical]) { return restoreLinksAndPins() }
        attemptedLink = !progress.isCancelled
        guard command(["link", "--force", upstream]), metadata(upstream)?["linked_keg"] as? String == expected else {
            return restoreLinksAndPins()
        }
        guard unpin(historical, required: historical != upstream && oldPinned),
              let final = metadata(upstream), final["pinned"] as? Bool == false,
              final["linked_keg"] as? String == expected else { return restoreLinksAndPins() }
        return .init(succeeded: true, message: historical == upstream
            ? "The latest formula release is active and unpinned. Normal Homebrew upgrades are available again."
            : "The latest formula release is active and unpinned. The historical keg remains installed and unpinned.")
    }
}

struct BPVersionReturnPlan: Sendable {
    let historical: String
    var upstream: String
    let cask: Bool
    let version: String
    var requiresUpstream: Bool = false
    let upstreamCandidates: [String]

    init(historical: String, upstream: String, cask: Bool, version: String, requiresUpstream: Bool = false, upstreamCandidates: [String] = []) {
        self.historical = historical
        self.upstream = upstream
        self.cask = cask
        self.version = version
        self.requiresUpstream = requiresUpstream
        self.upstreamCandidates = upstreamCandidates
    }
    init(release: BPVersionRelease) {
        self.init(historical: release.target, upstream: release.source.formula,
                  cask: release.source.isCask, version: release.version)
    }
    static func validPackage(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9][A-Za-z0-9+_.@-]*$", options: .regularExpression) != nil &&
        !name.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }
    var isValid: Bool {
        let oldName = historical.split(separator: "/").last.map(String.init) ?? ""
        let newName = upstream.split(separator: "/").last.map(String.init) ?? ""
        let samePackage = cask ? oldName == newName : oldName.split(separator: "@").first == newName.split(separator: "@").first
        return samePackage && Self.validPackage(historical) && Self.validPackage(upstream) && !version.isEmpty && version.count <= 128 &&
        !upstream.hasPrefix("cakebrew/versions") && !upstream.hasPrefix("cakebrew/history-")
    }
}

struct BPPinnedVersionResolver {
    typealias Receipt = @Sendable (String, Bool) -> BPVersionRelease?

    /// Read installed metadata rather than guessing a tap from a short display name.
    static func resolve(name: String, cask: Bool, read: BPVersionInstaller.Read,
                        receipt: Receipt = { BPVersionReceipt.find(name: $0, cask: $1) }) throws -> BPVersionReturnPlan {
        let response = read(["info", "--json=v2", cask ? "--cask" : "--formula", "--installed"])
        guard response.succeeded,
              let json = try? JSONSerialization.jsonObject(with: Data(response.output.utf8)) as? [String: Any],
              let packages = json[cask ? "casks" : "formulae"] as? [[String: Any]] else {
            throw BPVersionHistoryError.message("Couldn’t read installed Homebrew package metadata.")
        }
        let matches = packages.filter { item in
            let token = (item[cask ? "token" : "name"] as? String ?? "").split(separator: "/").last.map(String.init) ?? ""
            let canonical = "\(item["tap"] as? String ?? "")/\(token)"
            return (name.contains("/") ? name == canonical : name == token) && item["pinned"] as? Bool == true
        }
        guard matches.count == 1, let info = matches.first else {
            throw BPVersionHistoryError.message("Couldn’t verify this pinned package. Refresh the Pinned list and try again.")
        }
        let version: String?
        if cask { version = info["installed"] as? String }
        else {
            let installed = (info["installed"] as? [[String: Any]] ?? []).compactMap { $0["version"] as? String }
            let linked = info["linked_keg"] as? String ?? ""
            version = installed.contains(linked) ? linked : (installed.count == 1 ? installed.first : nil)
        }
        guard let version, !version.isEmpty, let tap = info["tap"] as? String else {
            throw BPVersionHistoryError.message("Homebrew did not identify a single installed version and source tap for this package.")
        }
        let token = (info[cask ? "token" : "name"] as? String ?? name).split(separator: "/").last.map(String.init) ?? ""
        let canonical = "\(tap)/\(token)"
        guard BPVersionReturnPlan.validPackage(canonical) else {
            throw BPVersionHistoryError.message("Homebrew returned an invalid package identity. No version was switched.")
        }
        if let saved = receipt(canonical, cask), saved.target == canonical, saved.source.isCask == cask,
           saved.canInstall {
            let pattern = "^\(NSRegularExpression.escapedPattern(for: saved.version))(?:_[0-9]+)?$"
            if cask ? version == saved.version : version.range(of: pattern, options: .regularExpression) != nil {
                return BPVersionReturnPlan(release: saved)
            }
        }
        let copied = tap == "cakebrew/versions" || tap.hasPrefix("cakebrew/versions-") || tap.hasPrefix("cakebrew/history-")
        let detected = copied ? BPVersionOriginDetector.detect(tap: tap, token: token, cask: cask, installed: info, read: read) : .init(upstream: canonical)
        return BPVersionReturnPlan(historical: canonical, upstream: detected.upstream ?? "",
                                   cask: cask, version: version, requiresUpstream: detected.upstream == nil,
                                   upstreamCandidates: detected.candidates)
    }
}

/// Recover copies predating receipts using Homebrew's catalog, without changing taps or pins.
/// Formula tap fingerprints identify the source tap; casks retain their token and homepage.
/// A missing or ambiguous identity deliberately leaves the review's manual fallback available.
struct BPVersionOriginDetector {
    struct Detection: Sendable {
        var upstream: String? = nil
        var candidates: [String] = []
    }
    static func detect(tap: String, token: String, cask: Bool, installed: [String: Any],
                       read: BPVersionInstaller.Read) -> Detection {
        let catalog = read([cask ? "casks" : "formulae"])
        guard catalog.succeeded else { return .init() }
        let defaultTap = cask ? "homebrew/cask" : "homebrew/core"
        let base = token.components(separatedBy: "@")[0]
        let candidates = Set(catalog.output.split(whereSeparator: \.isWhitespace).map(String.init).map {
            $0.contains("/") ? $0 : "\(defaultTap)/\($0)"
        }.filter { candidate in
            guard BPVersionReturnPlan.validPackage(candidate),
                  !candidate.hasPrefix("cakebrew/versions"), !candidate.hasPrefix("cakebrew/history-") else { return false }
            let name = candidate.split(separator: "/").last.map(String.init) ?? ""
            return cask ? name == token : name.components(separatedBy: "@")[0] == base
        })
        let eligible = candidates.filter { candidate in
            if cask { return true }
            let sourceTap = candidate.split(separator: "/").dropLast().joined(separator: "/").lowercased()
            if tap == "cakebrew/versions" { return sourceTap == "homebrew/core" }
            let digest = SHA256.hash(data: Data(sourceTap.utf8)).map { String(format: "%02x", $0) }.joined()
            return tap == "cakebrew/versions-\(digest.prefix(16))"
        }.sorted()
        guard !eligible.isEmpty else { return .init() }
        guard eligible.count <= 32 else { return .init(candidates: eligible) }
        // extract removes the original @major name. Do not guess between versioned branches.
        if !cask && eligible.count != 1 { return .init(candidates: eligible) }
        let oldHomepage = homepage(installed["homepage"] as? String)
        if cask && oldHomepage == nil { return .init(candidates: eligible) }
        var matches: [String] = []
        for candidate in eligible {
            let response = read(["info", "--json=v2", cask ? "--cask" : "--formula", candidate])
            guard response.succeeded,
                  let json = try? JSONSerialization.jsonObject(with: Data(response.output.utf8)) as? [String: Any],
                  let packages = json[cask ? "casks" : "formulae"] as? [[String: Any]], packages.count == 1,
                  let info = packages.first,
                  let sourceTap = info["tap"] as? String,
                  let name = info[cask ? "token" : "name"] as? String,
                  "\(sourceTap)/\(name.split(separator: "/").last ?? "")" == candidate else {
                // Keep unreadable competing recipes as possibilities, without selecting one.
                return .init(candidates: eligible)
            }
            let currentHomepage = homepage(info["homepage"] as? String)
            if let oldHomepage, currentHomepage != oldHomepage { continue }
            matches.append(candidate)
        }
        return matches.count == 1 ? .init(upstream: matches.first) : .init(candidates: matches)
    }

    private static func homepage(_ value: String?) -> String? {
        guard let value, var url = URLComponents(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        url.scheme = url.scheme?.lowercased()
        url.host = host.lowercased()
        while url.path.hasSuffix("/") { url.path.removeLast() }
        return url.string
    }
}
