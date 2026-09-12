import AppKit
import SwiftUI

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
        presentation.state.begin(name: name, cask: cask).generation
    }

    @objc(receiveInformation:website:name:cask:generation:)
    public func receive(information: String?, website: URL?, name: String, cask: Bool, generation: UInt64) {
        presentation.state.receive(request: BPFormulaInformationRequest(
            identity: BPFormulaInformationIdentity(name: name, cask: cask), generation: generation),
            information: information, website: website)
    }

    @objc public func close() {
        presentation.state.close()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("Information_Title", comment: "Package information popover title"),
                        presentation.state.request?.identity.name ?? ""))
                .font(.headline)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("formula.information.title")
            Divider()
            if presentation.state.isLoading {
                ProgressView(NSLocalizedString("Loading_Status_Default", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("formula.information.loading")
            } else if let information = presentation.state.information {
                ScrollView {
                    Text(BPFormulaInformationAttributedText(information))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("formula.information.text")
                }
            } else {
                Text(NSLocalizedString("Information_Unavailable", comment: "No package information was returned"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier("formula.information.unavailable")
            }
        }
        .padding(16)
        .frame(width: 460, height: 320)
    }
}
