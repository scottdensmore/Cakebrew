import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@objc(BPBackgroundView)
public final class BPBackgroundView: NSView {
    @objc public var backgroundColor: NSColor?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        if backgroundColor == nil {
            backgroundColor = .controlColor
            wantsLayer = true
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        backgroundColor?.setFill()
        dirtyRect.fill()
    }
}

