import CryptoKit
import Darwin
import Foundation

@objc(BPHomebrewInterface)
open class BPHomebrewInterface: NSObject, BPFormulaDataProvider, BPTaskCompleted, @unchecked Sendable {
    private static let cakebrewOutputIdentifier = "+++++Cakebrew+++++"
    private static let kDebugWarningFormat = "User Shell: %@\nCommand: %@\nOS X Version: %@\n\nThe outputs are going to be different if run from Xcode!!\nInstalling and upgrading formulas is not advised in DEBUG mode!\n\n"

    #if DEBUG
    nonisolated(unsafe) private static var sTestingSharedInterface: BPHomebrewInterface?
    #endif
    nonisolated(unsafe) private static var sDefaultSharedInterface: BPHomebrewInterface?

    // All stored properties have zero-byte defaults so class_createInstance(Cls, 0) works safely.
    @objc public weak var delegate: (any BPHomebrewInterfaceDelegate)?
    @objc public var brewTransport: BPBrewTransport = .direct
    private var _pathShellStorage: NSString?
    private var _tasksStorage: NSMutableDictionary?
    private var _taskOperationsQueueStorage: DispatchQueue?
    private var _currentOperationTaskStorage: BPTask?

    @objc public var path_shell: String? {
        get { _pathShellStorage as String? }
        set { _pathShellStorage = (newValue as NSString?)?.copy() as? NSString }
    }

    @objc public var currentOperationTask: BPTask? {
        get { _currentOperationTaskStorage }
        set { _currentOperationTaskStorage = newValue }
    }

    @objc public var tasks: NSMutableDictionary {
        get {
            bpSynchronized(self) {
                if let existing = _tasksStorage {
                    return existing
                }
                let created = NSMutableDictionary()
                _tasksStorage = created
                return created
            }
        }
        set {
            bpSynchronized(self) {
                _tasksStorage = newValue
            }
        }
    }

    @objc public var taskOperationsQueue: DispatchQueue {
        get {
            bpSynchronized(self) {
                if let existing = _taskOperationsQueueStorage {
                    return existing
                }
                let created = DispatchQueue(
                    label: "com.brunophilipe.Cakebrew.BPHomebrewInterface.Tasks",
                    qos: .userInitiated,
                    attributes: .concurrent
                )
                _taskOperationsQueueStorage = created
                return created
            }
        }
        set {
            bpSynchronized(self) {
                _taskOperationsQueueStorage = newValue
            }
        }
    }

    #if DEBUG
    @objc(setSharedInterfaceForTesting:)
    public class func setSharedInterfaceForTesting(_ interface: BPHomebrewInterface?) {
        bpSynchronized(self) {
            sTestingSharedInterface = interface
        }
    }
    #endif

    @objc public class func sharedInterface() -> BPHomebrewInterface {
        bpSynchronized(self) {
            #if DEBUG
            if let testing = sTestingSharedInterface {
                return testing
            }
            #endif
            if let existing = sDefaultSharedInterface {
                return existing
            }
            let instance: BPHomebrewInterface
            if ProcessInfo.processInfo.arguments.contains("-BPMockBrew"),
               let mockClass = NSClassFromString("BPMockHomebrewInterface") as? BPHomebrewInterface.Type {
                instance = mockClass.init(uniqueInstance: ())
            } else {
                instance = BPHomebrewInterface(uniqueInstance: ())
            }
            sDefaultSharedInterface = instance
            return instance
        }
    }

    @objc(initUniqueInstance)
    public required init(uniqueInstance: Void = ()) {
        super.init()
        _tasksStorage = NSMutableDictionary()
        _taskOperationsQueueStorage = DispatchQueue(
            label: "com.brunophilipe.Cakebrew.BPHomebrewInterface.Tasks",
            qos: .userInitiated,
            attributes: .concurrent
        )
        brewTransport = Self.defaultTransport(whenSandboxed: Self.isRunningSandboxed())
    }

    public override init() {
        super.init()
        _tasksStorage = NSMutableDictionary()
        _taskOperationsQueueStorage = DispatchQueue(
            label: "com.brunophilipe.Cakebrew.BPHomebrewInterface.Tasks",
            qos: .userInitiated,
            attributes: .concurrent
        )
        brewTransport = Self.defaultTransport(whenSandboxed: Self.isRunningSandboxed())
    }

    @objc open func cleanup() {
        let dict = self.tasks
        let snapshot: [BPTask] = bpSynchronized(dict) {
            (dict.allValues as? [BPTask]) ?? []
        }
        for task in snapshot {
            task.cleanup()
        }
    }

    @objc open func cancelAllRunningTasks() {
        let dict = self.tasks
        let snapshot: [BPTask] = bpSynchronized(dict) {
            (dict.allValues as? [BPTask]) ?? []
        }
        for task in snapshot {
            task.cancel()
        }
        currentOperationTask?.cancel()
    }

    @objc open func cancelCurrentOperation() {
        if brewTransport == .helper {
            bpSharedHelperClient()?.cancelCurrentCommand()
            return
        }
        currentOperationTask?.cancel()
    }

    @objc open var hasCancellableOperation: Bool {
        if brewTransport == .helper {
            return true
        }
        return currentOperationTask != nil
    }

    @objc public class func installationURL() -> URL {
        URL(string: "https://brew.sh")!
    }

    @objc(discoveryResultForOutput:exitStatus:)
    public class func discoveryResult(forOutput output: String?, exitStatus status: Int32) -> BPHomebrewDiscoveryResult {
        guard let output else { return .checkFailed }
        let start = output.components(separatedBy: "+++++Cakebrew Discovery+++++\n")
        guard start.count == 2, let last = start.last else { return .checkFailed }
        let end = last.components(separatedBy: "+++++Cakebrew Discovery End+++++\n")
        guard end.count == 2, let first = end.first else { return .checkFailed }
        let path = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 1 && path.isEmpty {
            return .missing
        }
        let nsPath = path as NSString
        if status != 0 || !nsPath.isAbsolutePath || nsPath.rangeOfCharacter(from: .newlines).location != NSNotFound {
            return .checkFailed
        }
        var directory: ObjCBool = false
        let files = FileManager.default
        let isExec = files.fileExists(atPath: path, isDirectory: &directory)
            && !directory.boolValue
            && files.isExecutableFile(atPath: path)
        return isExec ? .available : .checkFailed
    }

    @objc open func discoverHomebrew() -> BPHomebrewDiscoveryResult {
        self.path_shell = getValidUserShellPath()
        guard let shell = self.path_shell else { return .invalidShell }
        let command = "printf '\\n+++++Cakebrew Discovery+++++\\n'; command -v brew; cakebrew_status=$?; printf '+++++Cakebrew Discovery End+++++\\n'; exit \"$cakebrew_status\""
        let task = BPTask(path: shell, arguments: ["-l", "-c", command])
        let status = task.execute()
        return Self.discoveryResult(forOutput: task.output, exitStatus: status)
    }

    @objc open func getValidUserShellPath() -> String? {
        guard let userShell = ProcessInfo.processInfo.environment["SHELL"], !userShell.isEmpty else {
            return nil
        }
        var isValidShell = false
        if let shellsContent = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) {
            for validShell in shellsContent.components(separatedBy: .newlines) {
                if validShell.trimmingCharacters(in: .whitespacesAndNewlines) == userShell {
                    isValidShell = true
                    break
                }
            }
        }
        guard isValidShell, FileManager.default.isExecutableFile(atPath: userShell) else {
            return nil
        }
        #if DEBUG
        NSLog("shell: %@", userShell)
        #endif
        return userShell
    }

    @objc(formatArguments:sendOutputId:)
    open func formatArguments(_ extraArguments: [Any]?, sendOutputId sendOutputID: Bool) -> [Any] {
        let command = sendOutputID
            ? "echo \"\(Self.cakebrewOutputIdentifier)\";brew \"$@\""
            : "brew \"$@\""
        var arguments: [Any] = ["-l", "-c", command, "brew"]
        if let extraArguments {
            arguments.append(contentsOf: extraArguments)
        }
        return arguments
    }

    @objc(task:didFinishWithOutput:error:)
    open func task(_ task: BPTask, didFinishWithOutput output: String, error: String) {
        let dict = self.tasks
        let key = String(format: "%p", Int(bitPattern: Unmanaged.passUnretained(task).toOpaque()))
        bpSynchronized(dict) {
            dict.removeObject(forKey: key)
        }
    }

    @objc(formatAutoremoveArguments:)
    open func formatAutoremoveArguments(_ arguments: [Any]) -> [Any] {
        var result: [Any] = [
            "-l",
            "-c",
            "printf '\\n+++++Cakebrew Autoremove+++++\\n'; /usr/bin/env HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew \"$@\"",
            "brew"
        ]
        result.append(contentsOf: arguments)
        return result
    }

    @objc(executeAutoremoveArguments:progress:output:)
    open func executeAutoremoveArguments(
        _ arguments: [Any],
        progress: Progress?,
        output: (@Sendable (String) -> Void)?
    ) -> Int32 {
        guard brewTransport == .direct, let shell = path_shell, progress?.isCancelled != true else {
            return -1
        }
        let task = BPTask(path: shell, arguments: formatAutoremoveArguments(arguments))
        task.delegate = self
        let preview = (arguments.first as? String) == "autoremove"
        task.updateBlock = preview ? nil : output
        task.cancellationProgress = progress
        progress?.cancellationHandler = {
            DispatchQueue.global(qos: .userInitiated).async {
                task.cancel()
            }
        }
        if progress?.isCancelled == true {
            task.cancel()
        }
        let dict = self.tasks
        let key = String(format: "%p", Int(bitPattern: Unmanaged.passUnretained(task).toOpaque()))
        bpSynchronized(dict) {
            dict[key] = task
        }
        let status = task.execute()
        progress?.cancellationHandler = nil
        task.cancellationProgress = nil
        if preview {
            let nsOut = task.output as NSString
            let marker = nsOut.range(of: "+++++Cakebrew Autoremove+++++\n")
            let clean = marker.location == NSNotFound
                ? task.output
                : nsOut.substring(from: marker.location + marker.length)
            if let output {
                let sep = task.error.isEmpty ? "" : "\n"
                output("\(clean)\(sep)\(task.error)")
            }
            if marker.location == NSNotFound {
                return -1
            }
        }
        return status
    }

    @objc(previewAutoremoveWithProgress:)
    open func previewAutoremove(withProgress progress: Progress?) -> BPAutoremovePreview {
        if brewTransport != .direct {
            return BPAutoremovePreview.preview(
                withOutput: NSLocalizedString(
                    "Unused dependency removal requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.",
                    comment: ""
                ),
                succeeded: false
            )
        }
        nonisolated(unsafe) let raw = NSMutableString()
        let status = executeAutoremoveArguments(["autoremove", "--dry-run"], progress: progress) { chunk in
            raw.append(chunk)
        }
        return BPAutoremovePreview.preview(
            withOutput: raw as String,
            succeeded: status == 0 && progress?.isCancelled != true
        )
    }

    @objc(removeUnusedFormulae:progress:output:)
    open func removeUnusedFormulae(
        _ names: [String]?,
        progress: Progress?,
        output: (@Sendable (String) -> Void)?
    ) -> Bool {
        let count = names?.count ?? 0
        let suffix = count == 1 ? "" : "e"
        let header = String(format: "==> Would autoremove %lu unneeded formula%@:\n", UInt(count), suffix)
        let body = (names ?? []).joined(separator: "\n")
        let validated = BPAutoremovePreview.preview(withOutput: header + body, succeeded: true)
        guard validated.valid, count > 0, progress?.isCancelled != true, brewTransport == .direct else {
            return false
        }
        let args: [Any] = ["uninstall", "--formula"] + validated.names
        let status = executeAutoremoveArguments(args, progress: progress, output: output)
        output?(String(format: NSLocalizedString("\nHomebrew exit status: %d\n", comment: ""), status))
        return status == 0 && progress?.isCancelled != true
    }

    @objc(performBrewCommandWithArguments:dataReturnBlock:)
    open func performBrewCommand(
        withArguments arguments: [Any]?,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(withArguments: arguments, wrapsSynchronousRequest: false, dataReturnBlock: block)
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(
            withArguments: arguments,
            wrapsSynchronousRequest: isSynchronous,
            progress: nil,
            dataReturnBlock: block
        )
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:progress:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        progress: Progress?,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(
            withArguments: arguments,
            wrapsSynchronousRequest: isSynchronous,
            progress: progress,
            includesCompletionMessage: true,
            dataReturnBlock: block
        )
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:includesCompletionMessage:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        includesCompletionMessage: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        performAsyncBrewCommand(
            withArguments: arguments,
            wrapsSynchronousRequest: isSynchronous,
            progress: nil,
            includesCompletionMessage: includesCompletionMessage,
            dataReturnBlock: block
        )
    }

    @objc(performAsyncBrewCommandWithArguments:wrapsSynchronousRequest:progress:includesCompletionMessage:dataReturnBlock:)
    open func performAsyncBrewCommand(
        withArguments arguments: [Any]?,
        wrapsSynchronousRequest isSynchronous: Bool,
        progress: Progress?,
        includesCompletionMessage: Bool,
        dataReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        if brewTransport == .helper {
            guard let client = bpSharedHelperClient() else { return false }
            return client.runBrew(
                withArguments: arguments ?? [],
                outputMarker: isSynchronous ? Self.cakebrewOutputIdentifier : nil,
                outputBlock: block
            )
        }

        let formattedArgs = formatArguments(arguments, sendOutputId: isSynchronous)
        guard let shell = path_shell, !formattedArgs.isEmpty else {
            return false
        }

        let task = BPTask(path: shell, arguments: formattedArgs)
        task.delegate = self
        task.updateBlock = block
        if let progress {
            task.cancellationProgress = progress
            progress.cancellationHandler = {
                DispatchQueue.global(qos: .userInitiated).async {
                    task.cancel()
                }
            }
            if progress.isCancelled {
                task.cancel()
            }
        }

        if !isSynchronous {
            currentOperationTask = task
        }

        let dict = self.tasks
        let key = String(format: "%p", Int(bitPattern: Unmanaged.passUnretained(task).toOpaque()))
        bpSynchronized(dict) {
            dict[key] = task
        }

        #if DEBUG
        if !isSynchronous {
            let joined = formattedArgs.compactMap { $0 as? String }.joined(separator: " ")
            let warning = String(
                format: Self.kDebugWarningFormat,
                shell,
                joined,
                ProcessInfo.processInfo.operatingSystemVersionString
            )
            invokeOutputBlock(block, withString: warning)
        }
        #endif

        let status = task.execute()
        progress?.cancellationHandler = nil
        task.cancellationProgress = nil

        if currentOperationTask === task {
            currentOperationTask = nil
        }

        let taskDoneString = String(
            format: "%@: (%d) %@ %@!",
            NSLocalizedString("Homebrew_Task_Finished", comment: ""),
            status,
            NSLocalizedString("Homebrew_Task_Finished_At", comment: ""),
            DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        )
        if includesCompletionMessage {
            invokeOutputBlock(block, withString: taskDoneString)
        }

        return status == 0
    }

    @objc(invokeOutputBlock:withString:)
    open func invokeOutputBlock(_ block: ((String) -> Void)?, withString string: String) {
        block?(string)
    }

    @objc open func isRunningBackgroundTask() -> Bool {
        let dict = self.tasks
        return bpSynchronized(dict) {
            dict.count > 0
        }
    }

    @objc(performSyncBrewCommandWithArguments:)
    open func performSyncBrewCommand(withArguments arguments: [Any]?) -> String? {
        var finalOutput: String?
        let queue = self.taskOperationsQueue
        queue.sync {
            nonisolated(unsafe) let output = NSMutableString()
            _ = self.performAsyncBrewCommand(withArguments: arguments, wrapsSynchronousRequest: true) { partialOutput in
                output.append(partialOutput)
            }
            finalOutput = output.copy() as? String
        }
        return removeLoginShellOutput(fromString: finalOutput)
    }

    @objc(defaultTransportWhenSandboxed:)
    public class func defaultTransport(whenSandboxed sandboxed: Bool) -> BPBrewTransport {
        sandboxed ? .helper : .direct
    }

    @objc public class func isRunningSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    @objc(isValidTapName:)
    public class func isValidTapName(_ name: String?) -> Bool {
        guard let name else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"
        let nsTrimmed = trimmed as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return regex.numberOfMatches(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length)) == 1
    }

    open func setCaskPinned(_ name: String?, pinned: Bool) -> Bool {
        guard let name else { return false }
        let command = pinned ? "pin" : "unpin"
        let result = performBrewCommand(withArguments: [command, "--cask", name], dataReturnBlock: nil)
        sendDelegateFormulaeUpdatedCall(forCommand: command)
        return result
    }

    @objc open func listPinnedCasks() -> [BPFormula]? {
        let call = BPHomebrewInterfaceListCallPinnedCasks()
        var output: NSString?
        let succeeded = performCleanReadOnlyBrewCommand(withArguments: call.arguments, output: &output)
        guard succeeded, let output else { return nil }
        return call.parseData(output as String)
    }

    @objc(listMode:)
    open func listMode(_ mode: BPListMode) -> [BPFormula]? {
        let listCall: BPHomebrewInterfaceListCall
        switch mode {
        case .installed:
            listCall = BPHomebrewInterfaceListCallInstalled()
        case .all:
            listCall = BPHomebrewInterfaceListCallAll()
        case .leaves:
            listCall = BPHomebrewInterfaceListCallLeaves()
        case .outdated:
            listCall = BPHomebrewInterfaceListCallUpgradeable()
        case .repositories:
            listCall = BPHomebrewInterfaceListCallRepositories()
        case .pinned:
            listCall = BPHomebrewInterfaceListCallPinned()
        case .installedCasks:
            listCall = BPHomebrewInterfaceListCallInstalledCasks()
        case .outdatedCasks:
            listCall = BPHomebrewInterfaceListCallOutdatedCasks()
        case .allCasks:
            listCall = BPHomebrewInterfaceListCallAllCasks()
        default:
            return nil
        }

        if mode == .outdated || mode == .outdatedCasks || mode == .pinned {
            var output: NSString?
            let succeeded = performCleanReadOnlyBrewCommand(withArguments: listCall.arguments, output: &output)
            guard succeeded, let output else { return nil }
            return listCall.parseData(output as String)
        }

        guard let string = performSyncBrewCommand(withArguments: listCall.arguments) else {
            return nil
        }
        return listCall.parseData(string)
    }

    @objc(informationForFormulaName:)
    open func information(forFormulaName name: String?) -> String? {
        guard let name else { return nil }
        return performSyncBrewCommand(withArguments: ["info", name])
    }

    @objc(listModeForRemovalRefresh:)
    open func listMode(forRemovalRefresh mode: BPListMode) -> [BPFormula]? {
        guard brewTransport == .direct else { return nil }
        let listCall: BPHomebrewInterfaceListCall
        switch mode {
        case .installed:
            listCall = BPHomebrewInterfaceListCallInstalled()
        case .leaves:
            listCall = BPHomebrewInterfaceListCallLeaves()
        case .outdated:
            listCall = BPHomebrewInterfaceListCallUpgradeable()
        default:
            return nil
        }
        var output: NSString?
        guard performCleanReadOnlyBrewCommand(withArguments: listCall.arguments, output: &output),
              let output else {
            return nil
        }
        return listCall.parseData(output as String)
    }

    @objc open func listServicesForRemovalRefresh() -> [BPService]? {
        guard brewTransport == .direct else { return nil }
        var output: NSString?
        guard performCleanReadOnlyBrewCommand(withArguments: ["services", "list", "--json"], output: &output) else {
            return nil
        }
        return BPService.validatedServices(fromJSONString: output as String?)
    }

    @objc(informationForCaskName:)
    open func information(forCaskName name: String?) -> String? {
        guard let name else { return nil }
        return performSyncBrewCommand(withArguments: ["info", "--cask", name])
    }

    @objc(serviceDetailsForName:)
    open func serviceDetails(forName name: String?) -> BPServiceDetails {
        guard let name, !name.isEmpty, !name.hasPrefix("-") else {
            return BPServiceDetails.details(forName: name, output: "", succeeded: false)
        }
        if brewTransport == .helper {
            return BPServiceDetails.details(
                forName: name,
                output: NSLocalizedString("Services_Details_Helper_Unavailable", comment: ""),
                succeeded: false
            )
        }
        var output: NSString?
        let succeeded = performCleanReadOnlyBrewCommand(
            withArguments: ["services", "info", "--json", name],
            output: &output
        )
        return BPServiceDetails.details(forName: name, output: output as String?, succeeded: succeeded)
    }

    @objc(performCleanReadOnlyBrewCommandWithArguments:output:)
    open func performCleanReadOnlyBrewCommand(
        withArguments arguments: [Any]?,
        output result: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        var succeeded = false
        var transcript: String?
        let queue = self.taskOperationsQueue
        queue.sync {
            nonisolated(unsafe) let output = NSMutableString()
            succeeded = self.performAsyncBrewCommand(
                withArguments: arguments,
                wrapsSynchronousRequest: true,
                includesCompletionMessage: false
            ) { chunk in
                output.append(chunk)
            }
            transcript = self.removeLoginShellOutput(fromString: output as String)
        }
        result?.pointee = transcript as NSString?
        return succeeded
    }

    @objc open func listServices() -> [BPService] {
        if brewTransport == .direct {
            var output: NSString?
            let succeeded = performCleanReadOnlyBrewCommand(
                withArguments: ["services", "list", "--json"],
                output: &output
            )
            return succeeded ? BPService.services(fromJSONString: output as String?) : []
        }
        let output = performSyncBrewCommand(withArguments: ["services", "list", "--json"])
        return output != nil ? BPService.services(fromJSONString: output) : []
    }

    @objc(startService:withReturnBlock:)
    open func startService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let name else { return false }
        return performBrewCommand(withArguments: ["services", "start", name], dataReturnBlock: block)
    }

    @objc(stopService:withReturnBlock:)
    open func stopService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let name else { return false }
        return performBrewCommand(withArguments: ["services", "stop", name], dataReturnBlock: block)
    }

    @objc(restartService:withReturnBlock:)
    open func restartService(_ name: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let name else { return false }
        return performBrewCommand(withArguments: ["services", "restart", name], dataReturnBlock: block)
    }

    @objc(dependantsForFormulaName:onlyInstalled:)
    open func dependants(forFormulaName name: String?, onlyInstalled: Bool) -> String? {
        guard let name else { return nil }
        var arguments = ["uses"]
        if onlyInstalled {
            arguments.append("--installed")
        }
        arguments.append(name)
        return performSyncBrewCommand(withArguments: arguments)
    }

    @objc(removeLoginShellOutputFromString:)
    open func removeLoginShellOutput(fromString string: String?) -> String? {
        guard let string else { return nil }
        let nsString = string as NSString
        let range = nsString.range(of: Self.cakebrewOutputIdentifier)
        if range.location != NSNotFound && range.location + range.length + 1 <= nsString.length {
            return nsString.substring(from: range.location + range.length + 1)
        }
        return string
    }

    @objc(updateWithReturnBlock:)
    open func update(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(withArguments: ["update"], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "update")
        return val
    }

    private class func upgradeArguments(withPrefix prefix: [String], names: [Any]?) -> [String] {
        var arguments = prefix
        if let names {
            for raw in names {
                if let name = raw as? String {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        arguments.append(trimmed)
                    }
                }
            }
        }
        return arguments
    }

    @objc(argumentsForUpgradingFormulae:)
    public class func arguments(forUpgradingFormulae formulae: [Any]?) -> [String] {
        upgradeArguments(withPrefix: ["upgrade"], names: formulae)
    }

    @objc(argumentsForUpgradingCasks:)
    public class func arguments(forUpgradingCasks casks: [Any]?) -> [String] {
        upgradeArguments(withPrefix: ["upgrade", "--cask"], names: casks)
    }

    @objc(upgradeFormulae:withReturnBlock:)
    open func upgradeFormulae(_ formulae: [Any]?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(
            withArguments: Self.arguments(forUpgradingFormulae: formulae),
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "upgrade")
        return val
    }

    @objc(upgradeSelectedFormulae:progress:withReturnBlock:)
    open func upgradeSelectedFormulae(
        _ formulae: [BPFormula]?,
        progress: Progress?,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        upgradeSelectionReporting(formulae, progress: progress, withReturnBlock: block).succeeded
    }

    @objc(upgradeSelectionReporting:progress:withReturnBlock:)
    open func upgradeSelectionReporting(
        _ formulae: [BPFormula]?,
        progress: Progress?,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> BPUpgradeResult {
        let plan = BPUpgradePlan(selection: formulae)
        var attempted = false
        let result = plan.executeReporting(withProgress: progress) { [weak self] arguments in
            guard let self else { return false }
            attempted = true
            return self.performAsyncBrewCommand(
                withArguments: arguments,
                wrapsSynchronousRequest: false,
                progress: progress,
                dataReturnBlock: block
            )
        }
        if attempted {
            sendDelegateFormulaeUpdatedCall(forCommand: "upgrade")
        }
        return result
    }

    @objc(upgradeCasks:withReturnBlock:)
    open func upgradeCasks(_ casks: [Any]?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(
            withArguments: Self.arguments(forUpgradingCasks: casks),
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "upgrade")
        return val
    }

    @objc(installFormula:withOptions:andReturnBlock:)
    open func installFormula(
        _ formula: String?,
        withOptions options: [Any]?,
        andReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        guard let formula else { return false }
        var params: [Any] = ["install", formula]
        if let options {
            params.append(contentsOf: options)
        }
        let val = performBrewCommand(withArguments: params, dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "install")
        return val
    }

    @objc(installCask:withReturnBlock:)
    open func installCask(_ cask: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let cask else { return false }
        let val = performBrewCommand(withArguments: ["install", "--cask", cask], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "install")
        return val
    }

    @objc(uninstallFormula:withReturnBlock:)
    open func uninstallFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let formula else { return false }
        let val = performBrewCommand(withArguments: ["uninstall", formula], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "uninstall")
        return val
    }

    @objc(argumentsForUninstallingCask:zap:)
    public class func arguments(forUninstallingCask cask: String?, zap: Bool) -> [String] {
        var arguments = ["uninstall", "--cask"]
        if zap {
            arguments.append("--zap")
        }
        if let token = cask?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            arguments.append(token)
        }
        return arguments
    }

    @objc(uninstallCask:withReturnBlock:)
    open func uninstallCask(_ cask: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        uninstallCask(cask, zap: false, withReturnBlock: block)
    }

    @objc(uninstallCask:zap:withReturnBlock:)
    open func uninstallCask(
        _ cask: String?,
        zap: Bool,
        withReturnBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        let val = performBrewCommand(
            withArguments: Self.arguments(forUninstallingCask: cask, zap: zap),
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "uninstall")
        return val
    }

    @objc(tapRepository:withReturnsBlock:)
    open func tapRepository(_ repository: String?, withReturnsBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let repository else { return false }
        let val = performBrewCommand(withArguments: ["tap", repository], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "tap")
        return val
    }

    @objc(untapRepository:withReturnsBlock:)
    open func untapRepository(_ repository: String?, withReturnsBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let repository else { return false }
        let val = performBrewCommand(withArguments: ["untap", repository], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "untap")
        return val
    }

    func versionHistoryReceipt(name: String, cask: Bool) -> BPVersionRelease? {
        BPVersionReceipt.find(name: name, cask: cask)
    }

    open func readVersionHistoryCommand(_ arguments: [String], progress: Progress? = nil) -> (succeeded: Bool, output: String) {
        guard progress?.isCancelled != true else { return (false, "") }
        nonisolated(unsafe) let output = NSMutableString()
        let succeeded = performAsyncBrewCommand(withArguments: arguments, wrapsSynchronousRequest: true,
            progress: progress, includesCompletionMessage: false) { chunk in output.append(chunk) }
        return (succeeded, removeLoginShellOutput(fromString: output as String) ?? "")
    }

    open func runVersionHistoryCommand(_ arguments: [String], progress: Progress,
                                       output: (@Sendable (String) -> Void)?) -> Bool {
        performAsyncBrewCommand(withArguments: arguments, wrapsSynchronousRequest: false,
                               progress: progress, includesCompletionMessage: false, dataReturnBlock: output)
    }

    @objc(pinFormula:withReturnBlock:)
    open func pinFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let formula else { return false }
        let val = performBrewCommand(withArguments: ["pin", formula], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "pin")
        return val
    }

    @objc(unpinFormula:withReturnBlock:)
    open func unpinFormula(_ formula: String?, withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        guard let formula else { return false }
        let val = performBrewCommand(withArguments: ["unpin", formula], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "unpin")
        return val
    }

    @objc(runCleanupWithReturnBlock:)
    open func runCleanup(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        performBrewCommand(withArguments: ["cleanup"], dataReturnBlock: block)
    }

    @objc public class func argumentsForCleanupDryRun() -> [String] {
        ["cleanup", "--dry-run"]
    }

    @objc open func previewCleanup() -> BPCleanupPreview {
        let output = performSyncBrewCommand(withArguments: Self.argumentsForCleanupDryRun())
        return BPCleanupPreview.preview(fromOutput: output)
    }

    @objc(runDoctorWithReturnBlock:)
    open func runDoctor(withReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        let val = performBrewCommand(withArguments: ["doctor"], dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "doctor")
        return val
    }

    @objc(runBrewExportToolWithPath:)
    open func runBrewExportTool(withPath path: String?) -> NSError? {
        guard let path else {
            return NSError(
                domain: "Cakebrew.Brewfile.Export",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        "Homebrew could not export the Brewfile. Check the destination and try again.",
                        comment: ""
                    )
                ]
            )
        }
        nonisolated(unsafe) let output = NSMutableString()
        let succeeded = performAsyncBrewCommand(
            withArguments: ["bundle", "dump", "--force", "--file=\(path)"],
            wrapsSynchronousRequest: false,
            includesCompletionMessage: false
        ) { chunk in
            output.append(chunk)
            if output.length > 1500 {
                output.deleteCharacters(in: NSRange(location: 0, length: output.length - 1500))
            }
        }
        if succeeded {
            return nil
        }
        var description = (output as String).trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            description = NSLocalizedString(
                "Homebrew could not export the Brewfile. Check the destination and try again.",
                comment: ""
            )
        }
        return NSError(
            domain: "Cakebrew.Brewfile.Export",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    @objc(runBrewImportToolWithPath:withReturnsBlock:)
    open func runBrewImportTool(
        withPath path: String?,
        withReturnsBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        guard let path else { return false }
        let arguments = ["bundle", "--file=\(path)"]
        let result = performBrewCommand(withArguments: arguments, dataReturnBlock: block)
        sendDelegateFormulaeUpdatedCall(forCommand: "bundle")
        return result
    }

    @objc(runBrewImportToolWithPath:progress:withReturnsBlock:)
    open func runBrewImportTool(
        withPath path: String?,
        progress: Progress?,
        withReturnsBlock block: (@Sendable (String) -> Void)?
    ) -> Bool {
        guard let path, brewTransport == .direct, progress?.isCancelled != true else {
            return false
        }
        let result = performAsyncBrewCommand(
            withArguments: ["bundle", "--file=\(path)"],
            wrapsSynchronousRequest: false,
            progress: progress,
            dataReturnBlock: block
        )
        sendDelegateFormulaeUpdatedCall(forCommand: "bundle")
        return result && progress?.isCancelled != true
    }

    private static let catalogChangingCommands: Set<String> = ["update", "tap", "untap", "bundle"]

    @objc(brewCommandChangesCatalogMembership:)
    public class func brewCommandChangesCatalogMembership(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else { return false }
        return catalogChangingCommands.contains(command.lowercased())
    }

    @objc(sendDelegateFormulaeUpdatedCallForCommand:)
    open func sendDelegateFormulaeUpdatedCall(forCommand command: String?) {
        let rebuildCatalogs = Self.brewCommandChangesCatalogMembership(command)
        guard let delegate = self.delegate else { return }
        DispatchQueue.main.async {
            delegate.homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs(rebuildCatalogs)
        }
    }
}

