import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPLoadingView)
public final class BPLoadingView: NSView {
    @objc public var view: NSView?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var loadingHost: BPLoadingHost?

    public override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            progressIndicator?.startAnimation(self)
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        let host = BPLoadingHost()
        self.loadingHost = host
        let hostView = host.viewController.view
        hostView.frame = bounds
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
}

