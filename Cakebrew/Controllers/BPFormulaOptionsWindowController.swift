import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPFormulaOptionsWindowController)
public final class BPFormulaOptionsWindowController: NSWindowController, NSTableViewDelegate {
    private static let optionCommandKey = "formulaOptionCommand"
    private static let optionAppliedKey = "isFormulaOptionCommandApplied"
    private static let optionDescriptionKey = "formulaOptionDescription"

    @objc public weak var userHelpLabel: NSTextField?
    @objc public weak var formulaNameLabel: NSTextField?
    @objc public weak var optionDetailsTextField: NSTextField?
    @objc public weak var formulaOptionsTableView: NSTableView?
    @objc public var formulasArrayController: NSArrayController?

    @objc public var availableOptions: NSMutableArray = NSMutableArray()
    @objc public var formula: AnyObject?
    @objc public var optionsHost: BPFormulaOptionsHost?
    @objc public var installWithOptionsBlock: (([Any]) -> Void)?

    override public func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        awakeFromNib()
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            var names: [String] = []
            var explanations: [String] = []
            for case let dict as NSDictionary in availableOptions {
                names.append((dict[Self.optionCommandKey] as? String) ?? "")
                explanations.append((dict[Self.optionDescriptionKey] as? String) ?? "")
            }

            let host = BPFormulaOptionsHost()
            let formulaName = bpAsFormula(formula)?.name ?? ""
            host.configure(formulaName: formulaName, optionNames: names, optionExplanations: explanations)
            host.onOptionToggled = { [weak self] optionName, applied in
                guard let self else { return }
                for case let entry as NSMutableDictionary in self.availableOptions {
                    if (entry[Self.optionCommandKey] as? String) == optionName {
                        entry[Self.optionAppliedKey] = NSNumber(value: applied)
                    }
                }
            }
            host.onCancel = { [weak self] in
                self?.cancel(nil)
            }
            host.onInstall = { [weak self] in
                self?.install(nil)
            }
            self.optionsHost = host

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
    }

    @objc(runFormula:withCompletionBlock:)
    public static func runFormula(
        _ formula: Any?,
        withCompletionBlock completionBlock: (([Any]) -> Void)?
    ) -> BPFormulaOptionsWindowController {
        let controller = BPFormulaOptionsWindowController(windowNibName: "BPFormulaOptionsWindow")
        controller.formula = formula as AnyObject?
        controller.installWithOptionsBlock = completionBlock
        let available = NSMutableArray()
        if let options = bpAsFormula(formula)?.options {
            for case let option as BPFormulaOption in options {
                if let optionCommand = option.name {
                    let optionDescription = option.explanation ?? ""
                    let dict = NSMutableDictionary(dictionary: [
                        optionCommandKey: optionCommand,
                        optionAppliedKey: NSNumber(value: false),
                        optionDescriptionKey: optionDescription
                    ])
                    available.add(dict)
                }
            }
        }
        controller.availableOptions = available

        if let formulaWindow = controller.window {
            bpSharedAppDelegate()?.isRunningBackgroundTask = true
            NSApplication.shared.mainWindow?.beginSheet(formulaWindow) { returnCode in
                if returnCode == .stop {
                    let selected = controller.allSelectedOptions()
                    controller.installWithOptionsBlock?(selected)
                } else {
                    bpSharedAppDelegate()?.isRunningBackgroundTask = false
                }
            }
        }
        return controller
    }

    @objc public func allSelectedOptions() -> [Any] {
        if let host = optionsHost {
            return host.selectedOptionNames
        }
        var selected: [String] = []
        for case let entry as NSDictionary in availableOptions {
            if (entry[Self.optionAppliedKey] as? NSNumber)?.boolValue == true,
               let cmd = entry[Self.optionCommandKey] as? String {
                selected.append(cmd)
            }
        }
        return selected
    }

    @objc(cancel:)
    public func cancel(_ sender: Any?) {
        guard let window = self.window else { return }
        if let mainWindow = NSApplication.shared.mainWindow {
            mainWindow.endSheet(window, returnCode: .abort)
        } else {
            window.sheetParent?.endSheet(window, returnCode: .abort)
        }
    }

    @objc(install:)
    public func install(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        let formulaName = bpAsFormula(formula)?.name ?? ""
        alert.informativeText = String(
            format: NSLocalizedString("Formula_Options_Confirmation", comment: ""),
            formulaName
        )
        alert.window.title = NSLocalizedString("Cakebrew", comment: "")

        let returnValue = alert.runModal()
        let modalResponse: NSApplication.ModalResponse = (returnValue == .alertFirstButtonReturn) ? .stop : .abort
        guard let window = self.window else { return }
        if let mainWindow = NSApplication.shared.mainWindow {
            mainWindow.endSheet(window, returnCode: modalResponse)
        } else {
            window.sheetParent?.endSheet(window, returnCode: modalResponse)
        }
    }
}

