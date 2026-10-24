import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@objc private protocol BPButtonEnabling: NSObjectProtocol {
    @objc var isEnabled: Bool {
        @objc(isEnabled) get
        @objc(setEnabled:) set
    }
}

@objc private protocol BPSheetWindowMessaging: NSObjectProtocol {
    @objc var sheetParent: AnyObject? { get }
    @objc(beginSheet:completionHandler:)
    func beginSheet(_ sheetWindow: AnyObject, completionHandler handler: ((NSApplication.ModalResponse) -> Void)?)
    @objc(endSheet:)
    func endSheet(_ sheetWindow: AnyObject)
}

@objc private protocol BPSheetDelegateRecorderMessaging: NSObjectProtocol {
    @objc optional var window: AnyObject? { get }
    @objc(isRunningBackgroundTask) optional func isRunningBackgroundTask() -> Bool
    @objc(runningBackgroundTask) optional func runningBackgroundTask() -> Bool
    @objc(setRunningBackgroundTask:) optional func setRunningBackgroundTask(_ running: Bool)
}

@objc private protocol BPSheetAppRecorderMessaging: NSObjectProtocol {
    @objc optional var delegate: AnyObject? { get }
    @objc optional var events: NSMutableArray? { get }
}

@MainActor
@objc(BPInstallationWindowController)
open class BPInstallationWindowController: NSWindowController {
    @objc open var windowTitleLabel: NSTextField?
    @objc open var formulaNameLabel: NSTextField?
    @objc open var recordTextView: BPAutoScrollTextView?
    @objc open var okButton: AnyObject?
    @objc open var cancelButton: NSButton?
    @objc open var wasCancelled: Bool = false
    @objc open var upgradeProgress: Progress?
    @objc open var progressIndicator: NSProgressIndicator?

    @objc open var windowOperation: BPWindowOperation = .install
    @objc open var formulae: [Any]?
    @objc open var options: [Any]?

    @objc open var operationStatus: Bool = false
    @objc open var upgradeResult: BPUpgradeResult?
    @objc open var upgradeWorkerFinished: Bool = false
    @objc open var zapCask: Bool = false
    @objc open var completionBlock: ((Bool) -> Void)?
    @objc open var installationHost: BPInstallationHost?
    @objc open var isRunningTask: Bool = false

    @objc open class func applicationDelegate() -> AnyObject? {
        guard let app = NSApp as AnyObject? else { return nil }
        return unsafeBitCast(app, to: BPSheetAppRecorderMessaging.self).delegate ?? nil
    }

    @objc open class func sharedTaskMessagesMap() -> [NSNumber: String] {
        return [
            NSNumber(value: BPWindowOperation.install.rawValue): NSLocalizedString("Installation_Window_Operation_Install", comment: ""),
            NSNumber(value: BPWindowOperation.uninstall.rawValue): NSLocalizedString("Installation_Window_Operation_Uninstall", comment: ""),
            NSNumber(value: BPWindowOperation.upgrade.rawValue): NSLocalizedString("Installation_Window_Operation_Update", comment: ""),
            NSNumber(value: BPWindowOperation.tap.rawValue): NSLocalizedString("Installation_Window_Operation_Tap", comment: ""),
            NSNumber(value: BPWindowOperation.untap.rawValue): NSLocalizedString("Installation_Window_Operation_Untap", comment: ""),
            NSNumber(value: BPWindowOperation.cleanup.rawValue): NSLocalizedString("Installation_Window_Operation_Cleanup", comment: "")
        ]
    }

    @objc open func sheetWindowObject() -> AnyObject? {
        return self.window
    }

    open override func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        if progressIndicator == nil {
            progressIndicator = NSProgressIndicator(frame: .zero)
        }
        setupUI()
    }

    open override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            self.setupUI()
        }
    }

    private func setOkButtonEnabled(_ enabled: Bool) {
        guard let okButton else { return }
        unsafeBitCast(okButton, to: BPButtonEnabling.self).isEnabled = enabled
    }

    private func isOkButtonEnabled() -> Bool {
        guard let okButton else { return false }
        if let button = okButton as? NSButton {
            return button.isEnabled
        }
        return unsafeBitCast(okButton, to: BPButtonEnabling.self).isEnabled
    }

    @objc open func setupUI() {
        let messagesMap = Self.sharedTaskMessagesMap()
        let font = BPStyle.defaultFixedWidthFont()
        if recordTextView == nil {
            recordTextView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 344, height: 162))
        }
        if windowTitleLabel == nil {
            windowTitleLabel = NSTextField(labelWithString: "")
        }
        if formulaNameLabel == nil {
            formulaNameLabel = NSTextField(labelWithString: "")
        }
        if okButton == nil {
            okButton = NSButton(title: NSLocalizedString("Generic_OK", comment: ""), target: self, action: #selector(okAction(_:)))
        }
        if cancelButton == nil {
            cancelButton = NSButton(title: NSLocalizedString("Generic_Cancel", comment: ""), target: self, action: #selector(cancelAction(_:)))
        }
        recordTextView?.font = font
        progressIndicator?.setAccessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
        windowTitleLabel?.stringValue = messagesMap[NSNumber(value: windowOperation.rawValue)] ?? ""

        let count = formulae?.count ?? 0
        if count >= 1 {
            let names = namesOfAllFormulae().joined(separator: ", ")
            formulaNameLabel?.stringValue = names
        } else {
            if windowOperation != .cleanup {
                formulaNameLabel?.stringValue = NSLocalizedString("Installation_Window_All_Formulae", comment: "")
            } else {
                formulaNameLabel?.stringValue = ""
            }
        }

        operationStatus = false
        isRunningTask = true

        if installationHost == nil,
           let rawWin = sheetWindowObject(),
           rawWin.isKind(of: NSWindow.self),
           let realWin = rawWin as? NSWindow,
           let contentView = realWin.contentView,
           let recordTextView {
            let host = BPInstallationHost(recordTextView: recordTextView)
            host.onCancel = { [weak self] in
                self?.cancelAction(nil)
            }
            host.onOK = { [weak self] in
                self?.okAction(nil)
            }
            self.installationHost = host

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
        syncInstallationHostState()
    }

    @objc open func syncInstallationHostState() {
        guard let installationHost else { return }
        installationHost.update(
            windowTitle: windowTitleLabel?.stringValue ?? "",
            formulaNames: formulaNameLabel?.stringValue ?? "",
            running: isRunningTask,
            okEnabled: isOkButtonEnabled(),
            cancelEnabled: cancelButton?.isEnabled ?? true
        )
    }

    @objc(runWithOperation:formulae:options:)
    open class func run(
        withOperation windowOperation: BPWindowOperation,
        formulae: [Any]?,
        options: [Any]?
    ) -> Self {
        return run(withOperation: windowOperation, formulae: formulae, options: options, completion: nil)
    }

    @objc(runWithOperation:formulae:options:zap:)
    open class func run(
        withOperation windowOperation: BPWindowOperation,
        formulae: [Any]?,
        options: [Any]?,
        zap: Bool
    ) -> Self {
        let controller = run(withOperation: windowOperation, formulae: formulae, options: options, completion: nil)
        controller.zapCask = zap
        return controller
    }

    @objc(runWithOperation:formulae:options:completion:)
    open class func run(
        withOperation windowOperation: BPWindowOperation,
        formulae: [Any]?,
        options: [Any]?,
        completion completionBlock: ((Bool) -> Void)?
    ) -> Self {
        let operationWindowController = self.init(windowNibName: "BPInstallationWindow")
        operationWindowController.windowOperation = windowOperation
        operationWindowController.formulae = formulae
        operationWindowController.options = options
        operationWindowController.completionBlock = completionBlock

        if let del = self.applicationDelegate() {
            let delProxy = unsafeBitCast(del, to: BPSheetDelegateRecorderMessaging.self)
            delProxy.setRunningBackgroundTask?(true)
            if let sheetWin = operationWindowController.sheetWindowObject() {
                if let parentWin = delProxy.window ?? nil {
                    unsafeBitCast(parentWin, to: BPSheetWindowMessaging.self).beginSheet(sheetWin) { _ in
                        MainActor.assumeIsolated {
                            operationWindowController.cleanupAfterTask()
                        }
                    }
                }
            }
        }
        operationWindowController.executeInstallation()
        return operationWindowController
    }

    @objc open func cleanupAfterTask() {
        if let del = type(of: self).applicationDelegate() {
            unsafeBitCast(del, to: BPSheetDelegateRecorderMessaging.self).setRunningBackgroundTask?(false)
        }
        completionBlock?(operationStatus)
    }

    @objc open func namesOfAllFormulae() -> [String] {
        guard let formulae else { return [] }
        return formulae.compactMap { bpAsFormula($0)?.name }
    }

    @objc open func executeInstallation() {
        isRunningTask = true
        setOkButtonEnabled(false)
        progressIndicator?.startAnimation(nil)
        syncInstallationHostState()
        if windowOperation == .upgrade && formulae != nil {
            upgradeProgress = Progress(totalUnitCount: 1)
        }

        let op = self.windowOperation
        nonisolated(unsafe) let capturedFormulae = self.formulae
        nonisolated(unsafe) let capturedOptions = self.options
        let capturedZap = self.zapCask
        let capturedProgress = self.upgradeProgress
        let tv = self.recordTextView

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let displayTerminalOutput: @Sendable (String) -> Void = { output in
                tv?.appendOutput(output)
                DispatchQueue.main.async {
                    self?.installationHost?.syncLogFromTextView()
                }
            }

            guard let homebrewInterface = bpSharedHomebrewInterface() else {
                self?.finishTask()
                return
            }

            var statusResult = false
            var upResult: BPUpgradeResult?

            if op == .install {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    if formula.cask {
                        statusResult = homebrewInterface.installCask(formula.name, withReturnBlock: displayTerminalOutput)
                    } else {
                        statusResult = homebrewInterface.installFormula(formula.name, withOptions: capturedOptions, andReturnBlock: displayTerminalOutput)
                    }
                }
            } else if op == .uninstall {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    if formula.cask {
                        statusResult = homebrewInterface.uninstallCask(formula.name, zap: capturedZap, withReturnBlock: displayTerminalOutput)
                    } else {
                        statusResult = homebrewInterface.uninstallFormula(formula.name, withReturnBlock: displayTerminalOutput)
                    }
                }
            } else if op == .upgrade {
                let res = homebrewInterface.upgradeSelectionReporting(capturedFormulae ?? [], progress: capturedProgress, withReturnBlock: displayTerminalOutput)
                upResult = res
                statusResult = res?.succeeded ?? false
                for batch in res?.batches ?? [] {
                    let statusKey: String
                    switch batch.status {
                    case .succeeded:   statusKey = "Updates_Command_Succeeded"
                    case .failed:      statusKey = "Updates_Command_Failed"
                    case .cancelled:   statusKey = "Updates_Command_Cancelled"
                    case .unattempted: statusKey = "Updates_Command_Unattempted"
                    @unknown default:  statusKey = "Updates_Command_Failed"
                    }
                    let line = String(format: NSLocalizedString(statusKey, comment: ""), batch.arguments.joined(separator: " "))
                    displayTerminalOutput("\n\(line)\n")
                }
            } else if op == .tap {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    statusResult = homebrewInterface.tapRepository(formula.name, withReturnsBlock: displayTerminalOutput)
                }
            } else if op == .untap {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    statusResult = homebrewInterface.untapRepository(formula.name, withReturnsBlock: displayTerminalOutput)
                }
            } else if op == .cleanup {
                statusResult = homebrewInterface.runCleanup(withReturnBlock: displayTerminalOutput)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.upgradeResult = upResult
                self.operationStatus = statusResult
                self.finishTask()
            }
        }
    }

    @objc nonisolated open func finishTask() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.upgradeWorkerFinished = true
            self.isRunningTask = false
            self.recordTextView?.flushPendingOutput()
            self.progressIndicator?.stopAnimation(nil)
            self.setOkButtonEnabled(true)
            self.cancelButton?.isEnabled = false

            let succeeded = self.operationStatus && !self.wasCancelled
            let cancelled = self.wasCancelled || (self.upgradeResult?.cancelled == true)
            let failureTitle = NSLocalizedString(cancelled ? "Updates_Task_Cancelled" : "Homebrew_Task_Failed", comment: "")
            let title = succeeded ? NSLocalizedString("Homebrew_Task_Finished", comment: "") : failureTitle
            let currentTitle = self.windowTitleLabel?.stringValue ?? ""
            let currentNames = self.formulaNameLabel?.stringValue ?? ""
            let desc = "\(currentTitle) \(currentNames)"

            self.windowTitleLabel?.stringValue = cancelled
                ? title
                : (succeeded ? currentTitle : "\(currentTitle) — \(failureTitle)")
            self.syncInstallationHostState()

            bpSharedAppDelegate()?.requestUserAttention(withMessageTitle: title, andDescription: desc)

            if let app = NSApp {
                NSAccessibility.post(
                    element: app,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: title,
                        .priority: NSAccessibilityPriorityLevel.high.rawValue
                    ]
                )
            }
            if let okResponder = self.okButton as? NSResponder,
               let rawWin = self.sheetWindowObject(),
               rawWin.isKind(of: NSWindow.self),
               let realWin = rawWin as? NSWindow {
                realWin.makeFirstResponder(okResponder)
            }
        }
    }

    @objc(cancelAction:)
    open func cancelAction(_ sender: Any?) {
        wasCancelled = true
        cancelButton?.isEnabled = false
        setOkButtonEnabled(upgradeProgress == nil)
        if upgradeProgress != nil {
            windowTitleLabel?.stringValue = NSLocalizedString("Updates_Cancelling", comment: "")
        }
        syncInstallationHostState()

        let msgKey = upgradeProgress != nil ? "Updates_Cancelling" : "Installation_Window_Cancelled"
        recordTextView?.appendOutput("\n\(NSLocalizedString(msgKey, comment: ""))\n")
        recordTextView?.flushPendingOutput()
        installationHost?.syncLogFromTextView()

        upgradeProgress?.cancel()
        if let interface = bpSharedHomebrewInterface() {
            if upgradeProgress == nil || interface.brewTransport == BPBrewTransport.helper.rawValue {
                interface.cancelCurrentOperation()
            }
        }
    }

    @objc(okAction:)
    open func okAction(_ sender: Any?) {
        if upgradeProgress != nil && !upgradeWorkerFinished {
            return
        }
        recordTextView?.clearOutput()
        recordTextView?.string = ""
        installationHost?.syncLogFromTextView()

        if let sheetWin = sheetWindowObject() {
            if let mainWindow = unsafeBitCast(sheetWin, to: BPSheetWindowMessaging.self).sheetParent {
                unsafeBitCast(mainWindow, to: BPSheetWindowMessaging.self).endSheet(sheetWin)
            }
        }
    }
}

@MainActor
@objc(BPInertInstallationWindowController)
public final class BPInertInstallationWindowController: BPInstallationWindowController {
    @objc public var recordedWindow: AnyObject?
    @objc public var parentAtExecution: AnyObject?
    @objc public var busyAtExecution: Bool = false
    @objc public var executions: UInt = 0

    public override init(window: NSWindow?) {
        super.init(window: window)
        if let recorderClass = NSClassFromString("BPSheetWindowRecorder") as? NSObject.Type {
            self.recordedWindow = recorderClass.init()
        }
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func sheetWindowObject() -> AnyObject? {
        return recordedWindow
    }

    public override var window: NSWindow? {
        get {
            guard let recordedWindow else { return nil }
            let raw = Unmanaged.passUnretained(recordedWindow).toOpaque()
            return Unmanaged<NSWindow>.fromOpaque(raw).takeUnretainedValue()
        }
        set {
            recordedWindow = newValue
        }
    }

    public override func executeInstallation() {
        executions += 1
        if let win = sheetWindowObject() {
            parentAtExecution = unsafeBitCast(win, to: BPSheetWindowMessaging.self).sheetParent
        }
        if let app = NSApp as AnyObject? {
            let appProxy = unsafeBitCast(app, to: BPSheetAppRecorderMessaging.self)
            if let del = appProxy.delegate ?? nil {
                let delProxy = unsafeBitCast(del, to: BPSheetDelegateRecorderMessaging.self)
                busyAtExecution = delProxy.runningBackgroundTask?() ?? delProxy.isRunningBackgroundTask?() ?? false
            }
            appProxy.events??.add("execute")
        }
        self.operationStatus = true
    }
}
