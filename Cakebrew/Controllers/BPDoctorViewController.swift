import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPDoctorViewController)
public final class BPDoctorViewController: NSViewController {
    @objc public var doctorTextView: BPAutoScrollTextView?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var isPerformingDoctor: Bool = false
    @objc public var consoleHost: BPConsoleToolHost?

    override public func loadView() {
        let textView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 232))
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
        self.doctorTextView = textView
        self.isPerformingDoctor = false

        let title = Bundle.main.localizedString(
            forKey: "UHp-GH-2qP.title",
            value: NSLocalizedString("Homebrew Doctor", comment: ""),
            table: "BPDoctorView"
        )
        let runTitle = Bundle.main.localizedString(
            forKey: "YyI-zq-THZ.title",
            value: NSLocalizedString("Run Doctor", comment: ""),
            table: "BPDoctorView"
        )
        let clearTitle = Bundle.main.localizedString(
            forKey: "AlR-6d-ju7.title",
            value: NSLocalizedString("Clear Log", comment: ""),
            table: "BPDoctorView"
        )

        let host = BPConsoleToolHost(
            textView: textView,
            title: title,
            subtitle: nil,
            runButtonTitle: runTitle,
            clearButtonTitle: clearTitle
        )
        host.onRun = { [weak self] in
            self?.runStopDoctor(nil)
        }
        host.onClear = { [weak self] in
            self?.clearLogDoctor(nil)
        }
        self.consoleHost = host
        self.view = host.viewController.view
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            progressIndicator?.setAccessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
            doctorTextView?.font = BPStyle.defaultFixedWidthFont()
            isPerformingDoctor = false
        }
    }

    override public var nibName: NSNib.Name? {
        "BPDoctorView"
    }

    @objc(runStopDoctor:)
    public func runStopDoctor(_ sender: Any?) {
        let appDelegate = bpSharedAppDelegate()
        if appDelegate?.isRunningBackgroundTask == true {
            appDelegate?.displayBackgroundWarning()
            return
        }
        appDelegate?.isRunningBackgroundTask = true

        doctorTextView?.clearOutput()
        isPerformingDoctor = true
        consoleHost?.isRunning = true
        consoleHost?.syncLogFromTextView()
        progressIndicator?.startAnimation(sender)

        let textView = self.doctorTextView
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = bpSharedHomebrewInterface()?.runDoctor { output in
                textView?.appendOutput(output)
                DispatchQueue.main.async {
                    self?.consoleHost?.syncLogFromTextView()
                }
            }
            DispatchQueue.main.async {
                textView?.flushPendingOutput()
                self?.progressIndicator?.stopAnimation(nil)
                self?.isPerformingDoctor = false
                self?.consoleHost?.isRunning = false
                self?.consoleHost?.syncLogFromTextView()
                bpSharedAppDelegate()?.isRunningBackgroundTask = false

                let title = NSLocalizedString("Homebrew_Task_Finished", comment: "")
                let desc = NSLocalizedString("Notification_Doctor", comment: "")
                bpSharedAppDelegate()?.requestUserAttention(withMessageTitle: title, andDescription: desc)
            }
        }
    }

    @objc(clearLogDoctor:)
    public func clearLogDoctor(_ sender: Any?) {
        doctorTextView?.clearOutput()
        doctorTextView?.string = ""
        consoleHost?.syncLogFromTextView()
    }
}

