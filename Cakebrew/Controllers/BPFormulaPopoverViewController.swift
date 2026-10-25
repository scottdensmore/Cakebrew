import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@objc private protocol BPInformationHostMessaging: NSObjectProtocol {
    var viewController: NSViewController { get }
    @objc(beginWithName:cask:infoType:)
    func begin(withName name: String?, cask: Bool, infoType: Int) -> UInt64
    @objc(receiveInformation:website:name:cask:infoType:generation:)
    func receiveInformation(
        _ information: String?,
        website: URL?,
        name: String?,
        cask: Bool,
        infoType: Int,
        generation: UInt64
    )
    @objc(close)
    func close()
}

@objc private protocol BPPopoverMessaging: NSObjectProtocol {
    var contentViewController: NSViewController? { get set }
    var behavior: NSPopover.Behavior { get set }
}

@MainActor
@objc(BPFormulaPopoverViewController)
public final class BPFormulaPopoverViewController: NSViewController {
    @objc public var formulaTextView: NSTextView?
    @objc public weak var formulaTitleLabel: NSTextField?
    @objc public weak var formulaPopover: NSPopover?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var timedDispatch: BPTimedDispatch?
    @objc public var informationHost: AnyObject?
    @objc public var retainedPopover: NSPopover?
    @objc public var dependentsProvider: (@Sendable (String, Bool) -> String?)?

    @objc public var infoType: BPFormulaInfoType = .general {
        didSet {
            activeInformationHost?.close()
            popoverBridge?.behavior = (infoType == .general) ? .transient : .semitransient
        }
    }

    @objc(formulaObject) public weak var formula: AnyObject? {
        didSet {
            handleFormulaChanged()
        }
    }

    private var activeInformationHost: BPInformationHostMessaging? {
        guard let host = informationHost else { return nil }
        return unsafeBitCast(host, to: BPInformationHostMessaging.self)
    }

    private var popoverBridge: BPPopoverMessaging? {
        guard let pop = formulaPopover as AnyObject? else { return nil }
        return unsafeBitCast(pop, to: BPPopoverMessaging.self)
    }

    override public func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))
        if formulaPopover == nil {
            let pop = NSPopover()
            retainedPopover = pop
            formulaPopover = pop
        }
        awakeFromNib()
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            formulaTextView?.font = BPStyle.defaultFixedWidthFont()
            formulaTextView?.textColor = BPStyle.popoverTextViewColor()
            popoverBridge?.contentViewController = self
            timedDispatch = BPTimedDispatch()
            formulaTitleLabel?.textColor = BPStyle.popoverTitleColor()
            infoType = .general
            NotificationCenter.default.removeObserver(self, name: NSPopover.willCloseNotification, object: nil)
            if let pop = formulaPopover {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(informationPopoverWillClose(_:)),
                    name: NSPopover.willCloseNotification,
                    object: pop
                )
            }
        }
    }

    @objc(informationPopoverWillClose:)
    public func informationPopoverWillClose(_ notification: Notification) {
        activeInformationHost?.close()
    }

    private func handleFormulaChanged() {
        activeInformationHost?.close()
        formulaTextView?.string = ""
        progressIndicator?.stopAnimation(nil)
        guard let formulaObj = formula, let f = bpAsFormula(formulaObj) else { return }

        if informationHost == nil {
            informationHost = BPFormulaInformationHost()
        }
        guard let host = activeInformationHost else { return }
        let name = f.name ?? ""
        let cask = f.cask
        let currentInfoType = self.infoType
        let generation = host.begin(withName: name, cask: cask, infoType: currentInfoType.rawValue)
        popoverBridge?.contentViewController = host.viewController

        if currentInfoType != .general {
            if cask {
                host.receiveInformation(
                    nil,
                    website: nil,
                    name: name,
                    cask: cask,
                    infoType: currentInfoType.rawValue,
                    generation: generation
                )
                return
            }
            let onlyInstalled = (currentInfoType == .installedDependents)
            let provider = self.dependentsProvider
            timedDispatch?.scheduleDispatch(
                afterTimeInterval: 0.0,
                in: DispatchQueue.global(qos: .background)
            ) { [weak self] in
                let dependents = provider != nil
                    ? provider?(name, onlyInstalled)
                    : bpSharedHomebrewInterface()?.dependants(forFormulaName: name, onlyInstalled: onlyInstalled)
                DispatchQueue.main.async {
                    self?.activeInformationHost?.receiveInformation(
                        dependents,
                        website: nil,
                        name: name,
                        cask: cask,
                        infoType: currentInfoType.rawValue,
                        generation: generation
                    )
                }
            }
            return
        }

        if let info = f.information {
            host.receiveInformation(
                info,
                website: f.website,
                name: name,
                cask: cask,
                infoType: currentInfoType.rawValue,
                generation: generation
            )
            return
        }

        nonisolated(unsafe) let unsafeFormula = f
        timedDispatch?.scheduleDispatch(
            afterTimeInterval: 0.3,
            in: DispatchQueue.global(qos: .background)
        ) { [weak self] in
            unsafeFormula.needsInformation = true
            let information = unsafeFormula.information
            let website = unsafeFormula.website
            DispatchQueue.main.async {
                self?.activeInformationHost?.receiveInformation(
                    information,
                    website: website,
                    name: name,
                    cask: cask,
                    infoType: currentInfoType.rawValue,
                    generation: generation
                )
            }
        }
    }


    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
