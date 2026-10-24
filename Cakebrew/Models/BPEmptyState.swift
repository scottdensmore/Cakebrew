import CryptoKit
import Darwin
import Foundation

@objc(BPEmptyState)
public final class BPEmptyState: NSObject {
    @objc public let symbolName: String
    @objc public let titleKey: String
    @objc public let messageKey: String

    public init(symbolName: String, titleKey: String, messageKey: String) {
        self.symbolName = symbolName
        self.titleKey = titleKey
        self.messageKey = messageKey
        super.init()
    }

    @objc(stateForSidebarRow:searching:)
    public static func state(forSidebarRow row: Int, searching: Bool) -> BPEmptyState {
        if searching {
            return BPEmptyState(
                symbolName: "magnifyingglass",
                titleKey: "Empty_Search_Title",
                messageKey: "Empty_Search_Message"
            )
        }
        switch row {
        case 2, 15:
            return BPEmptyState(
                symbolName: "checkmark.circle",
                titleKey: "Empty_Outdated_Title",
                messageKey: "Empty_Outdated_Message"
            )
        case 9:
            return BPEmptyState(
                symbolName: "checkmark.circle",
                titleKey: "Empty_OutdatedCasks_Title",
                messageKey: "Empty_OutdatedCasks_Message"
            )
        case 5:
            return BPEmptyState(
                symbolName: "pin",
                titleKey: "Empty_Pinned_Title",
                messageKey: "Empty_Pinned_Message"
            )
        case 14:
            return BPEmptyState(
                symbolName: "gearshape.2",
                titleKey: "Empty_Services_Title",
                messageKey: "Empty_Services_Message"
            )
        case 8:
            return BPEmptyState(
                symbolName: "macwindow",
                titleKey: "Empty_Casks_Title",
                messageKey: "Empty_Casks_Message"
            )
        case 4:
            return BPEmptyState(
                symbolName: "leaf",
                titleKey: "Empty_Leaves_Title",
                messageKey: "Empty_Leaves_Message"
            )
        default:
            return BPEmptyState(
                symbolName: "tray",
                titleKey: "Empty_Generic_Title",
                messageKey: "Empty_Generic_Message"
            )
        }
    }

    @objc(shouldShowForRowCount:loading:)
    public static func shouldShow(forRowCount rowCount: Int, loading: Bool) -> Bool {
        return rowCount == 0 && !loading
    }
}
