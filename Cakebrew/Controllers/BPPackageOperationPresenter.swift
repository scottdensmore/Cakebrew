import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

// MARK: - Objective-C AppKit & Helper Runtime Bridges

@objc internal protocol BPAppDelegateObjCBridge: NSObjectProtocol {
    var window: NSWindow? { get }
    var isRunningBackgroundTask: Bool {
        @objc(isRunningBackgroundTask) get
        @objc(setRunningBackgroundTask:) set
    }
    var brewfileImportTarget: AnyObject? { get }
    @objc(displayBackgroundWarning)
    func displayBackgroundWarning()
    @objc(requestUserAttentionWithMessageTitle:andDescription:)
    func requestUserAttention(withMessageTitle title: String, andDescription desc: String)
    @objc(updateMenuBarExtra)
    func updateMenuBarExtra()
    @objc(checkForAppUpdates:)
    func checkForAppUpdates(_ sender: Any?)
}

@objc internal protocol BPBrewfileImportingObjCBridge: NSObjectProtocol {
    @objc(importBrewfileAtURL:)
    func importBrewfile(at url: URL)
}

@objc internal protocol BPHelperRegistrationObjCBridge: NSObjectProtocol {
    @objc(currentState)
    func currentState() -> Int
    @objc(registerReturningError:)
    func registerReturningError(_ error: NSErrorPointer) -> Bool
}

@objc internal protocol BPHelperRegistrationClassObjCBridge: NSObjectProtocol {
    @objc(sharedRegistration)
    func sharedRegistration() -> AnyObject?
    @objc(localizedDescriptionForState:)
    func localizedDescription(forState state: Int) -> String
    @objc(stateOffersLoginItemsShortcut:)
    func stateOffersLoginItemsShortcut(_ state: Int) -> Bool
    @objc(openLoginItemsSettings)
    func openLoginItemsSettings()
}

@MainActor
@inline(__always)
internal func bpSharedAppDelegate() -> BPAppDelegateObjCBridge? {
    guard let delegate = NSApplication.shared.delegate else { return nil }
    return unsafeBitCast(delegate as AnyObject, to: BPAppDelegateObjCBridge.self)
}

@inline(__always)
internal func bpHelperRegistrationClass() -> BPHelperRegistrationClassObjCBridge? {
    guard let cls = NSClassFromString("BPHelperRegistration") else { return nil }
    return unsafeBitCast(cls as AnyObject, to: BPHelperRegistrationClassObjCBridge.self)
}

@inline(__always)
internal func bpSharedHelperRegistration() -> BPHelperRegistrationObjCBridge? {
    guard let obj = bpHelperRegistrationClass()?.sharedRegistration() else { return nil }
    return unsafeBitCast(obj, to: BPHelperRegistrationObjCBridge.self)
}

// MARK: - Migrated Presenter, DataSource, Sidebar, Window & Controllers (Swift 6)

@MainActor
internal var bpTapInputHostAssocKey: UInt8 = 0
@MainActor
internal var bpCleanupPreviewHostAssocKey: UInt8 = 0
@MainActor
internal var bpBrewfileReviewHostAssocKey: UInt8 = 0

@MainActor
@objc(BPPackageOperationPresenter)
public final class BPPackageOperationPresenter: NSObject {
    private static func operationLocalizedFormat(_ key: String, fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    @objc(installAlertForFormula:)
    public static func installAlert(forFormula formula: Any?) -> NSAlert? {
        guard let f = bpAsFormula(formula), let name = f.name, !name.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Confirmation_Install_Formula",
                fallback: "Are you sure you want to install the formula '%@'?"
            ),
            name
        )
        return alert
    }

    @objc(uninstallAlertForFormula:initialZapState:)
    public static func uninstallAlert(forFormula formula: Any?, initialZapState zapState: Bool) -> NSAlert? {
        guard let f = bpAsFormula(formula), let name = f.name, !name.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Confirmation_Uninstall_Formula",
                fallback: "Are you sure you want to uninstall the formula '%@'?"
            ),
            name
        )
        if f.cask {
            let zapCheckbox = NSButton(
                checkboxWithTitle: NSLocalizedString("Confirmation_Uninstall_Cask_Zap", comment: ""),
                target: nil,
                action: nil
            )
            zapCheckbox.sizeToFit()
            zapCheckbox.state = zapState ? .on : .off
            alert.accessoryView = zapCheckbox
        }
        return alert
    }

    @objc(upgradeAlertForFormulae:)
    public static func upgradeAlert(forFormulae formulae: [Any]?) -> NSAlert? {
        guard let formulae, !formulae.isEmpty else { return nil }
        var names: [String] = []
        names.reserveCapacity(formulae.count)
        for item in formulae {
            if let f = bpAsFormula(item), let name = f.name, !name.isEmpty {
                names.append(name)
            }
        }
        guard !names.isEmpty else { return nil }
        let formulaNames = names.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Message_Update_Formulae_Title", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Message_Update_Formulae_Body",
                fallback: "Are you sure you want to update these formulae: '%@'?"
            ),
            formulaNames
        )
        return alert
    }

    @objc(updatesReviewSummaryForSnapshot:)
    public static func updatesReviewSummary(forSnapshot snapshot: BPUpdatesSnapshot?) -> String? {
        guard let snapshot, snapshot.hasEligibleUpdates else { return nil }
        var sections: [String] = []
        if !snapshot.eligibleFormulae.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat("Updates_Formula_Targets", fallback: "Formulae: %@"),
                snapshot.eligibleFormulae.joined(separator: ", ")
            ))
        }
        if !snapshot.eligibleCasks.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat("Updates_Cask_Targets", fallback: "Casks: %@"),
                snapshot.eligibleCasks.joined(separator: ", ")
            ))
        }
        if !snapshot.excludedFormulae.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat(
                    "Updates_Pinned_Formula_Exclusions",
                    fallback: "Pinned formulae will be skipped: %@"
                ),
                snapshot.excludedFormulae.joined(separator: ", ")
            ))
        }
        if !snapshot.excludedCasks.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat(
                    "Updates_Pinned_Cask_Exclusions",
                    fallback: "Pinned casks will be skipped: %@"
                ),
                snapshot.excludedCasks.joined(separator: ", ")
            ))
        }
        return sections.joined(separator: "\n\n")
    }

    @objc(upgradeAllAlertForSnapshot:)
    public static func upgradeAllAlert(forSnapshot snapshot: BPUpdatesSnapshot?) -> NSAlert? {
        guard let summary = updatesReviewSummary(forSnapshot: snapshot) else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Updates_Confirm_Title", comment: "")
        alert.informativeText = NSLocalizedString("Updates_Review_Body", comment: "")
        let review = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
        review.hasVerticalScroller = true
        review.borderType = .bezelBorder
        let targets = NSTextView(frame: review.contentView.bounds)
        targets.isEditable = false
        targets.isSelectable = true
        targets.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        targets.textContainerInset = NSSize(width: 8, height: 8)
        targets.textContainer?.widthTracksTextView = true
        targets.autoresizingMask = [.width]
        targets.isVerticallyResizable = true
        targets.isHorizontallyResizable = false
        targets.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        targets.string = summary
        targets.setAccessibilityIdentifier("updates.targets")
        targets.setAccessibilityLabel(NSLocalizedString("Updates_Review_Targets", comment: ""))
        review.documentView = targets
        alert.accessoryView = review
        alert.addButton(withTitle: NSLocalizedString("Updates_Confirm_Action", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.buttons.first?.setAccessibilityIdentifier("updates.confirm")
        return alert
    }

    @objc public static func updatesChangedAlert() -> NSAlert {
        let changed = NSAlert()
        changed.messageText = NSLocalizedString("Updates_Changed_Title", comment: "")
        changed.informativeText = NSLocalizedString("Updates_Changed_Body", comment: "")
        changed.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        return changed
    }

    @objc public static func tapInputAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Message_Tap_Title", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = NSLocalizedString("Message_Tap_Body", comment: "")

        let host = BPTapInputHost()
        objc_setAssociatedObject(alert, &bpTapInputHostAssocKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        alert.accessoryView = host.viewController.view
        return alert
    }

    @objc(tapInputHostForAlert:)
    public static func tapInputHost(for alert: NSAlert?) -> BPTapInputHost? {
        guard let alert else { return nil }
        return objc_getAssociatedObject(alert, &bpTapInputHostAssocKey) as? BPTapInputHost
    }

    @objc public static func invalidTapAlert() -> NSAlert {
        let error = NSAlert()
        error.messageText = NSLocalizedString("Message_Tap_Invalid_Title", comment: "")
        error.informativeText = NSLocalizedString("Message_Tap_Invalid_Body", comment: "")
        error.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        return error
    }

    @objc(untapAlertForFormula:)
    public static func untapAlert(forFormula formula: Any?) -> NSAlert? {
        guard let f = bpAsFormula(formula), let name = f.name, !name.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Message_Untap_Title", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Message_Untap_Body",
                fallback: "Are you sure you want to untap the repository '%@'?"
            ),
            name
        )
        return alert
    }

    @objc(cleanupConfirmationBodyForPreview:)
    public static func cleanupConfirmationBody(for preview: BPCleanupPreview) -> String {
        let items = preview.itemCount == 1
            ? operationLocalizedFormat("Cleanup_Item_Count_One", fallback: "1 item")
            : String.localizedStringWithFormat(
                operationLocalizedFormat("Cleanup_Item_Count_Other", fallback: "%lu items"),
                UInt(preview.itemCount)
            )

        if preview.reclaimableBytes == 0 {
            return String.localizedStringWithFormat(
                operationLocalizedFormat(
                    "Confirmation_Cleanup_No_Size",
                    fallback: "Would remove %@ from Homebrew's cache and old installed versions.\n\nAre you sure you want to proceed?"
                ),
                items
            )
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        let size = formatter.string(fromByteCount: Int64(preview.reclaimableBytes))

        return String.localizedStringWithFormat(
            operationLocalizedFormat(
                "Confirmation_Cleanup",
                fallback: "Would remove %@ (%@) from Homebrew's cache and old installed versions.\n\nAre you sure you want to proceed?"
            ),
            items,
            size
        )
    }

    @objc(cleanupAlertForPreview:)
    public static func cleanupAlert(for preview: BPCleanupPreview) -> NSAlert {
        let alert = NSAlert()
        if preview.empty {
            alert.messageText = NSLocalizedString("Cleanup_Nothing_Title", comment: "")
            alert.informativeText = NSLocalizedString("Cleanup_Nothing_Body", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
            return alert
        }

        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = cleanupConfirmationBody(for: preview)

        var formattedSize = ""
        if preview.reclaimableBytes > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            formattedSize = formatter.string(fromByteCount: Int64(preview.reclaimableBytes))
        }
        let host = BPCleanupPreviewHost(
            itemCount: Int(preview.itemCount),
            reclaimableBytes: preview.reclaimableBytes,
            formattedByteCount: formattedSize,
            samplePaths: preview.paths
        )
        objc_setAssociatedObject(alert, &bpCleanupPreviewHostAssocKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        alert.accessoryView = host.viewController.view
        return alert
    }

    @objc(cleanupPreviewHostForAlert:)
    public static func cleanupPreviewHost(for alert: NSAlert?) -> BPCleanupPreviewHost? {
        guard let alert else { return nil }
        return objc_getAssociatedObject(alert, &bpCleanupPreviewHostAssocKey) as? BPCleanupPreviewHost
    }

    @objc(brewfileInventoriesForInstalledFormulae:installedCasks:repositories:)
    public static func brewfileInventories(
        forInstalledFormulae formulae: [Any]?,
        installedCasks casks: [Any]?,
        repositories: [Any]?
    ) -> [String: [String]] {
        var inventories: [String: [String]] = [:]
        if let formulae {
            inventories["brew"] = formulae.compactMap { bpAsFormula($0)?.name }
        }
        if let casks {
            inventories["cask"] = casks.compactMap { bpAsFormula($0)?.name }
        }
        if let repositories {
            inventories["tap"] = repositories.compactMap { bpAsFormula($0)?.name }
        }
        return inventories
    }

    @objc(resolvedSelectionForFormulaNames:caskNames:outdatedFormulae:outdatedCasks:)
    public static func resolvedSelection(
        forFormulaNames formulaNames: [Any],
        caskNames: [Any],
        outdatedFormulae: [Any]?,
        outdatedCasks: [Any]?
    ) -> [Any] {
        var result: [Any] = []
        let formulaCls = bpFormulaClass()

        var formulaByName: [String: AnyObject] = [:]
        if let outdatedFormulae {
            for item in outdatedFormulae {
                if let f = bpAsFormula(item), let name = f.name, !name.isEmpty {
                    formulaByName[name] = item as AnyObject
                }
            }
        }
        for rawName in formulaNames {
            guard let name = rawName as? String, !name.isEmpty else { continue }
            if let matched = formulaByName[name] {
                result.append(matched)
            } else if let fallback = formulaCls?.formula(withName: name), let f = bpAsFormula(fallback) {
                f.cask = false
                result.append(fallback)
            }
        }

        var caskByName: [String: AnyObject] = [:]
        if let outdatedCasks {
            for item in outdatedCasks {
                if let c = bpAsFormula(item), let name = c.name, !name.isEmpty {
                    caskByName[name] = item as AnyObject
                }
            }
        }
        for rawName in caskNames {
            guard let name = rawName as? String, !name.isEmpty else { continue }
            if let matched = caskByName[name] {
                result.append(matched)
            } else if let fallback = formulaCls?.formula(withName: name), let c = bpAsFormula(fallback) {
                c.cask = true
                result.append(fallback)
            }
        }

        return result
    }
}
