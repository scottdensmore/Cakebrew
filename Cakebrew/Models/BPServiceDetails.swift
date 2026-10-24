import CryptoKit
import Darwin
import Foundation

@objc(BPServiceDetails)
public final class BPServiceDetails: NSObject, @unchecked Sendable {
    @objc public private(set) var available: Bool = false
    @objc public private(set) var service: BPService?
    @objc public private(set) var rawOutput: String = ""
    @objc public private(set) var serviceFile: String?
    @objc public private(set) var loadedFile: String?
    @objc public private(set) var logPath: String?
    @objc public private(set) var errorLogPath: String?
    @objc public private(set) var exitCode: NSNumber?

    @objc(readableFileURLForPath:)
    public static func readableFileURL(forPath path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let nsPath = path as NSString
        if nsPath.rangeOfCharacter(from: .controlCharacters).location != NSNotFound {
            return nil
        }
        if path.hasPrefix("//") || (!path.hasPrefix("/") && !path.hasPrefix("~/")) {
            return nil
        }
        let resolved = ((nsPath.expandingTildeInPath as NSString).standardizingPath as NSString).resolvingSymlinksInPath
        let files = FileManager.default
        guard let attributes = try? files.attributesOfItem(atPath: resolved),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              files.isReadableFile(atPath: resolved) else {
            return nil
        }
        return URL(fileURLWithPath: resolved)
    }

    @objc(detailsForName:output:succeeded:)
    public static func details(forName name: String?, output: String?, succeeded: Bool) -> BPServiceDetails {
        let result = BPServiceDetails()
        result.rawOutput = output ?? ""
        guard succeeded, let name, !name.isEmpty,
              let data = result.rawOutput.data(using: .utf8),
              let records = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [Any],
              records.count == 1,
              let record = records.first as? [String: Any],
              (record["name"] as? String) == name else {
            return result
        }
        result.service = BPService.services(fromJSONString: output).first
        result.serviceFile = record["file"] as? String
        result.loadedFile = record["loaded_file"] as? String
        result.logPath = record["log_path"] as? String
        result.errorLogPath = record["error_log_path"] as? String
        result.exitCode = integerOrNil(record["exit_code"])
        let pid = integerOrNil(record["pid"])
        result.service?.pid = (pid?.int64Value ?? 0) > 0 ? pid : nil
        result.available = (result.service != nil)
        return result
    }

    private static func integerOrNil(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID() else {
            return nil
        }
        return number.doubleValue == Double(number.int64Value) ? number : nil
    }
}

