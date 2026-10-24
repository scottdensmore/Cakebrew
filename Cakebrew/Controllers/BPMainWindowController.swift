import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPMainWindowController)
public final class BPMainWindowController: NSWindowController {
    @objc public weak var sidebarView: NSScrollView?
    @objc public weak var windowContentView: NSView?
    @objc public private(set) var splitViewController: NSSplitViewController?

    @objc(toggleSidebar:)
    public func toggleSidebar(_ sender: Any?) {
        splitViewController?.toggleSidebar(sender)
    }

    @objc public func setUpViews() {
        guard let window = self.window else { return }
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic

        let splitVC = NSSplitViewController(nibName: nil, bundle: nil)
        splitVC.addSplitViewItem(makeSidebarSplitViewItem())
        splitVC.addSplitViewItem(makeContentSplitViewItem())
        self.splitViewController = splitVC

        let splitControllerView = splitVC.view
        guard let contentView = window.contentView else { return }

        splitControllerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitControllerView)

        NSLayoutConstraint.activate([
            splitControllerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitControllerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitControllerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitControllerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc(setContentViewHidden:)
    public func setContentViewHidden(_ hide: Bool) {
        windowContentView?.isHidden = hide
    }

    private func makeSidebarSplitViewItem() -> NSSplitViewItem {
        let vc = NSViewController(nibName: nil, bundle: nil)
        if let sidebarView {
            vc.view = sidebarView
        }
        let item = NSSplitViewItem(sidebarWithViewController: vc)
        item.minimumThickness = 190.0
        item.maximumThickness = 280.0
        return item
    }

    private func makeContentSplitViewItem() -> NSSplitViewItem {
        let vc = NSViewController(nibName: nil, bundle: nil)
        if let windowContentView {
            vc.view = windowContentView
        }
        return NSSplitViewItem(viewController: vc)
    }
}

