import CryptoKit
import Darwin
import Foundation

// MARK: - SwiftUI Tahoe Surface State Models

public struct BPEmptyStateModel: Equatable, Sendable {
    public let symbolName: String
    public let title: String
    public let message: String

    public init(symbolName: String, title: String, message: String) {
        self.symbolName = symbolName.isEmpty ? "tray" : symbolName
        self.title = title
        self.message = message
    }

    public var combinedAccessibilityLabel: String {
        "\(title). \(message)"
    }
}

public struct BPDisabledRecoveryState: Equatable, Sendable {
    public var title: String
    public var message: String
    public var retryEnabled: Bool
    public var isChecking: Bool

    public init(title: String = "",
                message: String = "",
                retryEnabled: Bool = true,
                isChecking: Bool = false) {
        self.title = title
        self.message = message
        self.retryEnabled = retryEnabled
        self.isChecking = isChecking
    }
}

public enum BPConsoleDiagnosticSeverity: Int, Equatable, Sendable {
    case idle = 0
    case running = 1
    case healthy = 2
    case warnings = 3
    case errors = 4
}

private func BPSplitLogLines(_ text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    var lines = text.components(separatedBy: .newlines)
    while lines.last == "" {
        lines.removeLast()
    }
    return lines
}

private func BPFilterLogLines(_ lines: [String], query: String) -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return lines }
    return lines.filter { $0.localizedCaseInsensitiveContains(trimmed) }
}

public struct BPConsoleToolState: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    public var runButtonTitle: String
    public var clearButtonTitle: String
    public var isRunning: Bool
    public var logText: String
    public var filterQuery: String

    public init(title: String = "",
                subtitle: String? = nil,
                runButtonTitle: String = "",
                clearButtonTitle: String = "",
                isRunning: Bool = false,
                logText: String = "",
                filterQuery: String = "") {
        self.title = title
        self.subtitle = subtitle
        self.runButtonTitle = runButtonTitle
        self.clearButtonTitle = clearButtonTitle
        self.isRunning = isRunning
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }

    public var warningCount: Int {
        allLines.reduce(into: 0) { count, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "warning:", options: [.caseInsensitive, .anchored]) != nil {
                count += 1
            }
        }
    }

    public var errorCount: Int {
        allLines.reduce(into: 0) { count, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "error:", options: [.caseInsensitive, .anchored]) != nil {
                count += 1
            }
        }
    }

    public var diagnosticSeverity: BPConsoleDiagnosticSeverity {
        if isRunning {
            return .running
        }
        if logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .idle
        }
        if errorCount > 0 {
            return .errors
        }
        if warningCount > 0 {
            return .warnings
        }
        return .healthy
    }

    public var diagnosticSummaryText: String {
        switch diagnosticSeverity {
        case .idle:
            return ""
        case .running:
            return NSLocalizedString("VoiceOver_Operation_Progress", comment: "")
        case .healthy:
            return NSLocalizedString("Homebrew_Task_Finished", comment: "")
        case .warnings:
            return "\(warningCount) \(NSLocalizedString("Generic_Attention", comment: ""))"
        case .errors:
            return "\(errorCount) \(NSLocalizedString("Generic_Error", comment: ""))"
        }
    }
}

public struct BPAutoremoveSheetState: Equatable, Sendable {
    public var statusText: String
    public var warningText: String
    public var removeButtonTitle: String
    public var cancelButtonTitle: String
    public var removeEnabled: Bool
    public var cancelEnabled: Bool
    public var isBusy: Bool
    public var candidateCount: Int
    public var logText: String
    public var filterQuery: String

    public init(statusText: String = "",
                warningText: String = "",
                removeButtonTitle: String = "",
                cancelButtonTitle: String = "",
                removeEnabled: Bool = false,
                cancelEnabled: Bool = true,
                isBusy: Bool = true,
                candidateCount: Int = 0,
                logText: String = "",
                filterQuery: String = "") {
        self.statusText = statusText
        self.warningText = warningText
        self.removeButtonTitle = removeButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
        self.removeEnabled = removeEnabled
        self.cancelEnabled = cancelEnabled
        self.isBusy = isBusy
        self.candidateCount = candidateCount
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }
}

public enum BPBundleOperationMode: Int, Equatable, Sendable {
    case importing = 0
    case exporting = 1
}

public struct BPBundleSheetState: Equatable, Sendable {
    public var mode: BPBundleOperationMode
    public var headerTitle: String
    public var subtitleText: String
    public var statusText: String
    public var detailText: String
    public var actionButtonTitle: String
    public var actionEnabled: Bool
    public var isRunning: Bool
    public var hasFinished: Bool
    public var succeeded: Bool
    public var logText: String
    public var filterQuery: String

    public init(mode: BPBundleOperationMode = .importing,
                headerTitle: String = "",
                subtitleText: String = "",
                statusText: String = "",
                detailText: String = "",
                actionButtonTitle: String = "",
                actionEnabled: Bool = true,
                isRunning: Bool = true,
                hasFinished: Bool = false,
                succeeded: Bool = false,
                logText: String = "",
                filterQuery: String = "") {
        self.mode = mode
        self.headerTitle = headerTitle
        self.subtitleText = subtitleText
        self.statusText = statusText
        self.detailText = detailText
        self.actionButtonTitle = actionButtonTitle
        self.actionEnabled = actionEnabled
        self.isRunning = isRunning
        self.hasFinished = hasFinished
        self.succeeded = succeeded
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }
}

public struct BPFormulaOptionRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let explanation: String
    public var isApplied: Bool

    public init(name: String, explanation: String, isApplied: Bool = false) {
        self.id = name
        self.name = name
        self.explanation = explanation
        self.isApplied = isApplied
    }
}

public struct BPFormulaOptionsSheetState: Equatable, Sendable {
    public var formulaName: String
    public var headerTitle: String
    public var helpText: String
    public var optionsColumnTitle: String
    public var descriptionPlaceholder: String
    public var cancelTitle: String
    public var installTitle: String
    public var options: [BPFormulaOptionRow]
    public var selectedOptionID: String?
    public var filterQuery: String

    public init(formulaName: String = "",
                headerTitle: String = "",
                helpText: String = "",
                optionsColumnTitle: String = "",
                descriptionPlaceholder: String = "",
                cancelTitle: String = "",
                installTitle: String = "",
                options: [BPFormulaOptionRow] = [],
                selectedOptionID: String? = nil,
                filterQuery: String = "") {
        self.formulaName = formulaName
        self.headerTitle = headerTitle
        self.helpText = helpText
        self.optionsColumnTitle = optionsColumnTitle
        self.descriptionPlaceholder = descriptionPlaceholder
        self.cancelTitle = cancelTitle
        self.installTitle = installTitle
        self.options = options
        self.selectedOptionID = selectedOptionID ?? options.first?.id
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var filteredOptions: [BPFormulaOptionRow] {
        let query = trimmedFilterQuery
        guard !query.isEmpty else { return options }
        return options.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.explanation.localizedCaseInsensitiveContains(query)
        }
    }

    public var selectedOptionNames: [String] {
        options.filter(\.isApplied).map(\.name)
    }

    public var appliedOptionCount: Int {
        options.reduce(into: 0) { count, row in
            if row.isApplied { count += 1 }
        }
    }

    public var selectedOptionDescription: String {
        guard let selectedOptionID,
              let row = options.first(where: { $0.id == selectedOptionID }),
              !row.explanation.isEmpty else {
            return descriptionPlaceholder
        }
        return row.explanation
    }

    public mutating func setApplied(_ applied: Bool, forOptionID id: String) {
        guard let index = options.firstIndex(where: { $0.id == id }) else { return }
        options[index].isApplied = applied
        selectedOptionID = id
    }

    public mutating func clearAllApplied() {
        for index in options.indices {
            options[index].isApplied = false
        }
    }
}

public enum BPServiceStatusFilter: Int, Equatable, Sendable {
    case all = 0
    case running = 1
    case stopped = 2
    case error = 3
}

public struct BPServicesState: Equatable, Sendable {
    public var statusFilter: BPServiceStatusFilter
    public var filterQuery: String
    public var runningCount: Int
    public var stoppedCount: Int
    public var errorCount: Int
    public var serviceFilePath: String
    public var logFilePath: String

    public init(statusFilter: BPServiceStatusFilter = .all,
                filterQuery: String = "",
                runningCount: Int = 0,
                stoppedCount: Int = 0,
                errorCount: Int = 0,
                serviceFilePath: String = "",
                logFilePath: String = "") {
        self.statusFilter = statusFilter
        self.filterQuery = filterQuery
        self.runningCount = runningCount
        self.stoppedCount = stoppedCount
        self.errorCount = errorCount
        self.serviceFilePath = serviceFilePath
        self.logFilePath = logFilePath
    }

    public var totalCount: Int {
        runningCount + stoppedCount + errorCount
    }
}

public struct BPInstallationSheetState: Equatable, Sendable {
    public var windowTitle: String
    public var formulaNamesText: String
    public var okTitle: String
    public var cancelTitle: String
    public var isRunning: Bool
    public var okEnabled: Bool
    public var cancelEnabled: Bool
    public var logText: String
    public var filterQuery: String

    public init(windowTitle: String = "",
                formulaNamesText: String = "",
                okTitle: String = "",
                cancelTitle: String = "",
                isRunning: Bool = true,
                okEnabled: Bool = false,
                cancelEnabled: Bool = true,
                logText: String = "",
                filterQuery: String = "") {
        self.windowTitle = windowTitle
        self.formulaNamesText = formulaNamesText
        self.okTitle = okTitle
        self.cancelTitle = cancelTitle
        self.isRunning = isRunning
        self.okEnabled = okEnabled
        self.cancelEnabled = cancelEnabled
        self.logText = logText
        self.filterQuery = filterQuery
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var allLines: [String] {
        BPSplitLogLines(logText)
    }

    public var filteredLines: [String] {
        BPFilterLogLines(allLines, query: filterQuery)
    }

    public var filteredOutputText: String {
        trimmedFilterQuery.isEmpty ? logText : filteredLines.joined(separator: "\n")
    }

    public var totalLineCount: Int {
        allLines.count
    }

    public var matchingLineCount: Int {
        filteredLines.count
    }
}

// MARK: - SwiftUI Tahoe About, Brewfile Review & Command Palette State Models

public enum BPAboutWindowTab: Int, Equatable, Sendable {
    case credits = 0
    case acknowledgements = 1
}

public struct BPAboutWindowState: Equatable, Sendable {
    public var appName: String
    public var appVersion: String
    public var appCopyright: String
    public var selectedTab: BPAboutWindowTab
    public var hasAcknowledgements: Bool

    public init(appName: String = "Cakebrew",
                appVersion: String = "",
                appCopyright: String = "",
                selectedTab: BPAboutWindowTab = .credits,
                hasAcknowledgements: Bool = true) {
        self.appName = appName
        self.appVersion = appVersion
        self.appCopyright = appCopyright
        self.selectedTab = selectedTab
        self.hasAcknowledgements = hasAcknowledgements
    }

    public var versionClipboardSummary: String {
        if appVersion.isEmpty {
            return appName
        }
        return "\(appName) (\(appVersion))"
    }
}

public enum BPBrewfileEntryFilter: Int, Equatable, Sendable {
    case all = 0
    case installed = 1
    case missing = 2
}

public struct BPBrewfileReviewState: Equatable, Sendable {
    public var fileName: String
    public var installedCount: Int
    public var missingCount: Int
    public var notCheckedCount: Int
    public var formulaCount: Int
    public var caskCount: Int
    public var tapCount: Int
    public var otherCount: Int
    public var canInstall: Bool
    public var summaryText: String
    public var statusFilter: BPBrewfileEntryFilter
    public var filterQuery: String

    public init(fileName: String = "Brewfile",
                installedCount: Int = 0,
                missingCount: Int = 0,
                notCheckedCount: Int = 0,
                formulaCount: Int = 0,
                caskCount: Int = 0,
                tapCount: Int = 0,
                otherCount: Int = 0,
                canInstall: Bool = false,
                summaryText: String = "",
                statusFilter: BPBrewfileEntryFilter = .all,
                filterQuery: String = "") {
        self.fileName = fileName
        self.installedCount = installedCount
        self.missingCount = missingCount
        self.notCheckedCount = notCheckedCount
        self.formulaCount = formulaCount
        self.caskCount = caskCount
        self.tapCount = tapCount
        self.otherCount = otherCount
        self.canInstall = canInstall
        self.summaryText = summaryText
        self.statusFilter = statusFilter
        self.filterQuery = filterQuery
    }

    public var totalEntryCount: Int {
        formulaCount + caskCount + tapCount + otherCount
    }

    public var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isFiltering: Bool {
        statusFilter != .all || !trimmedFilterQuery.isEmpty
    }

    public var filteredSummaryLines: [String] {
        let lines = BPSplitLogLines(summaryText)
        guard isFiltering else { return lines }
        let installedToken = NSLocalizedString("Installed", comment: "")
        let missingToken = NSLocalizedString("Missing", comment: "")
        let query = trimmedFilterQuery
        return lines.filter { line in
            guard line.contains(" — ") || line.contains("[") else { return false }
            let matchesStatus: Bool
            switch statusFilter {
            case .all:
                matchesStatus = true
            case .installed:
                matchesStatus = line.localizedCaseInsensitiveContains(installedToken)
                    || line.localizedCaseInsensitiveContains("Installed")
            case .missing:
                matchesStatus = line.localizedCaseInsensitiveContains(missingToken)
                    || line.localizedCaseInsensitiveContains("Missing")
            }
            guard matchesStatus else { return false }
            guard !query.isEmpty else { return true }
            return line.localizedCaseInsensitiveContains(query)
        }
    }

    public var filteredSummaryText: String {
        isFiltering ? filteredSummaryLines.joined(separator: "\n") : summaryText
    }

    public var matchingEntryCount: Int {
        if !isFiltering {
            return totalEntryCount
        }
        return filteredSummaryLines.count
    }
}

public enum BPCommandPaletteItemKind: Int, Equatable, Sendable {
    case navigation = 0
    case action = 1
    case package = 2
}

public struct BPCommandPaletteItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbolName: String
    public let shortcutHint: String?
    public let kind: BPCommandPaletteItemKind
    public let sidebarRow: Int
    public let actionIdentifier: String?
    public let packageName: String?
    public let isCask: Bool

    public init(id: String,
                title: String,
                subtitle: String = "",
                symbolName: String = "sparkle.magnifyingglass",
                shortcutHint: String? = nil,
                kind: BPCommandPaletteItemKind,
                sidebarRow: Int = -1,
                actionIdentifier: String? = nil,
                packageName: String? = nil,
                isCask: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.shortcutHint = shortcutHint
        self.kind = kind
        self.sidebarRow = sidebarRow
        self.actionIdentifier = actionIdentifier
        self.packageName = packageName
        self.isCask = isCask
    }
}

public struct BPCommandPaletteState: Equatable, Sendable {
    public var query: String = "" {
        didSet {
            normalizeSelection()
        }
    }
    public var items: [BPCommandPaletteItem] = [] {
        didSet {
            normalizeSelection()
        }
    }
    public var selectedItemID: String?

    public init(query: String = "",
                items: [BPCommandPaletteItem] = [],
                selectedItemID: String? = nil) {
        self.query = query
        self.items = items
        self.selectedItemID = selectedItemID
        normalizeSelection()
    }

    public var filteredItems: [BPCommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items
        }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
                || item.subtitle.localizedCaseInsensitiveContains(trimmed)
                || (item.packageName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    public var selectedItem: BPCommandPaletteItem? {
        let current = filteredItems
        if let selectedItemID, let match = current.first(where: { $0.id == selectedItemID }) {
            return match
        }
        return current.first
    }

    public mutating func normalizeSelection() {
        let current = filteredItems
        if let selectedItemID, current.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = current.first?.id
    }

    public mutating func moveSelection(delta: Int) {
        let current = filteredItems
        guard !current.isEmpty else {
            selectedItemID = nil
            return
        }
        guard let selectedItemID,
              let index = current.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = current.first?.id
            return
        }
        let nextIndex = max(0, min(current.count - 1, index + delta))
        self.selectedItemID = current[nextIndex].id
    }
}

public struct BPStatusBarState: Equatable, Sendable {
    public var message: String
    public var isBusy: Bool
    public var installedCount: Int
    public var outdatedCount: Int
    public var pinnedCount: Int

    public init(message: String = "",
                isBusy: Bool = false,
                installedCount: Int = 0,
                outdatedCount: Int = 0,
                pinnedCount: Int = 0) {
        self.message = message
        self.isBusy = isBusy
        self.installedCount = installedCount
        self.outdatedCount = outdatedCount
        self.pinnedCount = pinnedCount
    }
}

public struct BPSidebarRowState: Identifiable, Equatable, Sendable {
    public let id: String
    public let rowIndex: Int
    public let title: String
    public let groupTitle: String
    public let symbolName: String
    public var badgeCount: Int
    public let accessibilityIdentifier: String
    public var accessibilityLabel: String

    public init(rowIndex: Int,
                title: String,
                groupTitle: String,
                symbolName: String,
                badgeCount: Int = -1,
                accessibilityIdentifier: String,
                accessibilityLabel: String = "") {
        self.id = accessibilityIdentifier.isEmpty ? "row.\(rowIndex)" : accessibilityIdentifier
        self.rowIndex = rowIndex
        self.title = title
        self.groupTitle = groupTitle
        self.symbolName = symbolName
        self.badgeCount = badgeCount
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct BPSidebarSectionState: Identifiable, Equatable, Sendable {
    public let id: String
    public let rowIndex: Int
    public let title: String
    public var rows: [BPSidebarRowState]

    public init(rowIndex: Int, title: String, rows: [BPSidebarRowState] = []) {
        self.id = "section.\(rowIndex)"
        self.rowIndex = rowIndex
        self.title = title
        self.rows = rows
    }
}

public struct BPSidebarState: Equatable, Sendable {
    public var sections: [BPSidebarSectionState]
    public var selectedRowIndex: Int

    public init(sections: [BPSidebarSectionState] = [], selectedRowIndex: Int = 1) {
        self.sections = sections
        self.selectedRowIndex = selectedRowIndex
    }

    public var allRows: [BPSidebarRowState] {
        sections.flatMap(\.rows)
    }

    public var selectedRow: BPSidebarRowState? {
        allRows.first(where: { $0.rowIndex == selectedRowIndex })
    }

    public func badgeCount(forRowIndex rowIndex: Int) -> Int {
        allRows.first(where: { $0.rowIndex == rowIndex })?.badgeCount ?? -1
    }
}

public struct BPTapInputState: Equatable, Sendable {
    public var repositoryName: String

    public init(repositoryName: String = "") {
        self.repositoryName = repositoryName
    }

    public var trimmedName: String {
        repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValidFormat: Bool {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
}

public struct BPCleanupPreviewState: Equatable, Sendable {
    public var itemCount: Int
    public var reclaimableBytes: UInt64
    public var formattedByteCount: String
    public var samplePaths: [String]

    public init(itemCount: Int = 0,
                reclaimableBytes: UInt64 = 0,
                formattedByteCount: String = "",
                samplePaths: [String] = []) {
        self.itemCount = itemCount
        self.reclaimableBytes = reclaimableBytes
        self.formattedByteCount = formattedByteCount
        self.samplePaths = samplePaths
    }
}

