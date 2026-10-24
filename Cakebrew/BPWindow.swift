import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPWindow)
public final class BPWindow: NSWindow {
    override public init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        sharedInit()
    }

    private func sharedInit() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        toolbarStyle = .unified
        registerForDraggedTypes([.fileURL])
    }

    @objc public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        brewfile(fromDrag: sender) != nil ? .copy : []
    }

    @objc public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    @objc public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let brewfile = brewfile(fromDrag: sender) else { return false }
        if let target = bpSharedAppDelegate()?.brewfileImportTarget {
            let importer = unsafeBitCast(target, to: BPBrewfileImportingObjCBridge.self)
            importer.importBrewfile(at: brewfile)
        }
        return true
    }

    @objc(brewfileFromDrag:)
    public func brewfile(fromDrag sender: any NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return BPBrewfile.brewfileURLs(from: urls).first
    }
}

