import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

// MARK: - Swift 6 AppKit & Presentation Views / Window Controllers

@objc(BPStyle)
public final class BPStyle: NSObject {
    @objc public static func defaultFixedWidthFont() -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)
    }

    @objc public static func toolbarSize() -> NSToolbar.SizeMode {
        return .default
    }

    @objc public static func toolbarImageForInstall() -> NSImage? {
        return appropriateIconForToolbar(name: "download", symbol: "plus.circle.fill")
    }

    @objc public static func toolbarImageForUninstall() -> NSImage? {
        return appropriateIconForToolbar(name: "delete", symbol: "xmark.circle.fill")
    }

    @objc public static func toolbarImageForTap() -> NSImage? {
        return appropriateIconForToolbar(name: "download", symbol: "plus.circle.fill")
    }

    @objc public static func toolbarImageForUntap() -> NSImage? {
        return appropriateIconForToolbar(name: "delete", symbol: "xmark.circle.fill")
    }

    @objc public static func toolbarImageForUpdate() -> NSImage? {
        return appropriateIconForToolbar(name: "reload", symbol: "arrow.triangle.2.circlepath.circle.fill")
    }

    @objc public static func toolbarImageForMoreInformation() -> NSImage? {
        return appropriateIconForToolbar(name: "label", symbol: "info.circle.fill")
    }

    @objc public static func toolbarImageForUpgrade() -> NSImage? {
        return appropriateIconForToolbar(name: "globe", symbol: "globe")
    }

    @objc public static func toolbarImageForCancel() -> NSImage? {
        return appropriateIconForToolbar(name: "cancel", symbol: "stop.circle")
    }

    private static func appropriateIconForToolbar(name: String, symbol: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(scale: .medium)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.isTemplate = true
        return configured
    }

    @objc public static func popoverTitleColor() -> NSColor {
        return .textColor
    }

    @objc public static func popoverTextViewColor() -> NSColor {
        return .textColor
    }
}
