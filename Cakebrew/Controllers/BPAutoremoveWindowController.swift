import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPAutoremoveWindowController)
public final class BPAutoremoveWindowController: NSWindowController {
    @objc public var interface: AnyObject?
    @objc public var manager: AnyObject?
    @objc public var preview: BPAutoremovePreview?
    @objc public var operation: BPAutoremoveOperation?
    @objc public var previewProgress: Progress?
    @objc public var statusLabel: NSTextField?
    @objc public var outputView: BPAutoScrollTextView?
    @objc public var removeButton: NSButton?
    @objc public var cancelButton: NSButton?
    @objc public var autoremoveHost: BPAutoremoveHost?
    @objc public var busy: Bool = false

    @objc(presentForWindow:interface:manager:)
    public static func present(
        for parent: NSWindow?,
        interface: Any?,
        manager: Any?
    ) -> BPAutoremoveWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = BPAutoremoveWindowController(window: window)
        controller.interface = interface as AnyObject?
        controller.manager = manager as AnyObject?
        controller.buildContent()
        bpSharedAppDelegate()?.isRunningBackgroundTask = true
        parent?.beginSheet(window) { _ in
            bpSharedAppDelegate()?.isRunningBackgroundTask = false
        }
        controller.loadPreview()
        return controller
    }

    private func buildContent() {
        window?.title = NSLocalizedString("Remove Unused Dependencies", comment: "")
        statusLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Checking unused dependencies…", comment: ""))
        let outView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 280))
        outView.isEditable = false
        outView.isSelectable = true
        outView.isRichText = false
        outView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        outView.textColor = .textColor
        outView.backgroundColor = .textBackgroundColor
        outView.textContainerInset = NSSize(width: 8, height: 8)
        outView.autoresizingMask = [.width]
        outView.isVerticallyResizable = true
        outView.textContainer?.widthTracksTextView = true
        outView.setAccessibilityIdentifier("autoremove.output")
        outView.setAccessibilityLabel(NSLocalizedString("Unused dependency preview and command output", comment: ""))
        self.outputView = outView

        let remBtn = NSButton(
            title: NSLocalizedString("Remove Reviewed Dependencies", comment: ""),
            target: self,
            action: #selector(removeReviewed(_:))
        )
        remBtn.isEnabled = false
        self.removeButton = remBtn

        let canBtn = NSButton(
            title: NSLocalizedString("Cancel", comment: ""),
            target: self,
            action: #selector(cancelOrClose(_:))
        )
        canBtn.isEnabled = true
        self.cancelButton = canBtn

        let host = BPAutoremoveHost(outputTextView: outView)
        host.onRemove = { [weak self] in
            self?.removeReviewed(nil)
        }
        host.onCancelOrClose = { [weak self] in
            self?.cancelOrClose(nil)
        }
        self.autoremoveHost = host

        if let contentView = window?.contentView {
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
        syncAutoremoveHostState()
    }

    @objc public func syncAutoremoveHostState() {
        autoremoveHost?.candidateCount = (preview?.valid == true) ? (preview?.names.count ?? 0) : 0
        autoremoveHost?.update(
            statusText: statusLabel?.stringValue ?? "",
            removeEnabled: removeButton?.isEnabled ?? false,
            cancelTitle: cancelButton?.title ?? "",
            cancelEnabled: cancelButton?.isEnabled ?? true,
            busy: busy
        )
        autoremoveHost?.syncLogFromTextView()
    }

    private func loadPreview() {
        busy = true
        syncAutoremoveHostState()
        let progress = Progress(totalUnitCount: 1)
        self.previewProgress = progress
        nonisolated(unsafe) let iface = self.interface
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let preview = bpAsHomebrewInterface(iface)?.previewAutoremove(withProgress: progress)
                ?? BPAutoremovePreview.preview(withOutput: nil, succeeded: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.preview = preview
                self.outputView?.string = preview.rawOutput
                self.cancelButton?.isEnabled = true
                if progress.isCancelled {
                    self.statusLabel?.stringValue = NSLocalizedString("Cancelled before removal. Nothing was removed.", comment: "")
                } else if !preview.valid {
                    self.statusLabel?.stringValue = NSLocalizedString("The unused dependency preview could not be verified. Nothing can be removed.", comment: "")
                } else if preview.names.isEmpty {
                    self.statusLabel?.stringValue = NSLocalizedString("No unused dependencies to remove.", comment: "")
                } else {
                    self.statusLabel?.stringValue = String.localizedStringWithFormat(
                        NSLocalizedString("Review %lu unused dependencies before removal.", comment: ""),
                        UInt(preview.names.count)
                    )
                    self.removeButton?.isEnabled = true
                }
                self.cancelButton?.title = NSLocalizedString("Close", comment: "")
                self.syncAutoremoveHostState()
            }
        }
    }

    @objc(removeReviewed:)
    public func removeReviewed(_ sender: Any?) {
        guard !busy,
              removeButton?.isEnabled == true,
              let preview,
              preview.valid,
              !preview.names.isEmpty else {
            return
        }
        busy = true
        removeButton?.isEnabled = false
        cancelButton?.title = NSLocalizedString("Cancel", comment: "")
        statusLabel?.stringValue = NSLocalizedString("Rechecking and removing reviewed dependencies…", comment: "")
        syncAutoremoveHostState()

        let op = BPAutoremoveOperation(preview: preview, interface: interface)
        self.operation = op
        let outView = self.outputView
        outView?.appendOutput("\n")
        op.start(withOutput: { [weak self] chunk in
            outView?.appendOutput(chunk)
            DispatchQueue.main.async {
                self?.autoremoveHost?.syncLogFromTextView()
            }
        }, completion: { [weak self] _, _, attempted, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.outputView?.flushPendingOutput()
                self.cancelButton?.isEnabled = false
                self.syncAutoremoveHostState()
                let finished: @Sendable (Bool) -> Void = { [weak self] refreshed in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if refreshed {
                            self.statusLabel?.stringValue = message
                        } else {
                            let suffix = NSLocalizedString(
                                "Some formula or service lists could not be refreshed. Previous values were retained; refresh again before another operation.",
                                comment: ""
                            )
                            self.statusLabel?.stringValue = "\(message)\n\(suffix)"
                        }
                        self.busy = false
                        self.cancelButton?.title = NSLocalizedString("Close", comment: "")
                        self.cancelButton?.isEnabled = true
                        self.syncAutoremoveHostState()
                    }
                }
                if attempted, let mgr = bpAsHomebrewManager(self.manager) {
                    mgr.refreshFormulaStateAfterRemoval(withCompletion: finished)
                } else {
                    finished(true)
                }
            }
        })
    }

    @objc(cancelOrClose:)
    public func cancelOrClose(_ sender: Any?) {
        if busy {
            cancelButton?.isEnabled = false
            statusLabel?.stringValue = NSLocalizedString("Cancelling; waiting for Homebrew to stop…", comment: "")
            syncAutoremoveHostState()
            if let operation {
                operation.cancel()
            } else {
                previewProgress?.cancel()
            }
        } else if let window = self.window {
            window.sheetParent?.endSheet(window)
        }
    }
}

