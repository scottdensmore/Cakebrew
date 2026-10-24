import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPEmptyStateView)
public final class BPEmptyStateView: NSView {
    private static let emptyStateViewTag = 0x43424553
    @objc public var host: BPEmptyStateHost?

    @objc(presentState:overView:)
    public static func presentState(_ state: BPEmptyState?, over container: NSView?) {
        guard let container else { return }
        for subview in container.subviews where subview.tag == emptyStateViewTag {
            subview.removeFromSuperview()
        }
        guard let state else { return }

        let title = NSLocalizedString(state.titleKey, comment: "")
        let message = NSLocalizedString(state.messageKey, comment: "")

        let view = BPEmptyStateView(frame: container.bounds)
        view.translatesAutoresizingMaskIntoConstraints = false
        let emptyHost = BPEmptyStateHost(
            symbolName: state.symbolName.isEmpty ? "tray" : state.symbolName,
            title: title,
            message: message
        )
        view.host = emptyHost

        let hostView = emptyHost.viewController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostView)
        container.addSubview(view)

        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.staticText)
        view.setAccessibilityLabel("\(title). \(message)")

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: view.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    public override var tag: Int {
        return Self.emptyStateViewTag
    }

    public override var isOpaque: Bool {
        return false
    }
}
