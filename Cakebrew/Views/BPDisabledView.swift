import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPDisabledView)
public final class BPDisabledView: NSView {
    @objc public var view: NSView?
    @objc public weak var titleField: NSTextField?
    @objc public weak var messageField: NSTextField?
    @objc public weak var retryButton: NSButton?
    @objc public weak var installButton: NSButton?
    @objc public var disabledHost: BPDisabledHost?
    @objc public var retryEnabled: Bool = true
    @objc public var retryHandler: (() -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        retryEnabled = true
        let host = BPDisabledHost()
        host.onRetry = { [weak self] in
            self?.retry(nil)
        }
        host.onOpenInstructions = { [weak self] in
            self?.openInstallationInstructions(nil)
        }
        self.disabledHost = host

        let hostView = host.viewController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostView)
        self.view = hostView

        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: topAnchor),
            hostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc(showDiscoveryResult:checking:)
    public func showDiscoveryResult(_ result: Int, checking: Bool) {
        self.retryEnabled = !checking
        self.retryButton?.isEnabled = !checking
        let title: String
        let message: String
        if checking {
            title = NSLocalizedString("Checking for Homebrew…", comment: "")
            message = NSLocalizedString("Cakebrew is checking your login shell for Homebrew. This may take a moment.", comment: "")
        } else {
            switch result {
            case 2: // BPHomebrewDiscoveryMissing
                title = NSLocalizedString("Homebrew wasn’t found", comment: "")
                message = NSLocalizedString("Cakebrew couldn’t find Homebrew in your login shell’s PATH. Open brew.sh for installation instructions, or fix your shell configuration, then choose Try Again.", comment: "")
            case 3: // BPHomebrewDiscoveryInvalidShell
                title = NSLocalizedString("Your login shell is unavailable", comment: "")
                message = NSLocalizedString("Cakebrew needs an executable login shell listed in /etc/shells. Check your shell configuration, then choose Try Again. Homebrew installation instructions are available at brew.sh.", comment: "")
            default:
                title = NSLocalizedString("Homebrew couldn’t be checked", comment: "")
                message = NSLocalizedString("Your login shell didn’t return a usable Homebrew executable. Check its startup configuration and PATH, then choose Try Again. Installation instructions are available at brew.sh.", comment: "")
            }
        }
        titleField?.stringValue = title
        messageField?.stringValue = message
        disabledHost?.update(title: title, message: message, retryEnabled: !checking, checking: checking)
    }

    @objc(retry:)
    public func retry(_ sender: Any?) {
        if retryEnabled {
            retryHandler?()
        }
    }

    @objc(openInstallationInstructions:)
    public func openInstallationInstructions(_ sender: Any?) {
        if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
    }
}
