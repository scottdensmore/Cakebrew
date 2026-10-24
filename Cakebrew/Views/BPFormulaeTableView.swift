import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

// MARK: - Swift 6 Wave 8: Dock Menu Protocols, Table View, Background Updater, Services, Installation & AppDelegate

@objc(BPDockMenuActions)
public protocol BPDockMenuActions: NSObjectProtocol {
    @objc(updateHomebrew:)
    func updateHomebrew(_ sender: Any?)
    @objc(upgradeAllOutdatedFormulae:)
    func upgradeAllOutdatedFormulae(_ sender: Any?)
    @objc(showUnifiedUpdates:)
    func showUnifiedUpdates(_ sender: Any?)
}

@objc(BPDockMenuTarget)
public protocol BPDockMenuTarget: BPDockMenuActions {
    @objc(isHomebrewInstalled)
    func isHomebrewInstalled() -> Bool
}

@objc(BPWindowOperation)
public enum BPWindowOperation: UInt, Sendable {
    @objc(kBPWindowOperationInstall) case install = 0
    @objc(kBPWindowOperationUninstall) case uninstall = 1
    @objc(kBPWindowOperationUpgrade) case upgrade = 2
    @objc(kBPWindowOperationTap) case tap = 3
    @objc(kBPWindowOperationUntap) case untap = 4
    @objc(kBPWindowOperationCleanup) case cleanup = 5
}

@objc(BPFormulaeTableRequest)
public enum BPFormulaeTableRequest: Int {
    case primary = 0
    case uninstall = 1
}

@objc(BPFormulaeTableActionDelegate)
public protocol BPFormulaeTableActionDelegate: NSObjectProtocol {
    @objc(formulaeTableView:requestAction:)
    func formulaeTableView(_ table: BPFormulaeTableView, requestAction request: BPFormulaeTableRequest)
}

@objc private protocol BPFirstResponderProviding: NSObjectProtocol {
    @objc optional var firstResponder: AnyObject? { get }
}

@MainActor
@objc(BPFormulaeTableView)
open class BPFormulaeTableView: NSTableView {
    nonisolated(unsafe) private static var kvoContext: UInt8 = 0

    private static let columnIdentifierVersion = NSUserInterfaceItemIdentifier("Version")
    private static let columnIdentifierLatestVersion = NSUserInterfaceItemIdentifier("LatestVersion")
    private static let columnIdentifierStatus = NSUserInterfaceItemIdentifier("Status")
    private static let columnIdentifierName = NSUserInterfaceItemIdentifier("Name")
    private static let spaceCharacter: unichar = 0x0020

    @objc dynamic open var mode: BPListMode = .all
    @objc open weak var actionDelegate: (any BPFormulaeTableActionDelegate)?
    private var isObservingMode: Bool = false

    open override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            self.target = self
            self.doubleAction = #selector(performDoubleClickAction(_:))
            if !self.isObservingMode {
                self.addObserver(
                    self,
                    forKeyPath: "mode",
                    options: [.initial, .new],
                    context: &Self.kvoContext
                )
                self.isObservingMode = true
            }
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.mode = .all
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc open func configureTableForListing() {
        var totalWidth: CGFloat = 0
        var titleWidth: Int = 0

        if let superview = self.superview {
            totalWidth = superview.frame.size.width
            let marginsFrame = superview.layoutMarginsGuide.frame
            totalWidth -= marginsFrame.origin.x * 2
        }

        switch self.mode {
        case .all, .allCasks:
            titleWidth = Int(totalWidth - 125)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.width = CGFloat(Int((totalWidth - CGFloat(titleWidth)) * 0.90))
            allowsMultipleSelection = false

        case .installed, .pinned, .installedCasks:
            titleWidth = Int(totalWidth * 0.4)
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.width = CGFloat(Int(totalWidth)) * 0.55
            allowsMultipleSelection = false

        case .leaves:
            titleWidth = Int(totalWidth - 1)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            allowsMultipleSelection = false

        case .outdated, .outdatedCasks:
            titleWidth = Int(totalWidth * 0.4)
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.width = (totalWidth - CGFloat(titleWidth)) * 0.48
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.width = (totalWidth - CGFloat(titleWidth)) * 0.48
            allowsMultipleSelection = true

        case .search:
            titleWidth = Int(totalWidth - 90)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.width = (totalWidth - CGFloat(titleWidth)) * 0.90
            allowsMultipleSelection = false

        case .repositories:
            titleWidth = Int(totalWidth - 1)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            allowsMultipleSelection = false

        @unknown default:
            break
        }

        tableColumn(withIdentifier: Self.columnIdentifierName)?.width = CGFloat(titleWidth)
        needsLayout = true
    }

    open nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if context == &Self.kvoContext {
            if let obj = object as AnyObject?, obj === self, keyPath == "mode" {
                MainActor.assumeIsolated {
                    self.configureTableForListing()
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    @objc open func currentFirstResponder() -> AnyObject? {
        return self.window?.firstResponder
    }

    open override func performKeyEquivalent(with theEvent: NSEvent) -> Bool {
        let responder = currentFirstResponder()
        if responder !== self {
            return super.performKeyEquivalent(with: theEvent)
        }

        if self.selectedRow == -1 {
            return false
        }

        let chars = (theEvent.charactersIgnoringModifiers ?? "") as NSString
        if theEvent.type == .keyDown && chars.length == 1 {
            let key = chars.character(at: 0)
            if key == Self.spaceCharacter {
                spaceBarPressed()
                return true
            }
            let shortcuts: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if !theEvent.isARepeat && theEvent.modifierFlags.intersection(shortcuts).isEmpty {
                if key == unichar(NSCarriageReturnCharacter) || key == unichar(NSEnterCharacter) {
                    actionDelegate?.formulaeTableView(self, requestAction: .primary)
                    return true
                }
                if key == unichar(NSDeleteCharacter) || key == unichar(NSDeleteFunctionKey) {
                    actionDelegate?.formulaeTableView(self, requestAction: .uninstall)
                    return true
                }
            }
        }
        return false
    }

    @objc(performDoubleClickAction:)
    open func performDoubleClickAction(_ sender: Any?) {
        let row = self.clickedRow
        if row < 0 || row >= self.numberOfRows || !self.selectedRowIndexes.contains(row) {
            return
        }
        actionDelegate?.formulaeTableView(self, requestAction: .primary)
    }

    @objc open func spaceBarPressed() {
        NSApp.sendAction(NSSelectorFromString("showFormulaInfo:"), to: nil, from: self)
    }

    deinit {
        if isObservingMode {
            super.removeObserver(self, forKeyPath: "mode", context: &Self.kvoContext)
        }
    }
}

@MainActor
@objc(BPTableActionWindowStub)
public final class BPTableActionWindowStub: NSObject {
    @objc public weak var firstResponder: NSResponder?
}

@MainActor
@objc(BPActionTestTable)
public final class BPActionTestTable: BPFormulaeTableView {
    @objc public var testWindow: BPTableActionWindowStub?
    @objc public var testSelectedRow: Int = 0
    @objc public var spaceCount: Int = 0
    @objc public var testClickedRow: Int = 0

    public override func currentFirstResponder() -> AnyObject? {
        return testWindow?.firstResponder
    }

    public override var selectedRow: Int { testSelectedRow }
    public override var clickedRow: Int { testClickedRow }
    public override var numberOfRows: Int { 2 }
    public override var selectedRowIndexes: IndexSet {
        testSelectedRow < 0 ? IndexSet() : IndexSet(integer: testSelectedRow)
    }

    public override func spaceBarPressed() {
        spaceCount += 1
    }
}
