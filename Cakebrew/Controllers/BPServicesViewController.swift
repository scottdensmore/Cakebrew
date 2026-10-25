import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
@objc(BPServicesViewController)
open class BPServicesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let serviceColumnName = NSUserInterfaceItemIdentifier("Name")
    private static let serviceColumnStatus = NSUserInterfaceItemIdentifier("Status")
    private static let serviceColumnUser = NSUserInterfaceItemIdentifier("User")

    @objc open var services: [BPService]?
    @objc open var tableView: NSTableView?
    @objc open var startButton: NSButton?
    @objc open var stopButton: NSButton?
    @objc open var restartButton: NSButton?
    @objc open var operationInFlight: Bool = false
    @objc open var details: BPServiceDetails?
    @objc open var detailsGeneration: UInt = 0
    @objc open var listGeneration: UInt = 0
    @objc open var applyingServices: Bool = false
    @objc open var detailsText: NSTextView?
    @objc open var revealButton: NSButton?
    @objc open var logsButton: NSButton?
    @objc open var outputCopyButton: NSButton?
    @objc open var selectedServiceName: String?
    @objc open var servicesHost: BPServicesHost?

    open override func loadView() {
        let tv = NSTableView(frame: .zero)
        for identifier in [Self.serviceColumnName, Self.serviceColumnStatus, Self.serviceColumnUser] {
            let column = NSTableColumn(identifier: identifier)
            column.title = NSLocalizedString("Services_Column_\(identifier.rawValue)", comment: "")
            column.width = identifier == Self.serviceColumnName ? 260 : 140
            tv.addTableColumn(column)
        }
        tv.dataSource = self
        tv.delegate = self
        tv.allowsMultipleSelection = false
        tv.setAccessibilityLabel(NSLocalizedString("Services_Title", comment: ""))
        self.tableView = tv

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        self.startButton = makeButton(title: NSLocalizedString("Services_Start", comment: ""), action: #selector(startSelectedService(_:)))
        self.stopButton = makeButton(title: NSLocalizedString("Services_Stop", comment: ""), action: #selector(stopSelectedService(_:)))
        self.restartButton = makeButton(title: NSLocalizedString("Services_Restart", comment: ""), action: #selector(restartSelectedService(_:)))

        let detailsScroll = NSScrollView(frame: .zero)
        detailsScroll.hasVerticalScroller = true
        detailsScroll.borderType = .bezelBorder
        let dt = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        dt.isEditable = false
        dt.isSelectable = true
        dt.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        dt.textColor = .labelColor
        dt.backgroundColor = .textBackgroundColor
        dt.textContainerInset = NSSize(width: 8, height: 6)
        dt.autoresizingMask = [.width]
        dt.isVerticallyResizable = true
        dt.isHorizontallyResizable = false
        dt.textContainer?.widthTracksTextView = true
        dt.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        dt.setAccessibilityIdentifier("services.details")
        dt.setAccessibilityLabel(NSLocalizedString("Services_Details_Title", comment: ""))
        self.detailsText = dt
        detailsScroll.documentView = dt

        let revBtn = makeButton(title: NSLocalizedString("Services_Reveal_File", comment: ""), action: #selector(revealServiceFile(_:)))
        let logBtn = makeButton(title: NSLocalizedString("Services_Open_Logs", comment: ""), action: #selector(openServiceLogs(_:)))
        let copyBtn = makeButton(title: NSLocalizedString("Services_Copy_Output", comment: ""), action: #selector(copyServiceOutput(_:)))
        revBtn.setAccessibilityIdentifier("services.revealFile")
        logBtn.setAccessibilityIdentifier("services.openLogs")
        copyBtn.setAccessibilityIdentifier("services.copyOutput")
        self.revealButton = revBtn
        self.logsButton = logBtn
        self.outputCopyButton = copyBtn

        let host = BPServicesHost(tableScrollView: scrollView, detailsScrollView: detailsScroll)
        host.onStart = { [weak self] in self?.startSelectedService(nil) }
        host.onStop = { [weak self] in self?.stopSelectedService(nil) }
        host.onRestart = { [weak self] in self?.restartSelectedService(nil) }
        host.onRevealFile = { [weak self] in self?.revealServiceFile(nil) }
        host.onOpenLogs = { [weak self] in self?.openServiceLogs(nil) }
        host.onCopyOutput = { [weak self] in self?.copyServiceOutput(nil) }
        host.onFilterChanged = { [weak self] in self?.applyServiceFilters() }
        host.onSelectionChanged = { [weak self] name in
            guard let self else { return }
            self.selectedServiceName = name
            self.updateButtonStates()
            self.requestSelectedServiceDetails()
        }
        self.servicesHost = host

        self.view = host.viewController.view
        updateButtonStates()
        showDetailsMessage(NSLocalizedString("Services_Details_Select", comment: ""))
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc open func displayedServices() -> [BPService] {
        let statusFilter = servicesHost?.statusFilterRawValue ?? 0
        let query = (servicesHost?.filterQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let all = services ?? []
        if statusFilter == 0 && query.isEmpty {
            return all
        }

        var filtered: [BPService] = []
        filtered.reserveCapacity(all.count)
        for service in all {
            if statusFilter == 1 && !(service.status == .started || service.status == .scheduled) {
                continue
            }
            if statusFilter == 2 && !(service.status == .none || service.status == .stopped) {
                continue
            }
            if statusFilter == 3 && service.status != .error {
                continue
            }
            if !query.isEmpty {
                let matchesName = service.name?.localizedCaseInsensitiveContains(query) ?? false
                let matchesUser = service.user?.localizedCaseInsensitiveContains(query) ?? false
                let localizedStatus = BPService.localizedName(for: service.status)
                let matchesStatus = localizedStatus.localizedCaseInsensitiveContains(query)
                if !matchesName && !matchesUser && !matchesStatus {
                    continue
                }
            }
            filtered.append(service)
        }
        return filtered
    }

    @objc open func applyServiceFilters() {
        let selectedName = selectedServiceName ?? selectedService()?.name
        applyingServices = true
        tableView?.reloadData()
        let displayed = displayedServices()
        if let selectedName, !selectedName.isEmpty,
           let idx = displayed.firstIndex(where: { $0.name == selectedName }) {
            tableView?.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else {
            tableView?.deselectAll(nil)
        }
        applyingServices = false
        selectedServiceName = selectedService()?.name
        updateButtonStates()
        refreshEmptyState()
        requestSelectedServiceDetails()
    }

    @objc open func refreshServices() {
        let selectedName = selectedService()?.name ?? selectedServiceName
        invalidateServiceDetails()
        let generation = self.listGeneration
        fetchServices { [weak self] fetched in
            MainActor.assumeIsolated {
                guard let self, generation == self.listGeneration else { return }
                self.applyingServices = true
                self.services = fetched
                self.tableView?.reloadData()
                let displayed = self.displayedServices()
                if let selectedName, !selectedName.isEmpty,
                   let idx = displayed.firstIndex(where: { $0.name == selectedName }) {
                    self.tableView?.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                } else {
                    self.tableView?.deselectAll(nil)
                }
                self.applyingServices = false
                self.selectedServiceName = self.selectedService()?.name
                self.updateButtonStates()
                self.refreshEmptyState()
                self.requestSelectedServiceDetails()
            }
        }
    }

    @objc(fetchServicesWithCompletion:)
    open func fetchServices(withCompletion completion: @escaping @Sendable ([BPService]?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let list = bpSharedHomebrewInterface()?.listServices()
            DispatchQueue.main.async {
                completion(list)
            }
        }
    }

    @objc open func selectedService() -> BPService? {
        let displayed = displayedServices()
        if let selectedServiceName { return displayed.first { $0.name == selectedServiceName } }
        guard let row = tableView?.selectedRow, row >= 0 && row < displayed.count else {
            return nil
        }
        return displayed[row]
    }

    @objc open func invalidateServiceDetails() {
        detailsGeneration &+= 1
        listGeneration &+= 1
        details = nil
        showDetailsMessage(NSLocalizedString("Services_Details_Select", comment: ""))
    }

    @objc(fetchDetailsForName:completion:)
    open func fetchDetails(forName name: String?, completion: @escaping @Sendable (BPServiceDetails?) -> Void) {
        let serviceName = name
        DispatchQueue.global(qos: .utility).async {
            let result = bpSharedHomebrewInterface()?.serviceDetails(forName: serviceName)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    @objc open func requestSelectedServiceDetails() {
        detailsGeneration &+= 1
        let generation = detailsGeneration
        details = nil
        guard let name = selectedService()?.name, !name.isEmpty else {
            showDetailsMessage(NSLocalizedString("Services_Details_Select", comment: ""))
            return
        }
        showDetailsMessage(String(format: NSLocalizedString("Services_Details_Loading", comment: ""), name))
        fetchDetails(forName: name) { [weak self] fetched in
            MainActor.assumeIsolated {
                guard let self,
                      generation == self.detailsGeneration,
                      self.selectedService()?.name == name else {
                    return
                }
                self.details = fetched
                self.renderServiceDetails()
            }
        }
    }

    @objc(showDetailsMessage:)
    open func showDetailsMessage(_ message: String?) {
        detailsText?.string = message ?? ""
        servicesHost?.detailsText = message ?? ""
        revealButton?.isEnabled = validatedServiceFileURL() != nil
        logsButton?.isEnabled = !validatedLogURLs().isEmpty
        outputCopyButton?.isEnabled = !(details?.rawOutput.isEmpty ?? true)
        syncServicesHostState()
    }

    @objc open func renderServiceDetails() {
        let service = details?.service ?? selectedService()
        let unknown = NSLocalizedString("Services_Details_Not_Available", comment: "")
        var format = NSLocalizedString("Services_Details_Format", comment: "")
        if format == "Services_Details_Format" {
            format = "Service: %@\nStatus: %@\nPID: %@\nUser: %@\nFile: %@\nLoaded file: %@\nLog: %@\nError log: %@\nExit code: %@"
        }
        let statusName = service.map { BPService.localizedName(for: $0.status) } ?? unknown
        var text = String(
            format: format,
            service?.name ?? unknown,
            statusName,
            service?.pid?.stringValue ?? unknown,
            service?.user ?? unknown,
            details?.serviceFile ?? unknown,
            details?.loadedFile ?? unknown,
            details?.logPath ?? unknown,
            details?.errorLogPath ?? unknown,
            details?.exitCode?.stringValue ?? unknown
        )
        if let details, !details.available {
            text = "\(NSLocalizedString("Services_Details_Failed", comment: ""))\n\(details.rawOutput)\n\n\(text)"
        }
        showDetailsMessage(text)
        servicesHost?.detailsText = detailsText?.string ?? ""
        detailsText?.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    @objc open func validatedLogURLs() -> [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        for path in [details?.logPath ?? "", details?.errorLogPath ?? ""] {
            if let url = BPServiceDetails.readableFileURL(forPath: path), seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    @objc open func showUnavailableFileMessage() {
        let current = detailsText?.string ?? ""
        showDetailsMessage("\(current)\n\n\(NSLocalizedString("Services_File_Unavailable", comment: ""))")
    }

    @objc(revealServiceFile:)
    open func revealServiceFile(_ sender: Any?) {
        guard let url = validatedServiceFileURL() else {
            showUnavailableFileMessage()
            return
        }
        revealValidatedFileURL(url)
    }

    @objc open func validatedServiceFileURL() -> URL? {
        BPServiceDetails.readableFileURL(forPath: details?.loadedFile)
            ?? BPServiceDetails.readableFileURL(forPath: details?.serviceFile)
    }

    @objc(revealValidatedFileURL:)
    open func revealValidatedFileURL(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc(openServiceLogs:)
    open func openServiceLogs(_ sender: Any?) {
        let urls = validatedLogURLs()
        guard !urls.isEmpty else {
            showUnavailableFileMessage()
            return
        }
        openLogURLs(urls)
    }

    @objc(openLogURLs:)
    open func openLogURLs(_ urls: [URL]) {
        guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            showUnavailableFileMessage()
            return
        }
        let generation = detailsGeneration
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: editor,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            if error != nil {
                DispatchQueue.main.async {
                    guard let self, generation == self.detailsGeneration else { return }
                    self.showUnavailableFileMessage()
                }
            }
        }
    }

    @objc(copyServiceOutput:)
    open func copyServiceOutput(_ sender: Any?) {
        guard let raw = details?.rawOutput, !raw.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
    }

    @objc(startSelectedService:)
    open func startSelectedService(_ sender: Any?) {
        runOperation { iface, name, output in
            iface.startService(name, withReturnBlock: output)
        }
    }

    @objc(stopSelectedService:)
    open func stopSelectedService(_ sender: Any?) {
        runOperation { iface, name, output in
            iface.stopService(name, withReturnBlock: output)
        }
    }

    @objc(restartSelectedService:)
    open func restartSelectedService(_ sender: Any?) {
        runOperation { iface, name, output in
            iface.restartService(name, withReturnBlock: output)
        }
    }

    private func runOperation(_ operation: @escaping @Sendable (BPHomebrewInterfaceObjCBridge, String, @escaping @Sendable (String) -> Void) -> Bool) {
        guard let selected = selectedService(), !operationInFlight else {
            return
        }

        let appDelegate = bpSharedAppDelegate()
        if BPAppDelegate.shouldBlockOperation(whileRunningBackgroundTask: appDelegate?.isRunningBackgroundTask == true) {
            appDelegate?.displayBackgroundWarning()
            return
        }

        let name = selected.name ?? ""
        operationInFlight = true
        invalidateServiceDetails()
        updateButtonStates()

        DispatchQueue.global(qos: .background).async { [weak self] in
            nonisolated(unsafe) let output = NSMutableString()
            let succeeded: Bool
            if let iface = bpSharedHomebrewInterface() {
                succeeded = operation(iface, name) { chunk in
                    bpSynchronized(output) {
                        output.append(chunk)
                    }
                }
            } else {
                succeeded = false
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.operationInFlight = false
                self.refreshServices()

                if !succeeded {
                    let transcript: String = bpSynchronized(output) { output.copy() as? String ?? "" }
                    self.presentServiceFailure(forName: name, output: transcript)
                }
            }
        }
    }

    @objc(presentServiceFailureForName:output:)
    open func presentServiceFailure(forName name: String, output: String) {
        let error = BPBrewError.error(forExitStatus: 1, output: output)
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Services_Operation_Failed_Title", comment: ""), name)
        alert.informativeText = error?.localizedDescription ?? ""
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        if let window = bpSharedAppDelegate()?.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    @objc open func refreshEmptyState() {
        let displayed = displayedServices()
        let isFiltering = (servicesHost?.statusFilterRawValue ?? 0) != 0 || !(servicesHost?.filterQuery.isEmpty ?? true)
        var state: BPEmptyState?
        if BPEmptyState.shouldShow(forRowCount: displayed.count, loading: false) {
            state = BPEmptyState.state(
                forSidebarRow: Int(FormulaeSideBarItem.services.rawValue),
                searching: isFiltering && !(services?.isEmpty ?? true)
            )
        }
        BPEmptyStateView.presentState(state, over: tableView?.enclosingScrollView)
    }

    @objc open func updateButtonStates() {
        let service = selectedService()
        let enabled = service != nil && !operationInFlight
        let running = service?.status == .started || service?.status == .scheduled

        startButton?.isEnabled = enabled && !running
        stopButton?.isEnabled = enabled && running
        restartButton?.isEnabled = enabled
        syncServicesHostState()
    }

    @objc open func syncServicesHostState() {
        servicesHost?.updateRows(displayedServices(), selectedName: selectedServiceName)
        var runningCount = 0
        var stoppedCount = 0
        var errorCount = 0
        for service in services ?? [] {
            if service.status == .started || service.status == .scheduled {
                runningCount += 1
            } else if service.status == .error {
                errorCount += 1
            } else {
                stoppedCount += 1
            }
        }
        servicesHost?.syncCounts(running: runningCount, stopped: stoppedCount, error: errorCount)
        let serviceFilePath = !(details?.loadedFile?.isEmpty ?? true) ? details?.loadedFile : details?.serviceFile
        let logFilePath = !(details?.logPath?.isEmpty ?? true) ? details?.logPath : details?.errorLogPath
        servicesHost?.syncPaths(serviceFile: serviceFilePath, logFile: logFilePath)
        servicesHost?.update(
            startEnabled: startButton?.isEnabled ?? false,
            stopEnabled: stopButton?.isEnabled ?? false,
            restartEnabled: restartButton?.isEnabled ?? false,
            revealEnabled: revealButton?.isEnabled ?? false,
            logsEnabled: logsButton?.isEnabled ?? false,
            copyEnabled: outputCopyButton?.isEnabled ?? false
        )
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        displayedServices().count
    }

    public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let displayed = displayedServices()
        guard row >= 0 && row < displayed.count else {
            return ""
        }
        let service = displayed[row]
        if tableColumn?.identifier == Self.serviceColumnName {
            return service.name
        }
        if tableColumn?.identifier == Self.serviceColumnStatus {
            return BPService.localizedName(for: service.status)
        }
        if tableColumn?.identifier == Self.serviceColumnUser {
            return service.user ?? "--"
        }
        return ""
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        selectedServiceName = selectedService()?.name
        updateButtonStates()
        if !applyingServices {
            requestSelectedServiceDetails()
        }
    }
}

@MainActor
@objc(BPDeferredServicesController)
public final class BPDeferredServicesController: BPServicesViewController {
    @objc public var completions: NSMutableArray?
    @objc public var listCompletion: (([BPService]?) -> Void)?
    @objc public var openedURLs: [URL]?
    @objc public var revealedURL: URL?

    public override func fetchDetails(forName name: String?, completion: @escaping @Sendable (BPServiceDetails?) -> Void) {
        let block: @convention(block) (BPServiceDetails?) -> Void = { details in
            completion(details)
        }
        completions?.add(unsafeBitCast(block, to: AnyObject.self))
    }

    public override func fetchServices(withCompletion completion: @escaping @Sendable ([BPService]?) -> Void) {
        self.listCompletion = completion
    }

    public override func openLogURLs(_ urls: [URL]) {
        self.openedURLs = urls
    }

    public override func revealValidatedFileURL(_ url: URL) {
        self.revealedURL = url
    }
}
