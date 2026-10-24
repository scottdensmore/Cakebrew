import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPUpdateViewController)
public final class BPUpdateViewController: NSViewController {
    @objc public var updateTextView: BPAutoScrollTextView?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var isPerformingUpdate: Bool = false
    @objc public var consoleHost: BPConsoleToolHost?

    override public func loadView() {
        let textView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 404, height: 232))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = BPStyle.defaultFixedWidthFont()
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        self.updateTextView = textView
        self.isPerformingUpdate = false

        let title = Bundle.main.localizedString(
            forKey: "a3Y-VX-bpV.title",
            value: NSLocalizedString("Homebrew Updater", comment: ""),
            table: "BPUpdateView"
        )
        let runTitle = Bundle.main.localizedString(
            forKey: "MVF-cn-lfW.title",
            value: NSLocalizedString("Update Homebrew", comment: ""),
            table: "BPUpdateView"
        )
        let clearTitle = Bundle.main.localizedString(
            forKey: "EE6-5g-Jos.title",
            value: NSLocalizedString("Clear Log", comment: ""),
            table: "BPUpdateView"
        )

        let host = BPConsoleToolHost(
            textView: textView,
            title: title,
            subtitle: nil,
            runButtonTitle: runTitle,
            clearButtonTitle: clearTitle
        )
        host.onRun = { [weak self] in
            self?.runStopUpdate(nil)
        }
        host.onClear = { [weak self] in
            self?.clearLogUpdate(nil)
        }
        self.consoleHost = host
        self.view = host.viewController.view
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            progressIndicator?.setAccessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
            updateTextView?.font = BPStyle.defaultFixedWidthFont()
            isPerformingUpdate = false
        }
    }

    override public var nibName: NSNib.Name? {
        "BPUpdateView"
    }

    @objc(runStopUpdate:)
    public func runStopUpdate(_ sender: Any?) {
        let appDelegate = bpSharedAppDelegate()
        if appDelegate?.isRunningBackgroundTask == true {
            appDelegate?.displayBackgroundWarning()
            return
        }
        appDelegate?.isRunningBackgroundTask = true

        updateTextView?.clearOutput()
        isPerformingUpdate = true
        consoleHost?.isRunning = true
        consoleHost?.syncLogFromTextView()
        progressIndicator?.startAnimation(sender)

        let textView = self.updateTextView
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = bpSharedHomebrewInterface()?.update { output in
                textView?.appendOutput(output)
                DispatchQueue.main.async {
                    self?.consoleHost?.syncLogFromTextView()
                }
            }
            DispatchQueue.main.async {
                textView?.flushPendingOutput()
                self?.progressIndicator?.stopAnimation(nil)
                self?.isPerformingUpdate = false
                self?.consoleHost?.isRunning = false
                self?.consoleHost?.syncLogFromTextView()
                bpSharedAppDelegate()?.isRunningBackgroundTask = false

                let title = NSLocalizedString("Homebrew_Task_Finished", comment: "")
                let desc = NSLocalizedString("Notification_Update", comment: "")
                bpSharedAppDelegate()?.requestUserAttention(withMessageTitle: title, andDescription: desc)
            }
        }
    }

    @objc(clearLogUpdate:)
    public func clearLogUpdate(_ sender: Any?) {
        updateTextView?.clearOutput()
        updateTextView?.string = ""
        consoleHost?.syncLogFromTextView()
    }
}
