import CryptoKit
import Darwin
import Foundation

@objc(BPServiceStatus)
public enum BPServiceStatus: Int, Sendable {
    case none = 0
    case started = 1
    case stopped = 2
    case error = 3
    case scheduled = 4
    case unknown = 5
}

@objc(BPService)
public final class BPService: NSObject, @unchecked Sendable {
    @objc public var name: String?
    @objc public var user: String?
    @objc public var pid: NSNumber?
    @objc public var status: BPServiceStatus = .none
    @objc public var statusString: String?

    @objc(localizationKeyForStatus:)
    public static func localizationKey(for status: BPServiceStatus) -> String {
        switch status {
        case .none:      return "Services_Status_None"
        case .started:   return "Services_Status_Started"
        case .stopped:   return "Services_Status_Stopped"
        case .error:     return "Services_Status_Error"
        case .scheduled: return "Services_Status_Scheduled"
        case .unknown:   return "Services_Status_Unknown"
        @unknown default: return "Services_Status_Unknown"
        }
    }

    @objc(localizedNameForStatus:)
    public static func localizedName(for status: BPServiceStatus) -> String {
        return NSLocalizedString(localizationKey(for: status), comment: "")
    }

    @objc(statusFromString:)
    public static func status(from status: String?) -> BPServiceStatus {
        switch status {
        case "none":      return .none
        case "started":   return .started
        case "stopped":   return .stopped
        case "error":     return .error
        case "scheduled": return .scheduled
        default:          return .unknown
        }
    }

    @objc(validatedServicesFromJSONString:)
    public static func validatedServices(fromJSONString output: String?) -> [BPService]? {
        guard let data = output?.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let entries = parsed as? [Any] else {
            return nil
        }
        var services: [BPService] = []
        for entry in entries {
            guard let dict = entry as? [String: Any] else { return nil }
            for key in ["user", "status", "pid"] {
                if let value = dict[key], !(value is NSNull) {
                    if key == "pid" {
                        guard value is NSNumber else { return nil }
                    } else {
                        guard value is NSString else { return nil }
                    }
                }
            }
            guard let service = service(withDictionary: dict) else { return nil }
            services.append(service)
        }
        return services
    }

    @objc(servicesFromJSONString:)
    public static func services(fromJSONString output: String?) -> [BPService] {
        guard let data = output?.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let entries = parsed as? [Any] else {
            return []
        }
        var services: [BPService] = []
        for entry in entries {
            guard let dict = entry as? [String: Any] else { continue }
            if let service = service(withDictionary: dict) {
                services.append(service)
            }
        }
        return services
    }

    private static func service(withDictionary dict: [String: Any]) -> BPService? {
        guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
        let service = BPService()
        service.name = name
        service.user = dict["user"] as? String
        service.statusString = dict["status"] as? String
        service.status = status(from: service.statusString)
        if let pid = dict["pid"] as? NSNumber {
            service.pid = pid
        }
        return service
    }
}
