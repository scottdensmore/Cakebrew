import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(DCOAboutWindowController)
public final class DCOAboutWindowController: NSWindowController {
    @objc public var infoView: NSView?
    @objc public var visitWebsiteButton: NSButton?
    @objc public var acknowledgementsButton: NSButton?
    @objc public private(set) var creditsTextView: NSTextView?
    @objc public private(set) var aboutHost: BPAboutWindowHost?
    @objc public var appAcknowledgements: NSAttributedString?

    @objc public var appName: String?
    @objc public var appVersion: String?
    @objc public var appCopyright: String?
    @objc public var appCredits: NSAttributedString?
    @objc public var appWebsiteURL: URL?

    @objc public var acknowledgementsPath: String? {
        didSet {
            loadAppAcknowledgements()
            if acknowledgementsPath == nil {
                acknowledgementsButton?.removeFromSuperview()
            }
            if let aboutHost {
                aboutHost.configure(
                    appName: appName ?? "Cakebrew",
                    appVersion: appVersion ?? "",
                    appCopyright: appCopyright ?? "",
                    hasAcknowledgements: ((acknowledgementsPath?.isEmpty == false) || (appAcknowledgements?.length ?? 0) > 0)
                )
            }
        }
    }


    public convenience init() {
        self.init(window: NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        ))
        window?.title = NSLocalizedString("About Cakebrew", comment: "")
        window?.isReleasedWhenClosed = false
        windowDidLoad()
    }

    public override init(window: NSWindow?) {
        super.init(window: window)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }


    public override func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    public override func windowDidLoad() {
        super.windowDidLoad()

        let bundleDict = Bundle.main.infoDictionary ?? [:]
        let resourceBundle = Bundle(for: Self.self)

        if appName == nil {
            appName = (bundleDict["CFBundleName"] as? String) ?? "Cakebrew"
        }

        if appVersion == nil {
            let version = (bundleDict["CFBundleVersion"] as? String) ?? "1"
            let shortVersion = (bundleDict["CFBundleShortVersionString"] as? String) ?? "1.0"
            appVersion = String(format: NSLocalizedString("Version %@ (Build %@)", comment: ""), shortVersion, version)
        }

        if appCopyright == nil {
            appCopyright = (bundleDict["NSHumanReadableCopyright"] as? String) ?? ""
        }

        if let button = visitWebsiteButton, !button.title.isEmpty, button.title.contains("%@"), let appName {
            button.title = String(format: button.title, appName)
        }

        if acknowledgementsPath == nil {
            acknowledgementsPath = Bundle.main.path(forResource: "Acknowledgements", ofType: "rtf")
                ?? resourceBundle.path(forResource: "Acknowledgements", ofType: "rtf")
        } else {
            loadAppAcknowledgements()
        }

        if appCredits == nil {
            loadAppCredits()
        }

        let textView = creditsTextView ?? NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
        self.creditsTextView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.setAccessibilityIdentifier("about.textView")
        applyDisplayedAttributedText(appCredits)

        let host = BPAboutWindowHost(creditsTextView: textView)
        host.configure(
            appName: appName ?? "Cakebrew",
            appVersion: appVersion ?? "",
            appCopyright: appCopyright ?? "",
            hasAcknowledgements: ((acknowledgementsPath?.isEmpty == false) || (appAcknowledgements?.length ?? 0) > 0)
        )
        host.onVisitWebsite = { [weak self] in
            self?.visitWebsite(nil)
        }
        host.onSelectTab = { [weak self] tabIndex in
            guard let self else { return }
            let targetText: NSAttributedString?
            if tabIndex == 1, let ack = self.appAcknowledgements, ack.length > 0 {
                targetText = ack
            } else {
                targetText = self.appCredits
            }
            self.applyDisplayedAttributedText(targetText)
        }
        self.aboutHost = host

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

    private func applyDisplayedAttributedText(_ attributedText: NSAttributedString?) {
        guard let storage = creditsTextView?.textStorage else { return }
        if let attributedText {
            storage.setAttributedString(attributedText)
        } else {
            creditsTextView?.string = ""
        }
    }

    private func normalizedAttributedString(fromRTFURL url: URL?) -> NSAttributedString? {
        guard let url,
              let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
            return nil
        }
        let mutableText = NSMutableAttributedString(attributedString: attributed)
        attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
            if value == nil && range.length > 0 {
                mutableText.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            }
        }
        return mutableText
    }

    private func loadAppCredits() {
        let creditsURL = Bundle.main.url(forResource: "Credits", withExtension: "rtf")
            ?? Bundle(for: Self.self).url(forResource: "Credits", withExtension: "rtf")
        if let credits = normalizedAttributedString(fromRTFURL: creditsURL) {
            appCredits = credits
        }
    }

    private func loadAppAcknowledgements() {
        let ackURL: URL?
        if let path = acknowledgementsPath, !path.isEmpty {
            ackURL = URL(fileURLWithPath: path)
        } else {
            ackURL = Bundle.main.url(forResource: "Acknowledgements", withExtension: "rtf")
                ?? Bundle(for: Self.self).url(forResource: "Acknowledgements", withExtension: "rtf")
        }
        if let ack = normalizedAttributedString(fromRTFURL: ackURL) {
            appAcknowledgements = ack
        }
    }

    @objc(visitWebsite:)
    public func visitWebsite(_ sender: Any?) {
        if let appWebsiteURL {
            NSWorkspace.shared.open(appWebsiteURL)
        }
    }

    @objc(showAcknowledgements:)
    public func showAcknowledgements(_ sender: Any?) {
        if let aboutHost, let ack = appAcknowledgements, ack.length > 0 {
            aboutHost.selectTab(at: 1)
            return
        }
        if let path = acknowledgementsPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

extension NSLayoutConstraint {
    @objc(activate:)
    public static func bp_activate(_ constraints: [NSLayoutConstraint]) {
        NSLayoutConstraint.activate(constraints)
    }
}

