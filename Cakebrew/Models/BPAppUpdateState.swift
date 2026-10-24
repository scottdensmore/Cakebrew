import CryptoKit
import Darwin
import Foundation

// MARK: - Secure In-App Update Discovery (#149)

public struct BPAppVersion: Equatable, Comparable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let raw: String

    public init(major: Int, minor: Int, patch: Int = 0, prerelease: String? = nil, raw: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        let cleanedPre = prerelease?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prerelease = (cleanedPre?.isEmpty == false) ? cleanedPre : nil
        if let raw, !raw.isEmpty {
            self.raw = raw
        } else if let prerelease = self.prerelease {
            self.raw = "\(major).\(minor).\(patch)-\(prerelease)"
        } else {
            self.raw = "\(major).\(minor).\(patch)"
        }
    }

    public init?(parsing string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutPrefix: String
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            withoutPrefix = String(trimmed.dropFirst())
        } else {
            withoutPrefix = trimmed
        }
        guard !withoutPrefix.isEmpty else { return nil }

        // Strip optional build metadata (+...)
        let withoutBuild = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let dashParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let corePart = String(dashParts[0])
        let prereleasePart: String? = dashParts.count > 1 ? String(dashParts[1]) : nil
        if let prereleasePart, prereleasePart.isEmpty {
            return nil
        }

        let numbers = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(numbers.count) else { return nil }
        guard let major = Int(numbers[0]), major >= 0,
              let minor = Int(numbers[1]), minor >= 0 else {
            return nil
        }
        let patch: Int
        if numbers.count == 3 {
            guard let parsedPatch = Int(numbers[2]), parsedPatch >= 0 else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }

        self.init(major: major, minor: minor, patch: patch, prerelease: prereleasePart, raw: withoutPrefix)
    }

    public static func < (lhs: BPAppVersion, rhs: BPAppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            // Prerelease is older than the final release of the same version
            return true
        case (nil, .some):
            return false
        case (.some(let lPre), .some(let rPre)):
            return lPre.localizedStandardCompare(rPre) == .orderedAscending
        }
    }
}

public struct BPAppUpdateRelease: Equatable, Sendable {
    public let version: BPAppVersion
    public let title: String
    public let releaseNotes: String
    public let downloadURL: URL
    public let sha256Hex: String
    public let ed25519SignatureBase64: String?
    public let publishedAt: String?

    public init(version: BPAppVersion,
                title: String,
                releaseNotes: String,
                downloadURL: URL,
                sha256Hex: String,
                ed25519SignatureBase64: String? = nil,
                publishedAt: String? = nil) {
        self.version = version
        self.title = title
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.sha256Hex = sha256Hex.lowercased()
        self.ed25519SignatureBase64 = ed25519SignatureBase64
        self.publishedAt = publishedAt
    }

    public var canonicalSignedPayload: Data {
        let string = "\(version.raw)\n\(downloadURL.absoluteString)\n\(sha256Hex.lowercased())"
        return Data(string.utf8)
    }
}

public enum BPAppUpdateFeedError: Error, Equatable, Sendable {
    case invalidJSON
    case invalidVersion
    case insecureDownloadURL
    case invalidSHA256
    case missingSignature
    case invalidSignature
}

public enum BPAppUpdateVerifier: Sendable {
    public static func isValidSHA256Hex(_ hex: String) -> Bool {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count == 64 else { return false }
        for byte in trimmed.utf8 {
            let isDigit = (byte >= 48 && byte <= 57)
            let isLowerHex = (byte >= 97 && byte <= 102)
            let isUpperHex = (byte >= 65 && byte <= 70)
            if !(isDigit || isLowerHex || isUpperHex) {
                return false
            }
        }
        return true
    }

    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func verifySHA256(data: Data, expectedHex: String) -> Bool {
        let cleaned = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidSHA256Hex(cleaned) else { return false }
        return sha256Hex(of: data) == cleaned
    }

    public static func verifyEd25519Signature(release: BPAppUpdateRelease, publicKeyBase64: String) -> Bool {
        guard let signatureBase64 = release.ed25519SignatureBase64,
              let signatureData = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let keyData = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return false
        }
        return publicKey.isValidSignature(signatureData, for: release.canonicalSignedPayload)
    }

    public static func parseFeed(data: Data, publicKeyBase64: String? = nil) -> Result<BPAppUpdateRelease, BPAppUpdateFeedError> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidJSON)
        }
        guard let versionString = json["version"] as? String,
              let version = BPAppVersion(parsing: versionString) else {
            return .failure(.invalidVersion)
        }
        guard let urlString = json["downloadURL"] as? String,
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return .failure(.insecureDownloadURL)
        }
        guard let sha256 = json["sha256"] as? String,
              isValidSHA256Hex(sha256) else {
            return .failure(.invalidSHA256)
        }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseNotes = (json["releaseNotes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let signature = (json["ed25519Signature"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let publishedAt = (json["publishedAt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let release = BPAppUpdateRelease(
            version: version,
            title: (title?.isEmpty == false) ? title! : "Cakebrew \(version.raw)",
            releaseNotes: releaseNotes,
            downloadURL: url,
            sha256Hex: sha256,
            ed25519SignatureBase64: signature,
            publishedAt: publishedAt)

        if let publicKeyBase64, !publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let signature, !signature.isEmpty else {
                return .failure(.missingSignature)
            }
            guard verifyEd25519Signature(release: release, publicKeyBase64: publicKeyBase64) else {
                return .failure(.invalidSignature)
            }
        }

        return .success(release)
    }
}

public struct BPAppUpdateState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate(latestVersion: String)
        case updateAvailable(release: BPAppUpdateRelease, isCryptographicallyVerified: Bool)
        case feedUnavailable
        case failed(message: String)
    }

    public static let defaultReleasesURL = URL(string: "https://github.com/scottdensmore/Cakebrew/releases")!

    public private(set) var currentVersion: BPAppVersion
    public private(set) var phase: Phase = .idle
    public private(set) var releasesPageURL: URL
    public private(set) var requestGeneration: UInt64 = 0

    public init(currentVersionString: String = "1.0.0",
                releasesPageURL: URL = BPAppUpdateState.defaultReleasesURL) {
        self.currentVersion = BPAppVersion(parsing: currentVersionString) ?? BPAppVersion(major: 1, minor: 0, patch: 0, raw: currentVersionString)
        self.releasesPageURL = releasesPageURL
    }

    @discardableResult
    public mutating func beginCheck(currentVersionString: String? = nil) -> UInt64 {
        if let currentVersionString, !currentVersionString.isEmpty {
            self.currentVersion = BPAppVersion(parsing: currentVersionString) ?? BPAppVersion(major: 1, minor: 0, patch: 0, raw: currentVersionString)
        }
        requestGeneration += 1
        phase = .checking
        return requestGeneration
    }

    @discardableResult
    public mutating func receiveFeedData(_ data: Data,
                                         publicKeyBase64: String? = nil,
                                         generation: UInt64) -> Bool {
        guard generation == requestGeneration else { return false }
        let hasPublicKey = (publicKeyBase64?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        switch BPAppUpdateVerifier.parseFeed(data: data, publicKeyBase64: publicKeyBase64) {
        case .success(let release):
            if release.version > currentVersion {
                phase = .updateAvailable(release: release, isCryptographicallyVerified: hasPublicKey)
            } else {
                phase = .upToDate(latestVersion: release.version.raw)
            }
        case .failure(let error):
            switch error {
            case .invalidJSON, .invalidVersion:
                phase = .failed(message: "Invalid update feed format.")
            case .insecureDownloadURL:
                phase = .failed(message: "Update download URL must use HTTPS.")
            case .invalidSHA256:
                phase = .failed(message: "Update feed is missing a valid SHA-256 digest.")
            case .missingSignature, .invalidSignature:
                phase = .failed(message: "Update signature verification failed.")
            }
        }
        return true
    }

    @discardableResult
    public mutating func receiveFeedUnavailable(generation: UInt64) -> Bool {
        guard generation == requestGeneration else { return false }
        phase = .feedUnavailable
        return true
    }

    @discardableResult
    public mutating func receiveError(_ message: String, generation: UInt64) -> Bool {
        guard generation == requestGeneration else { return false }
        phase = .failed(message: message)
        return true
    }
}

