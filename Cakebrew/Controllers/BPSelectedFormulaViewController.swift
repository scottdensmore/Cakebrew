import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@objc(BPSelectedFormulaViewControllerDelegate)
public protocol BPSelectedFormulaViewControllerDelegate: NSObjectProtocol {
    @objc(selectedFormulaViewDidUpdateFormulaInfoForFormula:)
    func selectedFormulaViewDidUpdateFormulaInfo(forFormula formula: Any?)
    @objc optional func selectedFormulaViewDidRequestSelectRelatedFormulaNamed(_ formulaName: String)
    @objc optional func selectedFormulaViewDidRequestShowMoreInformation()
    @objc optional func selectedFormulaViewDidRequestOpenWebsite()
}

@objc private protocol BPSelectedFormulaHostMessaging: NSObjectProtocol {
    var viewController: NSViewController { get }
    @objc func clearSelection()
    @objc func showMultipleSelection()
    @objc(beginSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    func beginSelection(
        withName name: String,
        cask: Bool,
        installed: Bool,
        pinned: Bool,
        installPath: String?,
        latestVersion: String?,
        dependencies: String?,
        conflicts: String?,
        shortDescription: String?
    ) -> UInt64
    @objc(updateSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    func updateSelection(
        withName name: String,
        cask: Bool,
        installed: Bool,
        pinned: Bool,
        installPath: String?,
        latestVersion: String?,
        dependencies: String?,
        conflicts: String?,
        shortDescription: String?
    )
    @objc(receiveDependents:name:cask:generation:)
    func receiveDependents(_ dependents: [String], name: String, cask: Bool, generation: UInt64)
}

@MainActor
@objc(BPSelectedFormulaViewController)
public final class BPSelectedFormulaViewController: NSViewController {
    private static let formulaDidUpdateNotification = Notification.Name("BPFormulaDidUpdateNotification")

    @objc public private(set) var inspectorHost: BPSelectedFormulaHost?
    private var customInspectorHost: AnyObject?
    @objc public var timedDispatch: BPTimedDispatch?

    @objc public weak var delegate: (any BPSelectedFormulaViewControllerDelegate)?
    @objc public var dependentsProvider: (@Sendable (String, Bool) -> String?)?

    @objc public weak var formulaDescriptionLabel: NSTextField?
    @objc public weak var formulaPathLabel: NSTextField?
    @objc public weak var formulaVersionLabel: NSTextField?
    @objc public weak var formulaDependenciesLabel: NSTextField?
    @objc public weak var formulaConflictsLabel: NSTextField?
    @objc public weak var formulaDependentsLabel: NSTextField?
    @objc public weak var pinnedInfoRow: NSView?

    private var activeInspectorHost: BPSelectedFormulaHostMessaging? {
        guard let target = (customInspectorHost ?? inspectorHost) else { return nil }
        return unsafeBitCast(target, to: BPSelectedFormulaHostMessaging.self)
    }

    override public func setValue(_ value: Any?, forKey key: String) {
        if key == "inspectorHost" {
            nonisolated(unsafe) let unsafeValue = value
            MainActor.assumeIsolated {
                if let host = unsafeValue as? BPSelectedFormulaHost {
                    inspectorHost = host
                    customInspectorHost = nil
                } else {
                    customInspectorHost = unsafeValue as AnyObject?
                }
                configureInspectorHostCallbacks()
            }
            return
        }
        super.setValue(value, forKey: key)
    }

    override public init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        self.timedDispatch = BPTimedDispatch()
        self.inspectorHost = BPSelectedFormulaHost()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configureInspectorHostCallbacks()
    }

    required public init?(coder: NSCoder) {
        self.timedDispatch = BPTimedDispatch()
        self.inspectorHost = BPSelectedFormulaHost()
        super.init(coder: coder)
        configureInspectorHostCallbacks()
    }

    private func configureInspectorHostCallbacks() {
        guard let host = inspectorHost, customInspectorHost == nil else { return }
        host.onSelectRelatedPackage = { [weak self] packageName in
            guard let self, !packageName.isEmpty else { return }
            self.delegate?.selectedFormulaViewDidRequestSelectRelatedFormulaNamed?(packageName)
        }
        host.onShowMoreInfo = { [weak self] in
            guard let self else { return }
            self.delegate?.selectedFormulaViewDidRequestShowMoreInformation?()
        }
        host.onOpenWebsite = { [weak self] in
            guard let self else { return }
            self.delegate?.selectedFormulaViewDidRequestOpenWebsite?()
        }
    }

    override public func loadView() {
        if timedDispatch == nil {
            timedDispatch = BPTimedDispatch()
        }
        if inspectorHost == nil && customInspectorHost == nil {
            inspectorHost = BPSelectedFormulaHost()
        }
        configureInspectorHostCallbacks()
        if let view = activeInspectorHost?.viewController.view {
            self.view = view
        } else {
            self.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        }
    }

    @objc public var formulae: [Any]? {
        willSet {
            if let old = formulae {
                for item in old {
                    NotificationCenter.default.removeObserver(
                        self,
                        name: Self.formulaDidUpdateNotification,
                        object: item as AnyObject
                    )
                }
            }
        }
        didSet {
            if let current = formulae {
                for item in current {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(updateFormulaInformation(_:)),
                        name: Self.formulaDidUpdateNotification,
                        object: item as AnyObject
                    )
                }
            }
            handleFormulaeUpdated()
        }
    }

    private func handleFormulaeUpdated() {
        if inspectorHost == nil && customInspectorHost == nil {
            inspectorHost = BPSelectedFormulaHost()
            configureInspectorHostCallbacks()
        }
        if timedDispatch == nil {
            timedDispatch = BPTimedDispatch()
        }
        guard let formulae, !formulae.isEmpty else {
            activeInspectorHost?.clearSelection()
            return
        }
        if formulae.count > 1 {
            activeInspectorHost?.showMultipleSelection()
            return
        }
        guard let firstObj = formulae.first, let formula = bpAsFormula(firstObj) else {
            activeInspectorHost?.clearSelection()
            return
        }

        let name = formula.name ?? ""
        let cask = formula.cask
        let pinned = !cask && (bpSharedHomebrewManager()?.isFormulaPinned(firstObj as AnyObject) ?? false)
        let generation = activeInspectorHost?.beginSelection(
            withName: name,
            cask: cask,
            installed: formula.isInstalled(),
            pinned: pinned,
            installPath: formula.installPath,
            latestVersion: formula.latestVersion,
            dependencies: formula.dependencies,
            conflicts: formula.conflicts,
            shortDescription: formula.shortDescription
        ) ?? 0

        delegate?.selectedFormulaViewDidUpdateFormulaInfo(forFormula: firstObj)

        let provider = self.dependentsProvider
        nonisolated(unsafe) let unsafeFormula = formula
        timedDispatch?.scheduleDispatch(
            afterTimeInterval: 0.3,
            in: DispatchQueue.global(qos: .background)
        ) { [weak self] in
            unsafeFormula.needsInformation = true
            if cask { return }
            let raw = provider != nil
                ? provider?(name, true)
                : bpSharedHomebrewInterface()?.dependants(forFormulaName: name, onlyInstalled: true)
            let dependents = bpFormulaClass()?.names(fromListOutput: raw) ?? []
            DispatchQueue.main.async {
                self?.activeInspectorHost?.receiveDependents(
                    dependents,
                    name: name,
                    cask: cask,
                    generation: generation
                )
            }
        }
    }

    @objc(updateFormulaInformation:)
    public nonisolated func updateFormulaInformation(_ notification: Notification) {
        let updatedObj = notification.object
        nonisolated(unsafe) let unsafeUpdated = updatedObj
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let formulae = self.formulae, formulae.count == 1,
                      let firstObj = formulae.first, let formula = bpAsFormula(firstObj) else {
                    return
                }
                if let updated = bpAsFormula(unsafeUpdated),
                   (updated.cask != formula.cask || updated.name != formula.name) {
                    return
                }
                let pinned = !formula.cask && (bpSharedHomebrewManager()?.isFormulaPinned(firstObj as AnyObject) ?? false)
                self.activeInspectorHost?.updateSelection(
                    withName: formula.name ?? "",
                    cask: formula.cask,
                    installed: formula.isInstalled(),
                    pinned: pinned,
                    installPath: formula.installPath,
                    latestVersion: formula.latestVersion,
                    dependencies: formula.dependencies,
                    conflicts: formula.conflicts,
                    shortDescription: formula.shortDescription
                )
                self.delegate?.selectedFormulaViewDidUpdateFormulaInfo(forFormula: firstObj)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

