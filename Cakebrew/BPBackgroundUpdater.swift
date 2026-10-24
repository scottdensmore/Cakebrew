import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@objc private protocol BPUserNotificationCenterMessaging: NSObjectProtocol {
    @objc(requestAuthorizationWithOptions:completionHandler:)
    func requestAuthorization(
        withOptions options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, NSError?) -> Void
    )
    @objc(addNotificationRequest:withCompletionHandler:)
    func addNotificationRequest(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (NSError?) -> Void)?
    )
}

@objc(BPBackgroundUpdater)
open class BPBackgroundUpdater: NSObject, @unchecked Sendable {
    nonisolated(unsafe) private static var kvoContext: UInt8 = 0

    private static let lastNotifiedOutdatedCountKey = "BPLastNotifiedOutdatedCount"
    public static let outdatedNotificationTargetKey = "outdated-target"
    public static let outdatedNotificationTargetFormulae = "formulae"
    public static let outdatedNotificationTargetCasks = "casks"
    public static let outdatedNotificationTargetMixed = "mixed"

    @objc open var timer: Timer?
    @objc open var lastKnownOutdatedCount: UInt = 0
    @objc open var scheduledInterval: TimeInterval = 0
    @objc open var observingHomebrewManager: Bool = false
    @objc open var notificationCenter: AnyObject?

    public override convenience init() {
        self.init(notificationCenter: UNUserNotificationCenter.current())
    }

    @objc(initWithNotificationCenter:)
    public init(notificationCenter: Any?) {
        self.notificationCenter = notificationCenter as AnyObject?
        super.init()
    }

    @objc(badgeLabelForOutdatedCount:)
    open class func badgeLabel(forOutdatedCount count: UInt) -> String? {
        count == 0 ? nil : "\(count)"
    }

    @objc(shouldNotifyForCount:previousCount:)
    open class func shouldNotify(forCount count: UInt, previousCount: UInt) -> Bool {
        count > previousCount
    }

    @objc(shouldNotifyForCount:previousCount:hasBaseline:)
    open class func shouldNotify(forCount count: UInt, previousCount: UInt, hasBaseline: Bool) -> Bool {
        guard hasBaseline else { return false }
        return shouldNotify(forCount: count, previousCount: previousCount)
    }

    @objc open class func persistedOutdatedCount() -> UInt {
        UInt(max(0, UserDefaults.standard.integer(forKey: lastNotifiedOutdatedCountKey)))
    }

    @objc(setPersistedOutdatedCount:)
    open class func setPersistedOutdatedCount(_ count: UInt) {
        UserDefaults.standard.set(Int(count), forKey: lastNotifiedOutdatedCountKey)
    }

    @objc open class func hasPersistedOutdatedCount() -> Bool {
        UserDefaults.standard.object(forKey: lastNotifiedOutdatedCountKey) != nil
    }

    @objc open class func clearPersistedOutdatedCount() {
        UserDefaults.standard.removeObject(forKey: lastNotifiedOutdatedCountKey)
    }

    @objc(notificationUserInfoForOutdatedFormulaeCount:caskCount:)
    open class func notificationUserInfo(forOutdatedFormulaeCount formulaeCount: UInt, caskCount: UInt) -> [String: String]? {
        if formulaeCount > 0 && caskCount > 0 {
            return [outdatedNotificationTargetKey: outdatedNotificationTargetMixed]
        }
        if formulaeCount > 0 {
            return [outdatedNotificationTargetKey: outdatedNotificationTargetFormulae]
        }
        if caskCount > 0 {
            return [outdatedNotificationTargetKey: outdatedNotificationTargetCasks]
        }
        return nil
    }

    @objc open func start() {
        if let manager = bpSharedHomebrewManager() as? NSObject {
            manager.addObserver(self, forKeyPath: "outdatedFormulae", options: [], context: &Self.kvoContext)
            manager.addObserver(self, forKeyPath: "outdatedCasks", options: [], context: &Self.kvoContext)
            self.observingHomebrewManager = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(outdatedSnapshotDidPublish(_:)),
                name: Notification.Name("BPHomebrewManagerDidPublishOutdatedSnapshotNotification"),
                object: manager
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleTimer),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        scheduleTimer()
    }

    deinit {
        if observingHomebrewManager, let manager = bpSharedHomebrewManager() as? NSObject {
            manager.removeObserver(self, forKeyPath: "outdatedFormulae", context: &Self.kvoContext)
            manager.removeObserver(self, forKeyPath: "outdatedCasks", context: &Self.kvoContext)
        }
        NotificationCenter.default.removeObserver(self)
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        timer?.invalidate()
    }

    @objc open func scheduleTimer() {
        let enabled = BPPreferences.backgroundCheckEnabled
        let interval = max(BPPreferences.backgroundCheckInterval, 3600.0)

        if !enabled {
            timer?.invalidate()
            timer = nil
            scheduledInterval = 0
            return
        }

        if timer != nil && scheduledInterval == interval {
            return
        }

        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        newTimer.tolerance = interval * 0.1
        self.timer = newTimer
        self.scheduledInterval = interval
    }

    @objc(timerFired:)
    open func timerFired(_ timer: Timer?) {
        let busy = MainActor.assumeIsolated { bpSharedAppDelegate()?.isRunningBackgroundTask == true }
        if busy {
            return
        }
        bpSharedHomebrewManager()?.reloadFromInterface(rebuildingCache: false)
    }

    open nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if context != &Self.kvoContext {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(updateDockBadge), object: nil)
        self.perform(#selector(updateDockBadge), with: nil, afterDelay: 0)
    }

    @objc open func updateDockBadge() {
        let manager = bpSharedHomebrewManager()
        let count = UInt((manager?.outdatedFormulae?.count ?? 0) + (manager?.outdatedCasks?.count ?? 0))
        applyDockBadgeLabel(Self.badgeLabel(forOutdatedCount: count))
    }

    @objc(applyDockBadgeLabel:)
    open func applyDockBadgeLabel(_ label: String?) {
        MainActor.assumeIsolated {
            NSApplication.shared.dockTile.badgeLabel = label
        }
    }

    @objc(outdatedSnapshotDidPublish:)
    open func outdatedSnapshotDidPublish(_ notification: Notification) {
        guard let manager = bpSharedHomebrewManager(),
              let obj = notification.object as AnyObject?,
              obj === (manager as AnyObject) else {
            return
        }
        let snapshot = notification.userInfo
        let gen = (snapshot?["generation"] as? NSNumber)?.uintValue ?? UInt.max
        if gen != manager.currentReloadGeneration {
            return
        }
        let formulaeCount = (snapshot?["formulae-count"] as? NSNumber)?.uintValue ?? 0
        let caskCount = (snapshot?["cask-count"] as? NSNumber)?.uintValue ?? 0
        let count = formulaeCount + caskCount

        let hasBaseline = Self.hasPersistedOutdatedCount()
        let previous = Self.persistedOutdatedCount()
        Self.setPersistedOutdatedCount(count)
        self.lastKnownOutdatedCount = count

        if Self.shouldNotify(forCount: count, previousCount: previous, hasBaseline: hasBaseline) {
            postOutdatedNotification(withFormulaeCount: formulaeCount, caskCount: caskCount)
        }
    }

    @objc(postOutdatedNotificationWithFormulaeCount:caskCount:)
    open func postOutdatedNotification(withFormulaeCount formulaeCount: UInt, caskCount: UInt) {
        guard let center = notificationCenter else { return }
        let centerProxy = unsafeBitCast(center, to: BPUserNotificationCenterMessaging.self)
        centerProxy.requestAuthorization(withOptions: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                NSLog("Error requesting notification permissions: %@", error as NSError)
            }
            if granted {
                DispatchQueue.main.async {
                    self?.deliverOutdatedNotification(withFormulaeCount: formulaeCount, caskCount: caskCount)
                }
            }
        }
    }

    @objc(deliverOutdatedNotificationWithFormulaeCount:caskCount:)
    open func deliverOutdatedNotification(withFormulaeCount formulaeCount: UInt, caskCount: UInt) {
        let count = formulaeCount + caskCount
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Background_Update_Notification_Title", comment: "")
        content.body = String(format: NSLocalizedString("Background_Update_Notification_Body", comment: ""), count)
        if let userInfo = Self.notificationUserInfo(forOutdatedFormulaeCount: formulaeCount, caskCount: caskCount) {
            content.userInfo = userInfo
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        if let center = notificationCenter {
            let centerProxy = unsafeBitCast(center, to: BPUserNotificationCenterMessaging.self)
            centerProxy.addNotificationRequest(request, withCompletionHandler: nil)
        }
    }
}

@objc(BPObservingBackgroundUpdater)
public final class BPObservingBackgroundUpdater: BPBackgroundUpdater, @unchecked Sendable {
    @objc public var badgeLabel: String?

    public override func scheduleTimer() {}

    public override func applyDockBadgeLabel(_ label: String?) {
        self.badgeLabel = label
    }
}

