import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

/// Selectable, bounded log output. Scrolling follows new output until the user
/// scrolls back; VoiceOver sees text rather than a visual-only terminal surface.
@MainActor
private struct BPLogOutputView: View {
    let text: String
    var accessibilityID = "log.output"
    @State private var followOutput = true
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.isEmpty ? " " : text)
                        .accessibilityIdentifier(accessibilityID)
                        .accessibilityValue(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }.padding(12)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { followOutput = false }
            }
            .onChange(of: text) { _, _ in
                if followOutput { proxy.scrollTo("end", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !followOutput {
                    Button("Latest Output", systemImage: "arrow.down.to.line") {
                        followOutput = true
                        proxy.scrollTo("end", anchor: .bottom)
                    }.padding(8)
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - SwiftUI Empty State Host

@MainActor
@objc(BPEmptyStateHost)
public final class BPEmptyStateHost: NSObject {
    @objc public let viewController: NSViewController
    public let model: BPEmptyStateModel

    @objc(initWithSymbolName:title:message:)
    public init(symbolName: String, title: String, message: String) {
        let model = BPEmptyStateModel(symbolName: symbolName, title: title, message: message)
        self.model = model
        let host = NSHostingController(rootView: BPEmptyStateSwiftUIView(model: model))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }
}

@MainActor
private struct BPEmptyStateSwiftUIView: View {
    let model: BPEmptyStateModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: model.symbolName)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(model.title)
                .font(.system(size: NSFont.systemFontSize + 3, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityValue(model.title)
            Text(model.message)
                .font(.system(size: NSFont.smallSystemFontSize))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .accessibilityValue(model.message)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.combinedAccessibilityLabel)
        .accessibilityValue(model.combinedAccessibilityLabel)
    }
}

// MARK: - SwiftUI Loading Overlay Host

@MainActor
@objc(BPLoadingHost)
public final class BPLoadingHost: NSObject {
    @objc public let viewController: NSViewController

    public override init() {
        let host = NSHostingController(rootView: BPLoadingSwiftUIView())
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }
}

@MainActor
private struct BPLoadingSwiftUIView: View {
    private var loadingTitle: String {
        Bundle.main.localizedString(forKey: "a1c-mR-c5p.title", value: "Loading", table: "Loading")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(loadingTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityValue(loadingTitle)
                .accessibilityIdentifier("loading.title")
            ProgressView()
                .controlSize(.regular)
                .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                .accessibilityIdentifier("loading.progress")
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftUI Disabled / Recovery Overlay Host

@MainActor
private final class BPDisabledPresentation: ObservableObject {
    @Published var state = BPDisabledRecoveryState(
        title: NSLocalizedString("Homebrew wasn’t found", comment: ""),
        message: NSLocalizedString("Cakebrew couldn’t find Homebrew in your login shell’s PATH. Open brew.sh for installation instructions, or fix your shell configuration, then choose Try Again.", comment: ""),
        retryEnabled: true,
        isChecking: false
    )
    var onRetry: (() -> Void)?
    var onOpenInstructions: (() -> Void)?
}

@MainActor
@objc(BPDisabledHost)
public final class BPDisabledHost: NSObject {
    private let presentation = BPDisabledPresentation()
    @objc public let viewController: NSViewController

    @objc public var onRetry: (() -> Void)? {
        get { presentation.onRetry }
        set { presentation.onRetry = newValue }
    }

    @objc public var onOpenInstructions: (() -> Void)? {
        get { presentation.onOpenInstructions }
        set { presentation.onOpenInstructions = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPDisabledSwiftUIView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithTitle:message:retryEnabled:checking:)
    public func update(title: String, message: String, retryEnabled: Bool, checking: Bool) {
        presentation.state = BPDisabledRecoveryState(
            title: title,
            message: message,
            retryEnabled: retryEnabled,
            isChecking: checking
        )
    }
}

@MainActor
private struct BPDisabledSwiftUIView: View {
    @ObservedObject var presentation: BPDisabledPresentation

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: presentation.state.isChecking ? "magnifyingglass.circle" : "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text(presentation.state.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .accessibilityValue(presentation.state.title)
                .accessibilityIdentifier("homebrew.recovery.title")

            Text(presentation.state.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .accessibilityValue(presentation.state.message)
                .accessibilityIdentifier("homebrew.recovery.message")

            HStack(spacing: 12) {
                Button(NSLocalizedString("Try Again", comment: "")) {
                    presentation.onRetry?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.state.retryEnabled)
                .accessibilityIdentifier("homebrew.retry")

                Button(NSLocalizedString("Open brew.sh", comment: "")) {
                    presentation.onOpenInstructions?()
                }
                .accessibilityIdentifier("homebrew.install")
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftUI Console Tool Host (Doctor & Update)

@MainActor
private struct BPLogFilterBarView: View {
    @Binding var filterQuery: String
    let matchingLineCount: Int
    let totalLineCount: Int
    let filterFieldIdentifier: String
    let lineCountIdentifier: String
    let copyButtonIdentifier: String
    let copyEnabled: Bool
    let onCopyOutput: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: $filterQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .accessibilityIdentifier(filterFieldIdentifier)
                if !filterQuery.isEmpty {
                    Button {
                        filterQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 210)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            if totalLineCount > 0 {
                let countText = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "\(totalLineCount)"
                    : "\(matchingLineCount)/\(totalLineCount)"
                Text(countText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .accessibilityValue(countText)
                    .accessibilityIdentifier(lineCountIdentifier)
            }

            Spacer()

            Button {
                onCopyOutput()
            } label: {
                Label(NSLocalizedString("Services_Copy_Output", comment: ""), systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .disabled(!copyEnabled)
            .accessibilityIdentifier(copyButtonIdentifier)
        }
    }
}

@MainActor
private struct BPFilteredLogOverlayView: View {
    let filteredText: String
    let accessibilityID: String

    var body: some View {
        ScrollView {
            Text(filteredText.isEmpty ? NSLocalizedString("Empty_Search_Title", comment: "") : filteredText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(filteredText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(10)
                .accessibilityValue(filteredText)
                .accessibilityIdentifier(accessibilityID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

@MainActor
private final class BPConsoleToolPresentation: ObservableObject {
    @Published var state: BPConsoleToolState
    let textView: NSTextView
    var onRun: (() -> Void)?
    var onClear: (() -> Void)?
    var onCopyOutput: (() -> Void)?

    init(textView: NSTextView, state: BPConsoleToolState) {
        self.textView = textView
        self.state = state
    }
}

@MainActor
@objc(BPConsoleToolHost)
public final class BPConsoleToolHost: NSObject {
    public var content: some View { BPConsoleToolView(presentation: presentation) }
    private let presentation: BPConsoleToolPresentation
    @objc public let viewController: NSViewController

    @objc public var isRunning: Bool {
        get { presentation.state.isRunning }
        set {
            presentation.state.isRunning = newValue
            presentation.state.logText = presentation.textView.string
        }
    }

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var warningCount: Int {
        presentation.state.warningCount
    }

    @objc public var errorCount: Int {
        presentation.state.errorCount
    }

    @objc public var diagnosticSeverityRawValue: Int {
        presentation.state.diagnosticSeverity.rawValue
    }

    @objc public var diagnosticSummaryText: String {
        presentation.state.diagnosticSummaryText
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onRun: (() -> Void)? {
        get { presentation.onRun }
        set { presentation.onRun = newValue }
    }

    @objc public var onClear: (() -> Void)? {
        get { presentation.onClear }
        set { presentation.onClear = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithTextView:title:subtitle:runButtonTitle:clearButtonTitle:)
    public init(textView: NSTextView,
                title: String,
                subtitle: String?,
                runButtonTitle: String,
                clearButtonTitle: String) {
        let state = BPConsoleToolState(
            title: title,
            subtitle: subtitle,
            runButtonTitle: runButtonTitle,
            clearButtonTitle: clearButtonTitle,
            isRunning: false,
            logText: textView.string
        )
        let presentation = BPConsoleToolPresentation(textView: textView, state: state)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPConsoleToolView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.textView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.textView.string.isEmpty {
            presentation.state.logText = presentation.textView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPConsoleToolView: View {
    @ObservedObject var presentation: BPConsoleToolPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private var diagnosticColor: Color {
        switch presentation.state.diagnosticSeverity {
        case .idle:
            return .secondary
        case .running:
            return .accentColor
        case .healthy:
            return .green
        case .warnings:
            return .orange
        case .errors:
            return .red
        }
    }

    private var diagnosticSymbol: String {
        switch presentation.state.diagnosticSeverity {
        case .idle:
            return "terminal"
        case .running:
            return "clock.arrow.circlepath"
        case .healthy:
            return "checkmark.seal.fill"
        case .warnings:
            return "exclamationmark.triangle.fill"
        case .errors:
            return "xmark.octagon.fill"
        }
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.textView.string.isEmpty {
            presentation.state.logText = presentation.textView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(presentation.state.title)
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityValue(presentation.state.title)

                        if presentation.state.diagnosticSeverity != .idle {
                            HStack(spacing: 4) {
                                Image(systemName: diagnosticSymbol)
                                    .font(.caption2)
                                Text(presentation.state.diagnosticSummaryText)
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                            }
                            .foregroundStyle(diagnosticColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(diagnosticColor.opacity(0.14))
                            )
                            .accessibilityValue(presentation.state.diagnosticSummaryText)
                            .accessibilityIdentifier("console.diagnostic.badge")
                        }
                    }
                    if let subtitle = presentation.state.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityValue(subtitle)
                    }
                }

                Spacer()

                if presentation.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                }

                Button(presentation.state.clearButtonTitle) {
                    presentation.onClear?()
                }
                .controlSize(.small)
                .keyboardShortcut("k", modifiers: .command)

                Button(presentation.state.runButtonTitle) {
                    presentation.onRun?()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(presentation.state.isRunning)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            BPLogFilterBarView(
                filterQuery: filterBinding,
                matchingLineCount: presentation.state.matchingLineCount,
                totalLineCount: presentation.state.totalLineCount,
                filterFieldIdentifier: "console.filterField",
                lineCountIdentifier: "console.lineCount",
                copyButtonIdentifier: "console.copyOutput",
                copyEnabled: !presentation.state.logText.isEmpty || !presentation.textView.string.isEmpty,
                onCopyOutput: copyCurrentOutput
            )
            .padding(.horizontal, 14)

            ZStack {
                BPLogOutputView(text: presentation.state.logText, accessibilityID: "console.output")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !presentation.state.trimmedFilterQuery.isEmpty {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredOutputText,
                        accessibilityID: "console.filteredOutput"
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftUI Services Tool Host

@MainActor
private final class BPServicesPresentation: ObservableObject {
    @Published var rows: [BPService] = []
    @Published var selectedName: String?
    @Published var detailsText = ""
    var onSelectionChanged: ((String?) -> Void)?
    @Published var state = BPServicesState()
    @Published var startEnabled = false
    @Published var stopEnabled = false
    @Published var restartEnabled = false
    @Published var revealEnabled = false
    @Published var logsEnabled = false
    @Published var copyEnabled = false

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onRestart: (() -> Void)?
    var onRevealFile: (() -> Void)?
    var onOpenLogs: (() -> Void)?
    var onCopyOutput: (() -> Void)?
    var onFilterChanged: (() -> Void)?

    init(tableScrollView: NSView, detailsScrollView: NSView) {

    }
}

@MainActor
@objc(BPServicesHost)
public final class BPServicesHost: NSObject {
    public func updateRows(_ rows: [BPService], selectedName: String?) {
        presentation.rows = rows
        presentation.selectedName = selectedName
    }
    public var onSelectionChanged: ((String?) -> Void)? {
        get { presentation.onSelectionChanged }
        set { presentation.onSelectionChanged = newValue }
    }
    public var detailsText: String {
        get { presentation.detailsText }
        set { presentation.detailsText = newValue }
    }

    public var content: some View { BPServicesView(presentation: presentation) }
    private let presentation: BPServicesPresentation
    @objc public let viewController: NSViewController

    @objc public var statusFilterRawValue: Int {
        get { presentation.state.statusFilter.rawValue }
        set {
            let filter = BPServiceStatusFilter(rawValue: newValue) ?? .all
            presentation.state.statusFilter = filter
            presentation.onFilterChanged?()
        }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set {
            presentation.state.filterQuery = newValue
            presentation.onFilterChanged?()
        }
    }

    @objc public var runningCount: Int {
        presentation.state.runningCount
    }

    @objc public var stoppedCount: Int {
        presentation.state.stoppedCount
    }

    @objc public var errorCount: Int {
        presentation.state.errorCount
    }

    @objc public var totalCount: Int {
        presentation.state.totalCount
    }

    @objc public var serviceFilePath: String {
        get { presentation.state.serviceFilePath }
        set { presentation.state.serviceFilePath = newValue }
    }

    @objc public var logFilePath: String {
        get { presentation.state.logFilePath }
        set { presentation.state.logFilePath = newValue }
    }

    @objc public var onStart: (() -> Void)? {
        get { presentation.onStart }
        set { presentation.onStart = newValue }
    }

    @objc public var onStop: (() -> Void)? {
        get { presentation.onStop }
        set { presentation.onStop = newValue }
    }

    @objc public var onRestart: (() -> Void)? {
        get { presentation.onRestart }
        set { presentation.onRestart = newValue }
    }

    @objc public var onRevealFile: (() -> Void)? {
        get { presentation.onRevealFile }
        set { presentation.onRevealFile = newValue }
    }

    @objc public var onOpenLogs: (() -> Void)? {
        get { presentation.onOpenLogs }
        set { presentation.onOpenLogs = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc public var onFilterChanged: (() -> Void)? {
        get { presentation.onFilterChanged }
        set { presentation.onFilterChanged = newValue }
    }

    @objc(initWithTableScrollView:detailsScrollView:)
    public init(tableScrollView: NSView, detailsScrollView: NSView) {
        let presentation = BPServicesPresentation(
            tableScrollView: tableScrollView,
            detailsScrollView: detailsScrollView
        )
        self.presentation = presentation
        let host = NSHostingController(rootView: BPServicesView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithStartEnabled:stopEnabled:restartEnabled:revealEnabled:logsEnabled:copyEnabled:)
    public func update(startEnabled: Bool,
                       stopEnabled: Bool,
                       restartEnabled: Bool,
                       revealEnabled: Bool,
                       logsEnabled: Bool,
                       copyEnabled: Bool) {
        presentation.startEnabled = startEnabled
        presentation.stopEnabled = stopEnabled
        presentation.restartEnabled = restartEnabled
        presentation.revealEnabled = revealEnabled
        presentation.logsEnabled = logsEnabled
        presentation.copyEnabled = copyEnabled
    }

    @objc(syncCountsWithRunning:stopped:error:)
    public func syncCounts(running: Int, stopped: Int, error: Int) {
        presentation.state.runningCount = running
        presentation.state.stoppedCount = stopped
        presentation.state.errorCount = error
    }

    @objc(syncPathsWithServiceFile:logFile:)
    public func syncPaths(serviceFile: String?, logFile: String?) {
        presentation.state.serviceFilePath = serviceFile ?? ""
        presentation.state.logFilePath = logFile ?? ""
    }

    @objc
    @discardableResult
    public func copyServiceFilePathToPasteboard() -> String {
        let path = presentation.state.serviceFilePath
        guard !path.isEmpty else { return "" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        return path
    }

    @objc
    @discardableResult
    public func copyLogPathToPasteboard() -> String {
        let path = presentation.state.logFilePath
        guard !path.isEmpty else { return "" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        return path
    }
}

@MainActor
private struct BPServicesView: View {
    @ObservedObject var presentation: BPServicesPresentation

    private var queryBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { newValue in
                presentation.state.filterQuery = newValue
                presentation.onFilterChanged?()
            }
        )
    }

    private func selectFilter(_ filter: BPServiceStatusFilter) {
        presentation.state.statusFilter = filter
        presentation.onFilterChanged?()
    }

    @ViewBuilder
    private func filterPill(filter: BPServiceStatusFilter,
                            title: String,
                            count: Int,
                            color: Color,
                            accessibilityID: String) -> some View {
        let isSelected = (presentation.state.statusFilter == filter)
        Button {
            selectFilter(filter)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                Text("\(count)")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(isSelected ? 0.24 : 0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(NSLocalizedString("Services_Title", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(NSLocalizedString("Services_Title", comment: ""))

                Spacer()

                filterPill(
                    filter: .all,
                    title: NSLocalizedString("Services_Filter_All", comment: ""),
                    count: presentation.state.totalCount,
                    color: .accentColor,
                    accessibilityID: "services.filter.all"
                )
                filterPill(
                    filter: .running,
                    title: NSLocalizedString("Services_Status_Started", comment: ""),
                    count: presentation.state.runningCount,
                    color: .green,
                    accessibilityID: "services.filter.running"
                )
                filterPill(
                    filter: .stopped,
                    title: NSLocalizedString("Services_Status_Stopped", comment: ""),
                    count: presentation.state.stoppedCount,
                    color: .secondary,
                    accessibilityID: "services.filter.stopped"
                )
                if presentation.state.errorCount > 0 || presentation.state.statusFilter == .error {
                    filterPill(
                        filter: .error,
                        title: NSLocalizedString("Services_Status_Error", comment: ""),
                        count: presentation.state.errorCount,
                        color: .red,
                        accessibilityID: "services.filter.error"
                    )
                }

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Services_Search", comment: ""), text: queryBinding)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .accessibilityIdentifier("services.searchField")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 150)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            Table(presentation.rows.map(BPServiceRow.init), selection: Binding(
                get: { presentation.selectedName },
                set: { presentation.selectedName = $0; presentation.onSelectionChanged?($0) }
            )) {
                TableColumn(NSLocalizedString("Services_Column_Name", comment: "")) { service in
                    Text(service.name ?? "")
                }
                TableColumn(NSLocalizedString("Services_Column_Status", comment: "")) { service in
                    Label(BPService.localizedName(for: service.status), systemImage: service.status == .started ? "play.circle" : "stop.circle")
                }
                TableColumn(NSLocalizedString("Services_Column_User", comment: "")) { service in
                    Text(service.user ?? "").foregroundStyle(.secondary)
                }
            }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .overlay {
                    if presentation.rows.isEmpty {
                        let state = BPEmptyState.state(forSidebarRow: 14, searching: !presentation.state.filterQuery.isEmpty || presentation.state.statusFilter != .all)
                        ContentUnavailableView {
                            Label(NSLocalizedString(state.titleKey, comment: ""), systemImage: state.symbolName)
                                .accessibilityIdentifier("emptyState.title")
                        } description: {
                            Text(NSLocalizedString(state.messageKey, comment: ""))
                                .accessibilityIdentifier("emptyState.message")
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 90, maxHeight: .infinity)

            HStack(spacing: 8) {
                Button(NSLocalizedString("Services_Start", comment: "")) {
                    presentation.onStart?()
                }
                .disabled(!presentation.startEnabled)

                Button(NSLocalizedString("Services_Stop", comment: "")) {
                    presentation.onStop?()
                }
                .disabled(!presentation.stopEnabled)

                Button(NSLocalizedString("Services_Restart", comment: "")) {
                    presentation.onRestart?()
                }
                .disabled(!presentation.restartEnabled)

                Spacer()
            }

            ScrollView {
                Text(presentation.detailsText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .accessibilityIdentifier("services.details")
                    .accessibilityValue(presentation.detailsText)
            }
            .frame(height: 115)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                Button(NSLocalizedString("Services_Reveal_File", comment: "")) {
                    presentation.onRevealFile?()
                }
                .disabled(!presentation.revealEnabled)
                .accessibilityIdentifier("services.revealFile")

                Button(NSLocalizedString("Services_Open_Logs", comment: "")) {
                    presentation.onOpenLogs?()
                }
                .disabled(!presentation.logsEnabled)
                .accessibilityIdentifier("services.openLogs")

                Button(NSLocalizedString("Services_Copy_Output", comment: "")) {
                    presentation.onCopyOutput?()
                }
                .disabled(!presentation.copyEnabled)
                .accessibilityIdentifier("services.copyOutput")

                if !presentation.state.serviceFilePath.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(presentation.state.serviceFilePath, forType: .string)
                    } label: {
                        Label(URL(fileURLWithPath: presentation.state.serviceFilePath).lastPathComponent, systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .help(presentation.state.serviceFilePath)
                    .accessibilityIdentifier("services.copyServicePath")
                }

                if !presentation.state.logFilePath.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(presentation.state.logFilePath, forType: .string)
                    } label: {
                        Label(URL(fileURLWithPath: presentation.state.logFilePath).lastPathComponent, systemImage: "doc.text")
                    }
                    .controlSize(.small)
                    .help(presentation.state.logFilePath)
                    .accessibilityIdentifier("services.copyLogPath")
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Autoremove Sheet Host

@MainActor
private final class BPAutoremovePresentation: ObservableObject {
    @Published var state = BPAutoremoveSheetState(
        statusText: NSLocalizedString("Checking unused dependencies…", comment: ""),
        warningText: NSLocalizedString("Only the reviewed formulae will be submitted for removal. Homebrew will recheck its dependency rules. Do not run other Homebrew operations until this finishes: external changes cannot be checked atomically.", comment: ""),
        removeButtonTitle: NSLocalizedString("Remove Reviewed Dependencies", comment: ""),
        cancelButtonTitle: NSLocalizedString("Cancel", comment: ""),
        removeEnabled: false,
        cancelEnabled: true,
        isBusy: true
    )
    let outputTextView: NSTextView
    var onRemove: (() -> Void)?
    var onCancelOrClose: (() -> Void)?
    var onCopyOutput: (() -> Void)?

    init(outputTextView: NSTextView) {
        self.outputTextView = outputTextView
    }
}

@MainActor
@objc(BPAutoremoveHost)
public final class BPAutoremoveHost: NSObject {
    private let presentation: BPAutoremovePresentation
    @objc public let viewController: NSViewController

    @objc public var candidateCount: Int {
        get { presentation.state.candidateCount }
        set { presentation.state.candidateCount = newValue }
    }

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onRemove: (() -> Void)? {
        get { presentation.onRemove }
        set { presentation.onRemove = newValue }
    }

    @objc public var onCancelOrClose: (() -> Void)? {
        get { presentation.onCancelOrClose }
        set { presentation.onCancelOrClose = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithOutputTextView:)
    public init(outputTextView: NSTextView) {
        let presentation = BPAutoremovePresentation(outputTextView: outputTextView)
        presentation.state.logText = outputTextView.string
        self.presentation = presentation
        let host = NSHostingController(rootView: BPAutoremoveView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithStatusText:removeEnabled:cancelTitle:cancelEnabled:busy:)
    public func update(statusText: String,
                       removeEnabled: Bool,
                       cancelTitle: String,
                       cancelEnabled: Bool,
                       busy: Bool) {
        presentation.state.statusText = statusText
        presentation.state.removeEnabled = removeEnabled
        presentation.state.cancelButtonTitle = cancelTitle
        presentation.state.cancelEnabled = cancelEnabled
        presentation.state.isBusy = busy
        presentation.state.logText = presentation.outputTextView.string
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.outputTextView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.outputTextView.string.isEmpty {
            presentation.state.logText = presentation.outputTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPAutoremoveView: View {
    @ObservedObject var presentation: BPAutoremovePresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.outputTextView.string.isEmpty {
            presentation.state.logText = presentation.outputTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(presentation.state.statusText)
                    .font(.system(size: 14, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(presentation.state.statusText)
                    .accessibilityIdentifier("autoremove.status")

                if presentation.state.candidateCount > 0 {
                    Text("\(presentation.state.candidateCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                        .accessibilityValue("\(presentation.state.candidateCount)")
                        .accessibilityIdentifier("autoremove.candidateBadge")
                }

                Spacer()
            }

            Text(presentation.state.warningText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(presentation.state.warningText)

            BPLogFilterBarView(
                filterQuery: filterBinding,
                matchingLineCount: presentation.state.matchingLineCount,
                totalLineCount: presentation.state.totalLineCount,
                filterFieldIdentifier: "autoremove.filterField",
                lineCountIdentifier: "autoremove.lineCount",
                copyButtonIdentifier: "autoremove.copyOutput",
                copyEnabled: !presentation.state.logText.isEmpty || !presentation.outputTextView.string.isEmpty,
                onCopyOutput: copyCurrentOutput
            )

            ZStack {
                BPLogOutputView(text: presentation.state.logText, accessibilityID: "autoremove.output")
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)

                if !presentation.state.trimmedFilterQuery.isEmpty {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredOutputText,
                        accessibilityID: "autoremove.filteredOutput"
                    )
                }
            }

            HStack(spacing: 12) {
                Button(presentation.state.cancelButtonTitle) {
                    presentation.onCancelOrClose?()
                }
                .disabled(!presentation.state.cancelEnabled)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("autoremove.cancel")

                Button(presentation.state.removeButtonTitle) {
                    presentation.onRemove?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.state.removeEnabled)
                .accessibilityIdentifier("autoremove.remove")

                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Bundle (Brewfile Import / Export) Sheet Host

private func BPBundleWindowLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "BPBundleWindow")
}

@MainActor
private final class BPBundleOperationPresentation: ObservableObject {
    @Published var state = BPBundleSheetState(
        mode: .importing,
        headerTitle: BPBundleWindowLocalizedTitle("UHp-GH-2qP.title", fallback: "Homebrew Bundle"),
        subtitleText: BPBundleWindowLocalizedTitle("UQX-gO-pze.title", fallback: "Importing File"),
        statusText: BPBundleWindowLocalizedTitle("NRz-0t-Pn6.title", fallback: "Please wait while the file is imported."),
        detailText: "",
        actionButtonTitle: NSLocalizedString("Cancel", comment: ""),
        actionEnabled: true,
        isRunning: true,
        hasFinished: false,
        succeeded: false
    )
    let importTextView: NSTextView
    var onAction: (() -> Void)?
    var onCopyOutput: (() -> Void)?

    init(importTextView: NSTextView) {
        self.importTextView = importTextView
    }
}

@MainActor
@objc(BPBundleOperationHost)
public final class BPBundleOperationHost: NSObject {
    private let presentation: BPBundleOperationPresentation
    @objc public let viewController: NSViewController

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onAction: (() -> Void)? {
        get { presentation.onAction }
        set { presentation.onAction = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithImportTextView:)
    public init(importTextView: NSTextView) {
        let presentation = BPBundleOperationPresentation(importTextView: importTextView)
        presentation.state.logText = importTextView.string
        self.presentation = presentation
        let host = NSHostingController(rootView: BPBundleOperationView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(configureImportWithStatusText:actionTitle:actionEnabled:running:)
    public func configureImport(statusText: String?,
                                actionTitle: String,
                                actionEnabled: Bool,
                                running: Bool) {
        let resolvedStatus = (statusText?.isEmpty == false)
            ? statusText!
            : BPBundleWindowLocalizedTitle("NRz-0t-Pn6.title", fallback: "Please wait while the file is imported.")
        presentation.state = BPBundleSheetState(
            mode: .importing,
            headerTitle: BPBundleWindowLocalizedTitle("UHp-GH-2qP.title", fallback: "Homebrew Bundle"),
            subtitleText: BPBundleWindowLocalizedTitle("UQX-gO-pze.title", fallback: "Importing File"),
            statusText: resolvedStatus,
            detailText: "",
            actionButtonTitle: actionTitle,
            actionEnabled: actionEnabled,
            isRunning: running,
            hasFinished: !running,
            succeeded: !running,
            logText: presentation.importTextView.string,
            filterQuery: presentation.state.filterQuery
        )
    }

    @objc(configureExportWithStatusText:detailText:actionTitle:actionEnabled:running:finished:succeeded:)
    public func configureExport(statusText: String?,
                                detailText: String?,
                                actionTitle: String?,
                                actionEnabled: Bool,
                                running: Bool,
                                finished: Bool,
                                succeeded: Bool) {
        let resolvedStatus = (statusText?.isEmpty == false)
            ? statusText!
            : BPBundleWindowLocalizedTitle("lO8-qv-x07.title", fallback: "Export Successful")
        let resolvedDetail = (detailText?.isEmpty == false)
            ? detailText!
            : BPBundleWindowLocalizedTitle("Vid-Aa-KXl.title", fallback: "Please wait while the file is generated.")
        let resolvedAction = (actionTitle?.isEmpty == false)
            ? actionTitle!
            : BPBundleWindowLocalizedTitle("xSx-yq-DSQ.title", fallback: "Close")
        presentation.state = BPBundleSheetState(
            mode: .exporting,
            headerTitle: BPBundleWindowLocalizedTitle("UHp-GH-2qP.title", fallback: "Homebrew Bundle"),
            subtitleText: BPBundleWindowLocalizedTitle("Kyw-ca-xgs.title", fallback: "Exporting File"),
            statusText: resolvedStatus,
            detailText: resolvedDetail,
            actionButtonTitle: resolvedAction,
            actionEnabled: actionEnabled,
            isRunning: running,
            hasFinished: finished,
            succeeded: succeeded,
            logText: presentation.state.logText,
            filterQuery: presentation.state.filterQuery
        )
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.importTextView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.importTextView.string.isEmpty {
            presentation.state.logText = presentation.importTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPBundleOperationView: View {
    @ObservedObject var presentation: BPBundleOperationPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.importTextView.string.isEmpty {
            presentation.state.logText = presentation.importTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.state.headerTitle)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(presentation.state.headerTitle)

            if presentation.state.mode == .importing {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.state.subtitleText)
                        .font(.body)
                        .accessibilityValue(presentation.state.subtitleText)

                    Text(presentation.state.statusText)
                        .font(.smallCaps(.caption)())
                        .foregroundStyle(.secondary)
                        .accessibilityValue(presentation.state.statusText)
                        .accessibilityIdentifier("brewfile.import.status")

                    BPLogFilterBarView(
                        filterQuery: filterBinding,
                        matchingLineCount: presentation.state.matchingLineCount,
                        totalLineCount: presentation.state.totalLineCount,
                        filterFieldIdentifier: "brewfile.import.filterField",
                        lineCountIdentifier: "brewfile.import.lineCount",
                        copyButtonIdentifier: "brewfile.import.copyOutput",
                        copyEnabled: !presentation.state.logText.isEmpty || !presentation.importTextView.string.isEmpty,
                        onCopyOutput: copyCurrentOutput
                    )

                    ZStack {
                        BPLogOutputView(text: presentation.state.logText, accessibilityID: "brewfile.import.output")
                            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)

                        if !presentation.state.trimmedFilterQuery.isEmpty {
                            BPFilteredLogOverlayView(
                                filteredText: presentation.state.filteredOutputText,
                                accessibilityID: "brewfile.import.filteredOutput"
                            )
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.state.subtitleText)
                        .font(.body)
                        .accessibilityValue(presentation.state.subtitleText)

                    if !presentation.state.hasFinished || !presentation.state.succeeded {
                        Text(presentation.state.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityValue(presentation.state.detailText)
                            .accessibilityIdentifier("brewfile.export.detail")
                    }

                    Spacer(minLength: 8)

                    if presentation.state.hasFinished {
                        VStack(spacing: 8) {
                            Image(systemName: presentation.state.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(presentation.state.succeeded ? .green : .red)
                            Text(presentation.state.statusText)
                                .font(.headline)
                                .accessibilityValue(presentation.state.statusText)
                                .accessibilityIdentifier("brewfile.export.status")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            }

            HStack {
                if presentation.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                        .accessibilityIdentifier(presentation.state.mode == .exporting ? "brewfile.export.progress" : "brewfile.import.progress")
                }

                Spacer()

                Button(presentation.state.actionButtonTitle) {
                    presentation.onAction?()
                }
                .disabled(!presentation.state.actionEnabled)
                .accessibilityIdentifier(presentation.state.mode == .importing ? "brewfile.import.action" : "brewfile.export.close")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Formula Options Sheet Host

private func BPFormulaOptionsLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "BPFormulaOptionsWindow")
}

@MainActor
private final class BPFormulaOptionsPresentation: ObservableObject {
    @Published var state = BPFormulaOptionsSheetState()
    var onOptionToggled: ((String, Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onInstall: (() -> Void)?
}

@MainActor
@objc(BPFormulaOptionsHost)
public final class BPFormulaOptionsHost: NSObject {
    private let presentation = BPFormulaOptionsPresentation()
    @objc public let viewController: NSViewController

    @objc public var selectedOptionNames: [String] {
        presentation.state.selectedOptionNames
    }

    @objc public var appliedOptionCount: Int {
        presentation.state.appliedOptionCount
    }

    @objc public var filteredOptionCount: Int {
        presentation.state.filteredOptions.count
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var onOptionToggled: ((String, Bool) -> Void)? {
        get { presentation.onOptionToggled }
        set { presentation.onOptionToggled = newValue }
    }

    @objc public var onCancel: (() -> Void)? {
        get { presentation.onCancel }
        set { presentation.onCancel = newValue }
    }

    @objc public var onInstall: (() -> Void)? {
        get { presentation.onInstall }
        set { presentation.onInstall = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPFormulaOptionsView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(configureWithFormulaName:optionNames:optionExplanations:)
    public func configure(formulaName: String,
                          optionNames: [String],
                          optionExplanations: [String]) {
        var rows: [BPFormulaOptionRow] = []
        rows.reserveCapacity(optionNames.count)
        for index in 0..<optionNames.count {
            let explanation = index < optionExplanations.count ? optionExplanations[index] : ""
            rows.append(BPFormulaOptionRow(name: optionNames[index], explanation: explanation, isApplied: false))
        }
        let helpText = rows.isEmpty
            ? NSLocalizedString("Formula_Options_NoOptions", comment: "")
            : NSLocalizedString("Formula_Options_ClickForDetails", comment: "")
        presentation.state = BPFormulaOptionsSheetState(
            formulaName: formulaName,
            headerTitle: BPFormulaOptionsLocalizedTitle("idS-tT-jie.title", fallback: "Picking Options for Formula:"),
            helpText: helpText,
            optionsColumnTitle: BPFormulaOptionsLocalizedTitle("XqV-53-e7D.headerCell.title", fallback: "Options"),
            descriptionPlaceholder: BPFormulaOptionsLocalizedTitle("G5n-5T-DoK.placeholderString", fallback: "Description for selected option."),
            cancelTitle: BPFormulaOptionsLocalizedTitle("dCD-PS-P4J.title", fallback: "Cancel"),
            installTitle: BPFormulaOptionsLocalizedTitle("hgj-Zo-s73.title", fallback: "Install"),
            options: rows,
            selectedOptionID: rows.first?.id
        )
    }

    @objc(setApplied:forOptionNamed:)
    public func setApplied(_ applied: Bool, forOptionNamed name: String) {
        presentation.state.setApplied(applied, forOptionID: name)
        presentation.onOptionToggled?(name, applied)
    }

    @objc
    public func clearAllAppliedOptions() {
        let previouslyApplied = presentation.state.selectedOptionNames
        presentation.state.clearAllApplied()
        for name in previouslyApplied {
            presentation.onOptionToggled?(name, false)
        }
    }
}

@MainActor
private struct BPFormulaOptionsView: View {
    @ObservedObject var presentation: BPFormulaOptionsPresentation

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { presentation.state.selectedOptionID },
            set: { presentation.state.selectedOptionID = $0 }
        )
    }

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private func toggleBinding(for row: BPFormulaOptionRow) -> Binding<Bool> {
        Binding(
            get: { row.isApplied },
            set: { newValue in
                presentation.state.setApplied(newValue, forOptionID: row.id)
                presentation.onOptionToggled?(row.name, newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(presentation.state.headerTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .accessibilityValue(presentation.state.headerTitle)
                Text(presentation.state.formulaName)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityValue(presentation.state.formulaName)
                    .accessibilityIdentifier("formula.options.formulaName")

                if presentation.state.appliedOptionCount > 0 {
                    Text("\(presentation.state.appliedOptionCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                        .accessibilityValue("\(presentation.state.appliedOptionCount)")
                        .accessibilityIdentifier("formula.options.appliedBadge")
                }

                Spacer()

                if !presentation.state.options.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: filterBinding)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .accessibilityIdentifier("formula.options.searchField")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(width: 140)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }

            List(presentation.state.filteredOptions, selection: selectionBinding) { row in
                HStack(spacing: 8) {
                    Toggle("", isOn: toggleBinding(for: row))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("formula.options.toggle.\(row.name)")
                    Text(row.name)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            presentation.state.selectedOptionID = row.id
                        }
                        .help(row.explanation)
                        .accessibilityLabel(row.explanation.isEmpty ? row.name : row.explanation)
                        .accessibilityValue(row.name)
                }
                .tag(Optional(row.id))
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 130, maxHeight: .infinity)
            .accessibilityLabel(NSLocalizedString("Formula_Options_VoiceOver", comment: ""))

            ScrollView {
                Text(presentation.state.selectedOptionDescription)
                    .font(.callout)
                    .foregroundStyle(presentation.state.selectedOptionID == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel(NSLocalizedString("Formula_Options_VoiceOver_Description", comment: ""))
                    .accessibilityValue(presentation.state.selectedOptionDescription)
            }
            .padding(8)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            HStack {
                Button(presentation.state.cancelTitle) {
                    presentation.onCancel?()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("formula.options.cancel")

                Spacer()

                Text(presentation.state.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityValue(presentation.state.helpText)

                Spacer()

                Button(presentation.state.installTitle) {
                    presentation.onInstall?()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("formula.options.install")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Installation / Operation Progress Sheet Host

private func BPInstallationLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "BPInstallationWindow")
}

@MainActor
private final class BPInstallationPresentation: ObservableObject {
    @Published var state = BPInstallationSheetState(
        windowTitle: "",
        formulaNamesText: "",
        okTitle: BPInstallationLocalizedTitle("atZ-M7-fU1.title", fallback: "OK"),
        cancelTitle: NSLocalizedString("Cancel", comment: ""),
        isRunning: true,
        okEnabled: false,
        cancelEnabled: true
    )
    let recordTextView: NSTextView
    var onCancel: (() -> Void)?
    var onOK: (() -> Void)?
    var onCopyOutput: (() -> Void)?

    init(recordTextView: NSTextView) {
        self.recordTextView = recordTextView
    }
}

@MainActor
@objc(BPInstallationHost)
public final class BPInstallationHost: NSObject {
    private let presentation: BPInstallationPresentation
    @objc public let viewController: NSViewController

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onCancel: (() -> Void)? {
        get { presentation.onCancel }
        set { presentation.onCancel = newValue }
    }

    @objc public var onOK: (() -> Void)? {
        get { presentation.onOK }
        set { presentation.onOK = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithRecordTextView:)
    public init(recordTextView: NSTextView) {
        let presentation = BPInstallationPresentation(recordTextView: recordTextView)
        presentation.state.logText = recordTextView.string
        self.presentation = presentation
        let host = NSHostingController(rootView: BPInstallationView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithWindowTitle:formulaNames:running:okEnabled:cancelEnabled:)
    public func update(windowTitle: String,
                       formulaNames: String,
                       running: Bool,
                       okEnabled: Bool,
                       cancelEnabled: Bool) {
        presentation.state = BPInstallationSheetState(
            windowTitle: windowTitle,
            formulaNamesText: formulaNames,
            okTitle: BPInstallationLocalizedTitle("atZ-M7-fU1.title", fallback: "OK"),
            cancelTitle: NSLocalizedString("Cancel", comment: ""),
            isRunning: running,
            okEnabled: okEnabled,
            cancelEnabled: cancelEnabled,
            logText: presentation.recordTextView.string,
            filterQuery: presentation.state.filterQuery
        )
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.recordTextView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.recordTextView.string.isEmpty {
            presentation.state.logText = presentation.recordTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPInstallationView: View {
    @ObservedObject var presentation: BPInstallationPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.recordTextView.string.isEmpty {
            presentation.state.logText = presentation.recordTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.state.windowTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .accessibilityValue(presentation.state.windowTitle)
                    .accessibilityIdentifier("installation.title")

                if !presentation.state.formulaNamesText.isEmpty {
                    Text(presentation.state.formulaNamesText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .accessibilityValue(presentation.state.formulaNamesText)
                        .accessibilityIdentifier("installation.target")
                }

                Spacer()
            }

            BPLogFilterBarView(
                filterQuery: filterBinding,
                matchingLineCount: presentation.state.matchingLineCount,
                totalLineCount: presentation.state.totalLineCount,
                filterFieldIdentifier: "installation.filterField",
                lineCountIdentifier: "installation.lineCount",
                copyButtonIdentifier: "installation.copyOutput",
                copyEnabled: !presentation.state.logText.isEmpty || !presentation.recordTextView.string.isEmpty,
                onCopyOutput: copyCurrentOutput
            )

            ZStack {
                BPLogOutputView(text: presentation.state.logText, accessibilityID: "installation.output")
                    .frame(maxWidth: .infinity, minHeight: 154, maxHeight: .infinity)

                if !presentation.state.trimmedFilterQuery.isEmpty {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredOutputText,
                        accessibilityID: "installation.filteredOutput"
                    )
                }
            }

            HStack(spacing: 10) {
                if presentation.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                }

                Spacer()

                Button(presentation.state.cancelTitle) {
                    presentation.onCancel?()
                }
                .disabled(!presentation.state.cancelEnabled)
                .accessibilityIdentifier("installation.cancel")

                Button(presentation.state.okTitle) {
                    presentation.onOK?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.state.okEnabled)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("installation.ok")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Tahoe About Window Host

internal func BPLocalizedWithFallback(_ key: String, fallback: String) -> String {
    let resolved = Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    return (resolved.isEmpty || resolved == key) ? fallback : resolved
}

@MainActor
private final class BPAboutWindowPresentation: ObservableObject {
    @Published var state = BPAboutWindowState()
    let creditsTextView: NSTextView
    var onVisitWebsite: (() -> Void)?
    var onSelectTab: ((Int) -> Void)?

    init(creditsTextView: NSTextView) {
        self.creditsTextView = creditsTextView
    }
}

@MainActor
@objc(BPAboutWindowHost)
public final class BPAboutWindowHost: NSObject {
    private let presentation: BPAboutWindowPresentation
    @objc public let viewController: NSViewController

    @objc public var selectedTabIndex: Int {
        presentation.state.selectedTab.rawValue
    }

    @objc public var versionClipboardSummary: String {
        presentation.state.versionClipboardSummary
    }

    @objc public var onVisitWebsite: (() -> Void)? {
        get { presentation.onVisitWebsite }
        set { presentation.onVisitWebsite = newValue }
    }

    @objc public var onSelectTab: ((Int) -> Void)? {
        get { presentation.onSelectTab }
        set { presentation.onSelectTab = newValue }
    }

    @objc(initWithCreditsTextView:)
    public init(creditsTextView: NSTextView) {
        let presentation = BPAboutWindowPresentation(creditsTextView: creditsTextView)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPAboutWindowView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(configureWithAppName:appVersion:appCopyright:hasAcknowledgements:)
    public func configure(appName: String,
                          appVersion: String,
                          appCopyright: String,
                          hasAcknowledgements: Bool) {
        presentation.state = BPAboutWindowState(
            appName: appName.isEmpty ? "Cakebrew" : appName,
            appVersion: appVersion,
            appCopyright: appCopyright,
            selectedTab: presentation.state.selectedTab,
            hasAcknowledgements: hasAcknowledgements
        )
    }

    @objc(selectTabAtIndex:)
    public func selectTab(at index: Int) {
        let tab = BPAboutWindowTab(rawValue: index) ?? .credits
        presentation.state.selectedTab = tab
        presentation.onSelectTab?(tab.rawValue)
    }

    @objc
    @discardableResult
    public func copyVersionInfoToPasteboard() -> String {
        let summary = presentation.state.versionClipboardSummary
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        return summary
    }
}

@MainActor
private struct BPAboutWindowView: View {
    @ObservedObject var presentation: BPAboutWindowPresentation

    private var selectedTabBinding: Binding<BPAboutWindowTab> {
        Binding(
            get: { presentation.state.selectedTab },
            set: { newTab in
                presentation.state.selectedTab = newTab
                presentation.onSelectTab?(newTab.rawValue)
            }
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(presentation.state.appName)
                            .font(.system(size: 22, weight: .bold))
                            .accessibilityIdentifier("about.appName")

                        if !presentation.state.appVersion.isEmpty {
                            Text(presentation.state.appVersion)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.14))
                                )
                                .accessibilityIdentifier("about.appVersion")
                        }
                    }

                    if !presentation.state.appCopyright.isEmpty {
                        Text(presentation.state.appCopyright)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .accessibilityIdentifier("about.appCopyright")
                    }
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )

            if presentation.state.hasAcknowledgements {
                Picker("", selection: selectedTabBinding) {
                    Text(BPLocalizedWithFallback("About_Credits", fallback: "Credits"))
                        .tag(BPAboutWindowTab.credits)
                    Text(BPLocalizedWithFallback("About_Acknowledgements", fallback: "Acknowledgements"))
                        .tag(BPAboutWindowTab.acknowledgements)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("about.tabPicker")
            }

            BPLogOutputView(text: presentation.creditsTextView.string)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(presentation.state.versionClipboardSummary, forType: .string)
                } label: {
                    Label(BPLocalizedWithFallback("About_Copy_Version", fallback: "Copy Version Info"), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .accessibilityIdentifier("about.copyVersion")

                Spacer()

                Button {
                    presentation.onVisitWebsite?()
                } label: {
                    Label(BPLocalizedWithFallback("About_Visit_Website", fallback: "Visit Website"), systemImage: "safari")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("about.visitWebsite")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Brewfile Review Accessory Host

@MainActor
private final class BPBrewfileReviewPresentation: ObservableObject {
    @Published var state: BPBrewfileReviewState
    let entriesTextView: NSTextView

    init(entriesTextView: NSTextView, state: BPBrewfileReviewState) {
        self.entriesTextView = entriesTextView
        self.state = state
    }
}

@MainActor
@objc(BPBrewfileReviewHost)
public final class BPBrewfileReviewHost: NSObject {
    private let presentation: BPBrewfileReviewPresentation
    @objc public let viewController: NSViewController

    @objc public var totalEntryCount: Int {
        presentation.state.totalEntryCount
    }

    @objc public var installedCount: Int {
        presentation.state.installedCount
    }

    @objc public var missingCount: Int {
        presentation.state.missingCount
    }

    @objc public var notCheckedCount: Int {
        presentation.state.notCheckedCount
    }

    @objc public var canInstall: Bool {
        presentation.state.canInstall
    }

    @objc public var statusFilterRawValue: Int {
        get { presentation.state.statusFilter.rawValue }
        set { presentation.state.statusFilter = BPBrewfileEntryFilter(rawValue: newValue) ?? .all }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingEntryCount: Int {
        presentation.state.matchingEntryCount
    }

    @objc public var entriesTextView: NSTextView {
        presentation.entriesTextView
    }

    @objc(initWithEntriesTextView:fileName:installedCount:missingCount:notCheckedCount:formulaCount:caskCount:tapCount:otherCount:canInstall:summaryText:)
    public init(entriesTextView: NSTextView,
                fileName: String,
                installedCount: Int,
                missingCount: Int,
                notCheckedCount: Int,
                formulaCount: Int,
                caskCount: Int,
                tapCount: Int,
                otherCount: Int,
                canInstall: Bool,
                summaryText: String) {
        let state = BPBrewfileReviewState(
            fileName: fileName,
            installedCount: installedCount,
            missingCount: missingCount,
            notCheckedCount: notCheckedCount,
            formulaCount: formulaCount,
            caskCount: caskCount,
            tapCount: tapCount,
            otherCount: otherCount,
            canInstall: canInstall,
            summaryText: summaryText
        )
        let presentation = BPBrewfileReviewPresentation(entriesTextView: entriesTextView, state: state)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPBrewfileReviewView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc
    @discardableResult
    public func copySummaryToPasteboard() -> String {
        let text = presentation.state.filteredSummaryText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }
}

@MainActor
private struct BPBrewfileReviewView: View {
    @ObservedObject var presentation: BPBrewfileReviewPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(presentation.state.fileName, systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("brewfile.review.fileName")

                Spacer()

                filterPillButton(
                    filter: .all,
                    count: presentation.state.totalEntryCount,
                    label: BPLocalizedWithFallback("Brewfile", fallback: "All"),
                    color: .accentColor,
                    accessibilityID: "brewfile.review.filter.all"
                )
                filterPillButton(
                    filter: .installed,
                    count: presentation.state.installedCount,
                    label: BPLocalizedWithFallback("Installed", fallback: "Installed"),
                    color: .green,
                    accessibilityID: "brewfile.review.filter.installed"
                )
                filterPillButton(
                    filter: .missing,
                    count: presentation.state.missingCount,
                    label: BPLocalizedWithFallback("Missing", fallback: "Missing"),
                    color: .orange,
                    accessibilityID: "brewfile.review.filter.missing"
                )
                if presentation.state.notCheckedCount > 0 {
                    statusPill(
                        count: presentation.state.notCheckedCount,
                        label: BPLocalizedWithFallback("Not checked", fallback: "Not checked"),
                        color: .secondary
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: filterBinding)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .accessibilityIdentifier("brewfile.review.searchField")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: 200)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                Spacer()

                Button {
                    let text = presentation.state.filteredSummaryText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label(NSLocalizedString("Services_Copy_Output", comment: ""), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(presentation.state.summaryText.isEmpty)
                .accessibilityIdentifier("brewfile.review.copySummary")
            }

            ZStack {
                BPLogOutputView(text: presentation.state.summaryText, accessibilityID: "brewfile.review.entries")
                    .frame(maxWidth: .infinity, minHeight: 185, maxHeight: .infinity)

                if presentation.state.isFiltering {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredSummaryText,
                        accessibilityID: "brewfile.review.filteredEntries"
                    )
                }
            }
        }
        .frame(width: 570, height: 296)
    }

    @ViewBuilder
    private func filterPillButton(filter: BPBrewfileEntryFilter,
                                  count: Int,
                                  label: String,
                                  color: Color,
                                  accessibilityID: String) -> some View {
        let isSelected = (presentation.state.statusFilter == filter)
        Button {
            presentation.state.statusFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(isSelected ? 0.24 : 0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder
    private func statusPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - SwiftUI Command Palette Host (⌘K)

@MainActor
private final class BPCommandPalettePresentation: ObservableObject {
    @Published var state = BPCommandPaletteState()
    var onNavigateToSidebarRow: ((Int) -> Void)?
    var onPerformAction: ((String) -> Void)?
    var onSelectPackage: ((String, Bool) -> Void)?
    var onDismiss: (() -> Void)?

    @discardableResult
    func execute(_ item: BPCommandPaletteItem) -> Bool {
        switch item.kind {
        case .navigation:
            guard item.sidebarRow >= 0 else { return false }
            onDismiss?()
            onNavigateToSidebarRow?(item.sidebarRow)
            return true
        case .action:
            guard let actionID = item.actionIdentifier, !actionID.isEmpty else { return false }
            onDismiss?()
            onPerformAction?(actionID)
            return true
        case .package:
            guard let name = item.packageName, !name.isEmpty else { return false }
            onDismiss?()
            onSelectPackage?(name, item.isCask)
            return true
        }
    }
}

@MainActor
@objc(BPCommandPaletteHost)
public final class BPCommandPaletteHost: NSObject {
    private let presentation = BPCommandPalettePresentation()
    @objc public let viewController: NSViewController

    @objc public var query: String {
        get { presentation.state.query }
        set { presentation.state.query = newValue }
    }

    @objc public var filteredCount: Int {
        presentation.state.filteredItems.count
    }

    @objc public var selectedItemID: String? {
        presentation.state.selectedItem?.id
    }

    @objc public var onNavigateToSidebarRow: ((Int) -> Void)? {
        get { presentation.onNavigateToSidebarRow }
        set { presentation.onNavigateToSidebarRow = newValue }
    }

    @objc public var onPerformAction: ((String) -> Void)? {
        get { presentation.onPerformAction }
        set { presentation.onPerformAction = newValue }
    }

    @objc public var onSelectPackage: ((String, Bool) -> Void)? {
        get { presentation.onSelectPackage }
        set { presentation.onSelectPackage = newValue }
    }

    @objc public var onDismiss: (() -> Void)? {
        get { presentation.onDismiss }
        set { presentation.onDismiss = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPCommandPaletteView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc
    public func removeAllItems() {
        presentation.state.items = []
        presentation.state.query = ""
    }

    @objc(addNavigationItemWithID:title:subtitle:symbolName:sidebarRow:)
    public func addNavigationItem(id: String,
                                  title: String,
                                  subtitle: String,
                                  symbolName: String,
                                  sidebarRow: Int) {
        let item = BPCommandPaletteItem(
            id: id,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            shortcutHint: nil,
            kind: .navigation,
            sidebarRow: sidebarRow
        )
        presentation.state.items.append(item)
    }

    @objc(addActionItemWithID:title:subtitle:symbolName:shortcutHint:)
    public func addActionItem(id: String,
                              title: String,
                              subtitle: String,
                              symbolName: String,
                              shortcutHint: String?) {
        let item = BPCommandPaletteItem(
            id: id,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            shortcutHint: shortcutHint,
            kind: .action,
            actionIdentifier: id
        )
        presentation.state.items.append(item)
    }

    @objc(addPackageItemWithName:version:cask:)
    public func addPackageItem(name: String, version: String, cask: Bool) {
        guard !name.isEmpty else { return }
        let kindLabel = cask
            ? BPLocalizedWithFallback("Casks", fallback: "Casks")
            : BPLocalizedWithFallback("Formulae", fallback: "Formulae")
        let subtitle = version.isEmpty ? kindLabel : "\(kindLabel) • \(version)"
        let item = BPCommandPaletteItem(
            id: "pkg:\(cask ? "cask" : "formula"):\(name)",
            title: name,
            subtitle: subtitle,
            symbolName: cask ? "macwindow" : "shippingbox",
            shortcutHint: nil,
            kind: .package,
            packageName: name,
            isCask: cask
        )
        presentation.state.items.append(item)
    }

    @objc
    public func moveSelectionDown() {
        presentation.state.moveSelection(delta: 1)
    }

    @objc
    public func moveSelectionUp() {
        presentation.state.moveSelection(delta: -1)
    }

    @objc
    @discardableResult
    public func executeSelectedItem() -> Bool {
        guard let item = presentation.state.selectedItem else { return false }
        return presentation.execute(item)
    }

    @objc(executeItemWithID:)
    @discardableResult
    public func executeItem(withID id: String) -> Bool {
        guard let item = presentation.state.items.first(where: { $0.id == id }) else { return false }
        return presentation.execute(item)
    }
}

@MainActor
private struct BPCommandPaletteView: View {
    @ObservedObject var presentation: BPCommandPalettePresentation

    private var queryBinding: Binding<String> {
        Binding(
            get: { presentation.state.query },
            set: { presentation.state.query = $0 }
        )
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { presentation.state.selectedItemID },
            set: { presentation.state.selectedItemID = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    BPLocalizedWithFallback("Command_Palette_Placeholder", fallback: "Jump to a view, run a tool, or inspect a package…"),
                    text: queryBinding
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit {
                    _ = presentation.state.selectedItem.map { presentation.execute($0) }
                }
                .accessibilityIdentifier("commandPalette.searchField")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            List(presentation.state.filteredItems, selection: selectionBinding) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let shortcut = item.shortcutHint, !shortcut.isEmpty {
                        Text(shortcut)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    _ = presentation.execute(item)
                }
                .onTapGesture {
                    presentation.state.selectedItemID = item.id
                }
                .tag(Optional(item.id))
            }
            .listStyle(.inset)
            .frame(minHeight: 240, maxHeight: .infinity)
            .accessibilityIdentifier("commandPalette.list")

            HStack {
                Button(BPLocalizedWithFallback("Cancel", fallback: "Cancel")) {
                    presentation.onDismiss?()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("commandPalette.cancel")

                Spacer()

                Button(BPLocalizedWithFallback("Generic_OK", fallback: "OK")) {
                    _ = presentation.state.selectedItem.map { presentation.execute($0) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(presentation.state.selectedItem == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("commandPalette.run")
            }
        }
        .padding(16)
        .frame(width: 520, height: 380)
    }
}

// MARK: - SwiftUI Tahoe Status Bar Host

@MainActor
private final class BPStatusBarPresentation: ObservableObject {
    @Published var state = BPStatusBarState()
    var onOpenCommandPalette: (() -> Void)?
    var onOpenUnifiedUpdates: (() -> Void)?
}

@MainActor
@objc(BPStatusBarHost)
public final class BPStatusBarHost: NSObject {
    public var content: some View { BPStatusBarView(presentation: presentation) }
    private let presentation = BPStatusBarPresentation()
    @objc public let viewController: NSViewController

    @objc public var onOpenCommandPalette: (() -> Void)? {
        get { presentation.onOpenCommandPalette }
        set { presentation.onOpenCommandPalette = newValue }
    }

    @objc public var onOpenUnifiedUpdates: (() -> Void)? {
        get { presentation.onOpenUnifiedUpdates }
        set { presentation.onOpenUnifiedUpdates = newValue }
    }

    @objc public var message: String {
        get { presentation.state.message }
        set { presentation.state.message = newValue }
    }

    @objc public var isBusy: Bool {
        get { presentation.state.isBusy }
        set { presentation.state.isBusy = newValue }
    }

    @objc public var installedCount: Int {
        get { presentation.state.installedCount }
        set { presentation.state.installedCount = newValue }
    }

    @objc public var outdatedCount: Int {
        get { presentation.state.outdatedCount }
        set { presentation.state.outdatedCount = newValue }
    }

    @objc public var pinnedCount: Int {
        get { presentation.state.pinnedCount }
        set { presentation.state.pinnedCount = newValue }
    }

    @objc public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPStatusBarView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()
    }

    @objc(updateWithMessage:isBusy:installedCount:outdatedCount:pinnedCount:)
    public func update(message: String,
                       isBusy: Bool,
                       installedCount: Int,
                       outdatedCount: Int,
                       pinnedCount: Int) {
        presentation.state = BPStatusBarState(
            message: message,
            isBusy: isBusy,
            installedCount: installedCount,
            outdatedCount: outdatedCount,
            pinnedCount: pinnedCount
        )
    }

    @objc public func triggerCommandPalette() {
        presentation.onOpenCommandPalette?()
    }

    @objc public func triggerUnifiedUpdates() {
        presentation.onOpenUnifiedUpdates?()
    }
}

@MainActor
private struct BPStatusBarView: View {
    @ObservedObject var presentation: BPStatusBarPresentation

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.6)

            HStack(spacing: 10) {
                if presentation.state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: 14, height: 14)
                        .accessibilityIdentifier("statusBar.activity")
                        .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(presentation.state.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("statusBar.message")

                Spacer(minLength: 8)

                if presentation.state.installedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(presentation.state.installedCount)")
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .accessibilityIdentifier("statusBar.installedCount")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(NSLocalizedString("Sidebar_Item_Installed", comment: ""))
                    .accessibilityValue(Text(presentation.state.installedCount, format: .number))
                }

                if presentation.state.outdatedCount > 0 {
                    Button {
                        presentation.onOpenUnifiedUpdates?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(presentation.state.outdatedCount)")
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statusBar.outdatedButton")
                    .accessibilityLabel(NSLocalizedString("Sidebar_Item_Unified_Updates", comment: ""))
                    .accessibilityValue(Text(presentation.state.outdatedCount, format: .number))
                }

                Button {
                    presentation.onOpenCommandPalette?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "command")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("K")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help(BPLocalizedWithFallback("Command_Palette_Title", fallback: "Command Palette"))
                .accessibilityIdentifier("statusBar.commandPaletteButton")
                .accessibilityLabel(BPLocalizedWithFallback("Command_Palette_Title", fallback: "Command Palette"))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - SwiftUI Tahoe Sidebar Host & Operation Accessory Cards

@MainActor
final class BPSidebarPresentation: ObservableObject {
    @Published var state = BPSidebarState() {
        didSet { selectionGeneration &+= 1 }
    }
    private var selectionGeneration: UInt64 = 0
    var onSelectRow: ((Int) -> Void)?

    // List can reconcile selection while rendering. Navigation must publish its
    // package, inspector and status models after that view update has finished.
    func selectFromList(_ row: Int?) {
        guard let row else { return }
        selectionGeneration &+= 1
        let generation = selectionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectionGeneration == generation,
                  self.state.selectedRowIndex != row else { return }
            self.state.selectedRowIndex = row
            self.onSelectRow?(row)
        }
    }
}

@MainActor
@objc(BPSidebarHost)
public final class BPSidebarHost: NSObject {
    public var content: some View { BPSidebarView(presentation: presentation) }
    private let presentation = BPSidebarPresentation()
    @objc public let viewController: NSViewController

    @objc public var onSelectRow: ((Int) -> Void)? {
        get { presentation.onSelectRow }
        set { presentation.onSelectRow = newValue }
    }

    @objc public var selectedRowIndex: Int {
        get { presentation.state.selectedRowIndex }
        set { presentation.state.selectedRowIndex = newValue }
    }

    @objc public var sectionCount: Int {
        presentation.state.sections.count
    }

    @objc public var selectableRowCount: Int {
        presentation.state.allRows.count
    }

    @objc public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPSidebarView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()
    }

    @objc public func removeAllSections() {
        presentation.state.sections.removeAll()
    }

    @objc(addSectionWithRowIndex:title:)
    public func addSection(rowIndex: Int, title: String) {
        presentation.state.sections.append(BPSidebarSectionState(rowIndex: rowIndex, title: title))
    }

    @objc(addRowToSectionAtRowIndex:rowIndex:title:groupTitle:symbolName:badgeCount:accessibilityIdentifier:accessibilityLabel:)
    public func addRow(toSectionAtRowIndex sectionRowIndex: Int,
                       rowIndex: Int,
                       title: String,
                       groupTitle: String,
                       symbolName: String,
                       badgeCount: Int,
                       accessibilityIdentifier: String,
                       accessibilityLabel: String) {
        guard let sectionIdx = presentation.state.sections.firstIndex(where: { $0.rowIndex == sectionRowIndex }) else {
            return
        }
        let row = BPSidebarRowState(
            rowIndex: rowIndex,
            title: title,
            groupTitle: groupTitle,
            symbolName: symbolName,
            badgeCount: badgeCount,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel
        )
        presentation.state.sections[sectionIdx].rows.append(row)
    }

    @objc(badgeCountForRowIndex:)
    public func badgeCount(forRowIndex rowIndex: Int) -> Int {
        presentation.state.badgeCount(forRowIndex: rowIndex)
    }

    @objc(selectRowAtIndex:)
    public func selectRow(atIndex rowIndex: Int) {
        presentation.state.selectedRowIndex = rowIndex
        presentation.onSelectRow?(rowIndex)
    }
}

@MainActor
private struct BPSidebarView: View {
    @ObservedObject var presentation: BPSidebarPresentation

    var body: some View {
        List(selection: Binding<Int?>(
            get: { presentation.state.selectedRowIndex },
            set: { presentation.selectFromList($0) }
        )) {
            ForEach(presentation.state.sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        Label {
                            Text(row.title)
                        } icon: {
                            Image(systemName: row.symbolName.isEmpty ? "folder" : row.symbolName)
                        }
                        .badge(row.badgeCount < 0 ? 0 : row.badgeCount)
                        .tag(row.rowIndex)
                        .accessibilityIdentifier(row.accessibilityIdentifier)
                        .accessibilityLabel(row.accessibilityLabel.isEmpty ? row.title : row.accessibilityLabel)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel(NSLocalizedString("Sidebar_VoiceOver_Sidebar", comment: ""))
    }
}


@MainActor
private final class BPTapInputPresentation: ObservableObject {
    @Published var state = BPTapInputState()
}

@MainActor
@objc(BPTapInputHost)
public final class BPTapInputHost: NSObject, NSTextFieldDelegate {
    private let presentation = BPTapInputPresentation()
    @objc public let inputField: NSTextField
    @objc public let viewController: NSViewController

    @objc public var repositoryName: String {
        get { presentation.state.repositoryName }
        set {
            inputField.stringValue = newValue
            presentation.state.repositoryName = newValue
        }
    }

    @objc public var isValidFormat: Bool {
        presentation.state.isValidFormat
    }

    @objc public override init() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "user/repo"
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.bezelStyle = .roundedBezel
        inputField = field

        let presentation = self.presentation
        let host = NSHostingController(
            rootView: BPTapInputCardView(presentation: presentation, inputField: field)
        )
        host.sizingOptions = []
        host.view.frame = NSRect(x: 0, y: 0, width: 320, height: 68)
        viewController = host
        super.init()
        field.delegate = self
    }

    public func controlTextDidChange(_ obj: Notification) {
        presentation.state.repositoryName = inputField.stringValue
    }
}

@MainActor
private struct BPTapInputCardView: View {
    @ObservedObject var presentation: BPTapInputPresentation
    let inputField: NSTextField

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("user/repo", text: Binding(
                get: { presentation.state.repositoryName },
                set: { presentation.state.repositoryName = $0; inputField.stringValue = $0 }
            ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Repository name"))

            HStack(spacing: 5) {
                if presentation.state.trimmedName.isEmpty {
                    Image(systemName: "building.columns")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("user/repo (e.g. homebrew/cask-fonts)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if presentation.state.isValidFormat {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(presentation.state.trimmedName)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(NSLocalizedString("Message_Tap_Invalid_Title", comment: ""))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("tap.input.validation")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 320, height: 68, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

@MainActor
private final class BPCleanupPreviewPresentation: ObservableObject {
    @Published var state: BPCleanupPreviewState

    init(state: BPCleanupPreviewState) {
        self.state = state
    }
}

@MainActor
@objc(BPCleanupPreviewHost)
public final class BPCleanupPreviewHost: NSObject {
    private let presentation: BPCleanupPreviewPresentation
    @objc public let viewController: NSViewController

    @objc public var itemCount: Int {
        presentation.state.itemCount
    }

    @objc public var reclaimableBytes: UInt64 {
        presentation.state.reclaimableBytes
    }

    @objc public var formattedByteCount: String {
        presentation.state.formattedByteCount
    }

    @objc(initWithItemCount:reclaimableBytes:formattedByteCount:samplePaths:)
    public init(itemCount: Int,
                reclaimableBytes: UInt64,
                formattedByteCount: String,
                samplePaths: [String]) {
        let state = BPCleanupPreviewState(
            itemCount: itemCount,
            reclaimableBytes: reclaimableBytes,
            formattedByteCount: formattedByteCount,
            samplePaths: samplePaths
        )
        let presentation = BPCleanupPreviewPresentation(state: state)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPCleanupPreviewCardView(presentation: presentation))
        host.sizingOptions = []
        host.view.frame = NSRect(x: 0, y: 0, width: 340, height: 84)
        viewController = host
        super.init()
    }
}

@MainActor
private struct BPCleanupPreviewCardView: View {
    @ObservedObject var presentation: BPCleanupPreviewPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(
                    presentation.state.itemCount == 1
                        ? BPLocalizedWithFallback("Cleanup_Item_Count_One", fallback: "1 item")
                        : String(
                            format: BPLocalizedWithFallback("Cleanup_Item_Count_Other", fallback: "%lu items"),
                            UInt(max(0, presentation.state.itemCount))
                        )
                )
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .accessibilityIdentifier("cleanup.preview.itemCount")

                Spacer()

                if !presentation.state.formattedByteCount.isEmpty {
                    Text(presentation.state.formattedByteCount)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                        .accessibilityIdentifier("cleanup.preview.byteCount")
                }
            }

            if let firstPath = presentation.state.samplePaths.first {
                Text((firstPath as NSString).lastPathComponent)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("cleanup.preview.samplePath")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 340, height: 84, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}


private struct BPServiceRow: Identifiable {
    let id: String
    let name: String?
    let user: String?
    let status: BPServiceStatus
    init(_ service: BPService) {
        id = service.name ?? ""
        name = service.name
        user = service.user
        status = service.status
    }
}
