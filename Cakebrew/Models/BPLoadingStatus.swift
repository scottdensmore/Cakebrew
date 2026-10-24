import CryptoKit
import Darwin
import Foundation

@objc(BPLoadingStatus)
public final class BPLoadingStatus: NSObject {
    @objc(localizationKeyForListMode:)
    public static func localizationKey(forListMode mode: Int) -> String? {
        switch mode {
        case 1: return "Loading_Status_Installed"
        case 3: return "Loading_Status_Outdated"
        case 2: return "Loading_Status_Leaves"
        case 6: return "Loading_Status_Pinned"
        case 5: return "Loading_Status_Repositories"
        case 7: return "Loading_Status_InstalledCasks"
        case 8: return "Loading_Status_OutdatedCasks"
        case 0: return "Loading_Status_AllFormulae"
        case 9: return "Loading_Status_AllCasks"
        default: return nil
        }
    }

    @objc(statusForListMode:)
    public static func status(forListMode mode: Int) -> String {
        let key = localizationKey(forListMode: mode) ?? "Loading_Status_Default"
        return NSLocalizedString(key, comment: "")
    }

    @objc(isSlowListMode:)
    public static func isSlowListMode(_ mode: Int) -> Bool {
        return mode == 0 || mode == 9
    }
}
