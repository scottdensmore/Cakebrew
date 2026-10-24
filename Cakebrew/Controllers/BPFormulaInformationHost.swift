import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
private final class BPFormulaInformationPresentation: ObservableObject {
    @Published var state = BPFormulaInformationState()
}

/// This facade exposes only Cocoa types in the generated Objective-C header.
@MainActor
@objc(BPFormulaInformationHost)
public final class BPFormulaInformationHost: NSObject {
    private let presentation = BPFormulaInformationPresentation()
    @objc public let viewController: NSViewController

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPFormulaInformationView(presentation: presentation))
        host.preferredContentSize = NSSize(width: 460, height: 320)
        viewController = host
        super.init()
    }

    @objc(beginWithName:cask:)
    public func begin(name: String, cask: Bool) -> UInt64 {
        begin(name: name, cask: cask, infoType: 0)
    }

    @objc(beginWithName:cask:infoType:)
    public func begin(name: String, cask: Bool, infoType: Int) -> UInt64 {
        presentation.state.begin(name: name, cask: cask, mode: BPFormulaInformationMode(rawInfoType: infoType)).generation
    }

    @objc(receiveInformation:website:name:cask:generation:)
    public func receive(information: String?, website: URL?, name: String, cask: Bool, generation: UInt64) {
        receive(information: information, website: website, name: name, cask: cask, infoType: 0, generation: generation)
    }

    @objc(receiveInformation:website:name:cask:infoType:generation:)
    public func receive(information: String?, website: URL?, name: String, cask: Bool, infoType: Int, generation: UInt64) {
        let mode = BPFormulaInformationMode(rawInfoType: infoType)
        presentation.state.receive(request: BPFormulaInformationRequest(
            identity: BPFormulaInformationIdentity(name: name, cask: cask, mode: mode), generation: generation),
            information: information, website: website)
    }

    @objc public func close() {
        presentation.state.close()
    }

    @objc
    @discardableResult
    public func copyInformationToPasteboard() -> String {
        let text = presentation.state.information ?? ""
        guard !text.isEmpty else { return "" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }
}

func BPFormulaInformationAttributedText(_ information: String) -> AttributedString {
    let attributed = NSMutableAttributedString(string: information)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        let range = NSRange(location: 0, length: attributed.length)
        detector.enumerateMatches(in: information, range: range) { match, _, _ in
            if let match, let url = match.url {
                attributed.addAttribute(.link, value: url, range: match.range)
            }
        }
    }
    return AttributedString(attributed)
}

@MainActor
private struct BPFormulaInformationView: View {
    @ObservedObject var presentation: BPFormulaInformationPresentation

    private var mode: BPFormulaInformationMode {
        presentation.state.request?.identity.mode ?? .general
    }

    private var isCask: Bool {
        presentation.state.request?.identity.cask ?? false
    }

    private var headerSymbolName: String {
        switch mode {
        case .general:
            return isCask ? "macwindow" : "shippingbox.fill"
        case .installedDependents, .allDependents:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var kindBadgeText: String {
        isCask
            ? BPLocalizedWithFallback("Casks", fallback: "Cask")
            : BPLocalizedWithFallback("Formulae", fallback: "Formula")
    }

    private var titleText: String {
        let name = presentation.state.request?.identity.name ?? ""
        switch mode {
        case .general:
            return String(format: NSLocalizedString("Information_Title", comment: "Package information popover title"), name)
        case .installedDependents:
            return String(format: NSLocalizedString("Formula_Installed_Dependents_Title", comment: "Installed dependents popover title"), name)
        case .allDependents:
            return String(format: NSLocalizedString("Formula_All_Dependents_Title", comment: "All dependents popover title"), name)
        }
    }

    private var titleIdentifier: String {
        mode == .general ? "formula.information.title" : "formula.dependents.title"
    }

    private var loadingIdentifier: String {
        mode == .general ? "formula.information.loading" : "formula.dependents.loading"
    }

    private var textIdentifier: String {
        mode == .general ? "formula.information.text" : "formula.dependents.text"
    }

    private var unavailableText: String {
        switch mode {
        case .general:
            return NSLocalizedString("Information_Unavailable", comment: "No package information was returned")
        case .installedDependents, .allDependents:
            return NSLocalizedString("Info_View_Empty_Value", comment: "No dependents placeholder")
        }
    }

    private var unavailableIdentifier: String {
        mode == .general ? "formula.information.unavailable" : "formula.dependents.empty"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: headerSymbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text(titleText)
                    .font(.headline)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier)

                Text(kindBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )

                Spacer(minLength: 4)

                if let website = presentation.state.website {
                    Button {
                        NSWorkspace.shared.open(website)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.borderless)
                    .help(website.absoluteString)
                    .accessibilityIdentifier("formula.information.website")
                }

                if let info = presentation.state.information, !info.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help(BPLocalizedWithFallback("Services_Copy_Output", fallback: "Copy Output"))
                    .accessibilityIdentifier("formula.information.copy")
                }
            }
            Divider()
            if presentation.state.isLoading {
                ProgressView(NSLocalizedString("Loading_Status_Default", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(loadingIdentifier)
            } else if let information = presentation.state.information {
                ScrollView {
                    Text(BPFormulaInformationAttributedText(information))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(textIdentifier)
                }
            } else {
                Text(unavailableText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier(unavailableIdentifier)
            }
        }
        .padding(16)
        .frame(width: 460, height: 320)
    }
}

