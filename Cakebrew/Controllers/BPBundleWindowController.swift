import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPBundleWindowController)
public final class BPBundleWindowController: NSWindowController {
    @objc public var viewOperationContainer: NSView?
    @objc public var viewExportProgress: NSView?
    @objc public var viewImportProgress: NSView?
    @objc public var textViewImport: BPAutoScrollTextView?
    @objc public var progressLabelImport: NSTextField?
    @objc public var statusViewExport: NSImageView?
    @objc public var statusLabelExport: NSTextField?
    @objc public var progressLabelExport: NSTextField?
    @objc public var progressIndicator: NSProgressIndicator?
    @objc public var buttonClose: NSButton?

    @objc public var importOperation: BPBrewfileImportOperation?
    @objc public var exportOperation: BPBrewfileExportOperation?
    @objc public var bundleHost: BPBundleOperationHost?

    @objc(reviewHostForPlan:fileName:error:)
    public static func reviewHost(
        for plan: BPBrewfilePlan?,
        fileName: String?,
        error: NSError?
    ) -> BPBrewfileReviewHost {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 550, height: 210))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = NSFont.systemFont(ofSize: 13)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityIdentifier("brewfile.review.entries")
        text.string = error?.localizedDescription ?? (plan?.reviewText ?? "")
        if bpSharedHomebrewInterface()?.brewTransport != 0 {
            text.string = NSLocalizedString(
                "Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.",
                comment: ""
            )
        }

        var installedCount = 0
        var missingCount = 0
        var notCheckedCount = 0
        var formulaCount = 0
        var caskCount = 0
        var tapCount = 0
        var otherCount = 0

        for entry in plan?.entries ?? [] {
            if entry.status == "Installed" {
                installedCount += 1
            } else if entry.status == "Missing" {
                missingCount += 1
            } else {
                notCheckedCount += 1
            }

            if entry.kind == "brew" {
                formulaCount += 1
            } else if entry.kind == "cask" {
                caskCount += 1
            } else if entry.kind == "tap" {
                tapCount += 1
            } else {
                otherCount += 1
            }
        }

        let canInstall = (plan?.canInstall == true) && (bpSharedHomebrewInterface()?.brewTransport == 0)
        let resolvedName = (fileName?.isEmpty == false) ? fileName! : "Brewfile"
        let host = BPBrewfileReviewHost(
            entriesTextView: text,
            fileName: resolvedName,
            installedCount: installedCount,
            missingCount: missingCount,
            notCheckedCount: notCheckedCount,
            formulaCount: formulaCount,
            caskCount: caskCount,
            tapCount: tapCount,
            otherCount: otherCount,
            canInstall: canInstall,
            summaryText: plan?.reviewText ?? ""
        )
        host.viewController.view.frame = NSRect(x: 0, y: 0, width: 570, height: 280)
        return host
    }

    @objc(reviewFile:inventories:parentWindow:completion:)
    public static func reviewFile(
        _ url: URL?,
        inventories: [String: [String]]?,
        parentWindow window: NSWindow?,
        completion: (@Sendable (BPBrewfilePlan?) -> Void)?
    ) {
        let inv = inventories ?? [:]
        DispatchQueue.global(qos: .userInitiated).async {
            var nsError: NSError?
            let plan: BPBrewfilePlan?
            do {
                plan = try BPBrewfilePlan.plan(with: url, inventories: inv)
            } catch let err as NSError {
                nsError = err
                plan = nil
            }
            let capturedError = nsError
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Review Brewfile", comment: "")
                let fileName = url?.lastPathComponent ?? ""
                let disclaimer = NSLocalizedString(
                    "Direct entries only, not a dependency or upgrade plan. Installed means present in the current inventory, not up to date. Homebrew may upgrade packages, install dependencies and required tools, and run package installation scripts. Only the reviewed literal entries will be submitted.",
                    comment: ""
                )
                alert.informativeText = "\(fileName)\n\n\(disclaimer)"
                let install = alert.addButton(withTitle: NSLocalizedString("Install Reviewed Entries", comment: ""))
                install.setAccessibilityIdentifier("brewfile.review.install")
                let canInstall = (plan?.canInstall == true) && (bpSharedHomebrewInterface()?.brewTransport == 0)
                install.isEnabled = canInstall
                let cancel = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                cancel.setAccessibilityIdentifier("brewfile.review.cancel")
                let reviewHost = Self.reviewHost(for: plan, fileName: fileName, error: capturedError)
                objc_setAssociatedObject(alert, &bpBrewfileReviewHostAssocKey, reviewHost, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                alert.accessoryView = reviewHost.viewController.view
                if let window {
                    alert.beginSheetModal(for: window) { result in
                        completion?(result == .alertFirstButtonReturn && canInstall ? plan : nil)
                    }
                } else {
                    completion?(nil)
                }
            }
        }
    }

    @objc(runImportOperationWithPlan:)
    public static func runImportOperation(with plan: BPBrewfilePlan?) -> BPBundleWindowController {
        let controller = createWindow()
        bpSharedAppDelegate()?.isRunningBackgroundTask = true
        controller.startSheetOnMainWindow()
        controller.runImportOperation(with: plan)
        return controller
    }

    @objc(runExportOperationWithFile:)
    public static func runExportOperation(withFile fileURL: URL?) -> BPBundleWindowController {
        let controller = createWindow()
        bpSharedAppDelegate()?.isRunningBackgroundTask = true
        controller.startSheetOnMainWindow()
        controller.runExportOperation(withFile: fileURL)
        return controller
    }

    @objc public static func createWindow() -> BPBundleWindowController {
        BPBundleWindowController(windowNibName: "BPBundleWindow")
    }

    override public func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 413, height: 289),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    override public func windowDidLoad() {
        super.windowDidLoad()
        if textViewImport == nil {
            textViewImport = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 373, height: 197))
        }
        if buttonClose == nil {
            buttonClose = NSButton(frame: NSRect(x: 0, y: 0, width: 80, height: 28))
        }
        if progressLabelImport == nil {
            progressLabelImport = NSTextField(labelWithString: "")
        }
        guard let textViewImport else { return }
        textViewImport.isEditable = false
        textViewImport.isSelectable = true
        textViewImport.isRichText = false
        textViewImport.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textViewImport.setAccessibilityIdentifier("brewfile.import.output")

        let host = BPBundleOperationHost(importTextView: textViewImport)
        host.onAction = { [weak self] in
            self?.didClickClose(nil)
        }
        self.bundleHost = host

        if let contentView = window?.contentView {
            for subview in contentView.subviews {
                subview.removeFromSuperview()
            }
            let hostView = host.viewController.view
            hostView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hostView)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    private func startSheetOnMainWindow() {
        guard let sheetWindow = self.window else { return }
        bpSharedAppDelegate()?.window?.beginSheet(sheetWindow) { _ in
            bpSharedAppDelegate()?.isRunningBackgroundTask = false
        }
    }

    @objc(runImportOperationWithPlan:)
    public func runImportOperation(with plan: BPBrewfilePlan?) {
        _ = self.window
        textViewImport?.clearOutput()
        window?.title = NSLocalizedString("Import Brewfile", comment: "")
        window?.setContentSize(NSSize(width: 650, height: 380))
        textViewImport?.setAccessibilityIdentifier("brewfile.import.output")
        buttonClose?.title = NSLocalizedString("Cancel", comment: "")
        buttonClose?.isEnabled = true
        bundleHost?.configureImport(
            statusText: nil,
            actionTitle: NSLocalizedString("Cancel", comment: ""),
            actionEnabled: true,
            running: true
        )
        let iface = (NSClassFromString("BPHomebrewInterface") as AnyObject?)
            .flatMap { unsafeBitCast($0, to: BPHomebrewInterfaceClassObjCBridge.self).sharedInterface() }
        let op = BPBrewfileImportOperation(plan: plan, interface: iface)
        self.importOperation = op
        let tv = self.textViewImport
        op.start(withOutput: { [weak self] output in
            tv?.appendOutput(output)
            DispatchQueue.main.async {
                self?.bundleHost?.syncLogFromTextView()
            }
        }, completion: { [weak self] success, cancelled, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let status = cancelled
                    ? NSLocalizedString("Import cancelled. Some changes may already have been made.", comment: "")
                    : (success
                        ? NSLocalizedString("Import finished.", comment: "")
                        : NSLocalizedString("Import failed. Review the output for details.", comment: ""))
                self.progressLabelImport?.stringValue = status
                if let error {
                    self.textViewImport?.appendOutput(error.localizedDescription)
                }
                self.textViewImport?.flushPendingOutput()
                self.buttonClose?.title = NSLocalizedString("Close", comment: "")
                self.buttonClose?.isEnabled = true
                self.bundleHost?.configureImport(
                    statusText: status,
                    actionTitle: NSLocalizedString("Close", comment: ""),
                    actionEnabled: true,
                    running: false
                )
                self.bundleHost?.syncLogFromTextView()
            }
        })
    }

    @objc(runExportOperationWithFile:)
    public func runExportOperation(withFile fileURL: URL?) {
        _ = self.window
        buttonClose?.isEnabled = false
        bundleHost?.configureExport(
            statusText: nil,
            detailText: nil,
            actionTitle: nil,
            actionEnabled: false,
            running: true,
            finished: false,
            succeeded: false
        )
        let iface = (NSClassFromString("BPHomebrewInterface") as AnyObject?)
            .flatMap { unsafeBitCast($0, to: BPHomebrewInterfaceClassObjCBridge.self).sharedInterface() }
        let op = BPBrewfileExportOperation(url: fileURL, interface: iface)
        self.exportOperation = op
        op.start { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                let succeeded = (error == nil)
                let statusText = error != nil ? NSLocalizedString("Brewfile_Export_Failed", comment: "") : nil
                let detailText = error?.localizedDescription
                self.buttonClose?.isEnabled = true
                self.bundleHost?.configureExport(
                    statusText: statusText,
                    detailText: detailText,
                    actionTitle: nil,
                    actionEnabled: true,
                    running: false,
                    finished: true,
                    succeeded: succeeded
                )
            }
        }
    }

    @objc(didClickClose:)
    public func didClickClose(_ sender: Any?) {
        if exportOperation?.running == true { return }
        if importOperation?.running == true {
            importOperation?.cancel()
            buttonClose?.isEnabled = false
            let cancelling = NSLocalizedString("Cancelling… Waiting for Homebrew to exit.", comment: "")
            progressLabelImport?.stringValue = cancelling
            bundleHost?.configureImport(
                statusText: cancelling,
                actionTitle: NSLocalizedString("Cancel", comment: ""),
                actionEnabled: false,
                running: true
            )
            return
        }
        if let window = self.window {
            window.sheetParent?.endSheet(window)
        }
    }
}

