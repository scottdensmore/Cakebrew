import CryptoKit
import Darwin
import Foundation

@objc(BPHomebrewDiscoveryResult)
public enum BPHomebrewDiscoveryResult: Int, Sendable {
    @objc(BPHomebrewDiscoveryUnknown) case unknown = 0
    @objc(BPHomebrewDiscoveryAvailable) case available = 1
    @objc(BPHomebrewDiscoveryMissing) case missing = 2
    @objc(BPHomebrewDiscoveryInvalidShell) case invalidShell = 3
    @objc(BPHomebrewDiscoveryCheckFailed) case checkFailed = 4
}

@objc(BPBrewTransport)
public enum BPBrewTransport: Int, Sendable {
    @objc(kBPBrewTransportDirect) case direct = 0
    @objc(kBPBrewTransportHelper) case helper = 1
}

@objc(BPListMode)
public enum BPListMode: Int, Sendable {
    @objc(kBPListAll) case all = 0
    @objc(kBPListInstalled) case installed = 1
    @objc(kBPListLeaves) case leaves = 2
    @objc(kBPListOutdated) case outdated = 3
    @objc(kBPListSearch) case search = 4
    @objc(kBPListRepositories) case repositories = 5
    @objc(kBPListPinned) case pinned = 6
    @objc(kBPListInstalledCasks) case installedCasks = 7
    @objc(kBPListOutdatedCasks) case outdatedCasks = 8
    @objc(kBPListAllCasks) case allCasks = 9
}

@objc(BPFormulaDataProvider)
public protocol BPFormulaDataProvider: NSObjectProtocol {
    @objc(informationForFormulaName:)
    func information(forFormulaName name: String?) -> String?

    @objc(informationForCaskName:)
    optional func information(forCaskName name: String?) -> String?
}

@objc(BPFormula)
open class BPFormula: NSObject, NSSecureCoding, NSCopying, BPFormulaObjCBridge, @unchecked Sendable {
    public static let didUpdateNotification = Notification.Name("BPFormulaDidUpdateNotification")

    nonisolated(unsafe) private static var kvoContext: UInt8 = 0

    private static let encodeFormulaName = "BP_ENCODE_FORMULA_NAME"
    private static let encodeFormulaIver = "BP_ENCODE_FORMULA_IVER"
    private static let encodeFormulaLver = "BP_ENCODE_FORMULA_LVER"
    private static let encodeFormulaPath = "BP_ENCODE_FORMULA_PATH"
    private static let encodeFormulaWurl = "BP_ENCODE_FORMULA_WURL"
    private static let encodeFormulaDeps = "BP_ENCODE_FORMULA_DEPS"
    private static let encodeFormulaInst = "BP_ENCODE_FORMULA_INST"
    private static let encodeFormulaCask = "BP_ENCODE_FORMULA_CASK"
    private static let encodeFormulaCnfl = "BP_ENCODE_FORMULA_CNFL"
    private static let encodeFormulaSdsc = "BP_ENCODE_FORMULA_SDSC"
    private static let encodeFormulaInfo = "BP_ENCODE_FORMULA_INFO"
    private static let encodeFormulaOptn = "BP_ENCODE_FORMULA_OPTN"

    private static let identifierDependencies = "==> Dependencies"
    private static let identifierOptions = "==> Options"
    private static let identifierCaveats = "==> Caveats"

    @objc open var name: String?
    @objc open var version: String?
    @objc open var latestVersion: String?
    @objc open var installPath: String?
    @objc open var dependencies: String?
    @objc open var conflicts: String?
    @objc open var shortDescription: String?
    @objc open var information: String?
    @objc open var website: URL?
    @objc open var options: [Any]?
    @objc open var cask: Bool = false
    @objc public var observerAdded: Bool = false
    @objc public var customDataProvider: (any BPFormulaDataProvider)?

    private var isObservingNeedsInformation: Bool = false
    private var isSuppressingNeedsInformationKVO: Bool = false

    @objc dynamic open var needsInformation: Bool = false

    @objc open class var defaultDataProviderClass: AnyClass? {
        nil
    }

    public static var supportsSecureCoding: Bool {
        true
    }

    public required override init() {
        super.init()
    }

    @objc(formulaWithName:version:andLatestVersion:)
    open class func formula(withName name: String?, version: String?, andLatestVersion latestVersion: String?) -> Self {
        let formula = self.init()
        formula.name = name
        formula.version = version
        formula.latestVersion = latestVersion
        formula.commonInit()
        return formula
    }

    @objc(formulaWithName:andVersion:)
    open class func formula(withName name: String?, andVersion version: String?) -> Self {
        return self.formula(withName: name, version: version, andLatestVersion: nil)
    }

    @objc(formulaWithName:)
    open class func formula(withName name: String?) -> Self {
        return self.formula(withName: name, andVersion: nil)
    }

    @objc(namesFromListOutput:)
    open class func names(fromListOutput output: String?) -> [String] {
        guard let output else { return [] }
        let separators = CharacterSet.whitespacesAndNewlines
        return output.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    open func encode(with aCoder: NSCoder) {
        if let name { aCoder.encode(name, forKey: Self.encodeFormulaName) }
        if let version { aCoder.encode(version, forKey: Self.encodeFormulaIver) }
        if let latestVersion { aCoder.encode(latestVersion, forKey: Self.encodeFormulaLver) }
        if let installPath { aCoder.encode(installPath, forKey: Self.encodeFormulaPath) }
        if let website { aCoder.encode(website, forKey: Self.encodeFormulaWurl) }
        if let dependencies { aCoder.encode(dependencies, forKey: Self.encodeFormulaDeps) }
        if let conflicts { aCoder.encode(conflicts, forKey: Self.encodeFormulaCnfl) }
        if let shortDescription { aCoder.encode(shortDescription, forKey: Self.encodeFormulaSdsc) }
        if let information { aCoder.encode(information, forKey: Self.encodeFormulaInfo) }
        if let options { aCoder.encode(options, forKey: Self.encodeFormulaOptn) }
        aCoder.encode(NSNumber(value: isInstalled()), forKey: Self.encodeFormulaInst)
        aCoder.encode(cask, forKey: Self.encodeFormulaCask)
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init()
        self.name = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaName) as String?
        self.version = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaIver) as String?
        self.latestVersion = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaLver) as String?
        self.installPath = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaPath) as String?
        self.website = aDecoder.decodeObject(of: NSURL.self, forKey: Self.encodeFormulaWurl) as URL?
        self.dependencies = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaDeps) as String?
        self.conflicts = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaCnfl) as String?
        self.shortDescription = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaSdsc) as String?
        self.information = aDecoder.decodeObject(of: NSString.self, forKey: Self.encodeFormulaInfo) as String?
        self.options = aDecoder.decodeObject(of: [NSArray.self, BPFormulaOption.self], forKey: Self.encodeFormulaOptn) as? [Any]
        self.cask = aDecoder.decodeBool(forKey: Self.encodeFormulaCask)
        commonInit()
    }

    @objc open func commonInit() {
        if !isObservingNeedsInformation {
            isObservingNeedsInformation = true
            self.addObserver(self, forKeyPath: "needsInformation", options: [.new], context: &Self.kvoContext)
        }
    }

    open override func addObserver(
        _ observer: NSObject,
        forKeyPath keyPath: String,
        options: NSKeyValueObservingOptions = [],
        context: UnsafeMutableRawPointer?
    ) {
        observerAdded = true
        super.addObserver(observer, forKeyPath: keyPath, options: options, context: context)
    }

    open func copy(with zone: NSZone? = nil) -> Any {
        let formula = type(of: self).init()
        formula.name = self.name
        formula.version = self.version
        formula.latestVersion = self.latestVersion
        formula.installPath = self.installPath
        formula.website = self.website
        formula.dependencies = self.dependencies
        formula.conflicts = self.conflicts
        formula.shortDescription = self.shortDescription
        formula.information = self.information
        formula.options = self.options
        formula.cask = self.cask
        formula.commonInit()
        return formula
    }

    @objc open func installedName() -> String? {
        guard let name else { return nil }
        let nsName = name as NSString
        let slashRange = nsName.range(of: "/", options: .backwards)
        if slashRange.location != NSNotFound {
            return nsName.substring(from: slashRange.location + 1)
        }
        return name
    }

    open override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if context == &Self.kvoContext {
            if let obj = object as? BPFormula, obj === self, keyPath == "needsInformation" {
                if !isSuppressingNeedsInformationKVO && self.needsInformation {
                    _ = getInformation()
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func resetNeedsInformationFlag() {
        isSuppressingNeedsInformationKVO = true
        self.needsInformation = false
        isSuppressingNeedsInformationKVO = false
    }

    private static func lineLooksLikeWebsite(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("://")
    }

    @objc(preprocessedCaskInformation:)
    open class func preprocessedCaskInformation(_ output: String?) -> String? {
        guard let output else { return nil }
        var lines = output.components(separatedBy: "\n")
        guard !lines.isEmpty else { return output }

        var header = lines[0]
        if header.hasPrefix("==> ") {
            header = String(header.dropFirst(4))
        }
        header = header.replacingOccurrences(of: " (auto_updates)", with: "")
        lines[0] = header

        for i in 1..<lines.count {
            let line = lines[i]
            if line == "Installed" || line.hasPrefix("Installed (") {
                lines.remove(at: i)
                break
            }
            if line == "Not installed" {
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    @objc(installLocationFromLines:startingAtIndex:)
    open class func installLocation(fromLines lines: [String]?, startingAtIndex startIndex: UInt) -> String? {
        guard let lines else { return nil }
        let installedVersionsHeading = "==> Installed Versions"
        let start = Int(startIndex)
        guard start >= 0 && start < lines.count else { return nil }

        for index in start..<lines.count {
            let line = lines[index]
            if line.hasPrefix("Aliases:") || line.hasPrefix("From:") || line.hasPrefix("License:") {
                continue
            }
            if line == "Not installed" {
                return nil
            }
            if line.hasPrefix("Installed") {
                if index + 1 < lines.count {
                    for versionIndex in (index + 1)..<lines.count {
                        if lines[versionIndex] != installedVersionsHeading {
                            continue
                        }
                        if versionIndex + 1 < lines.count {
                            for buildIndex in (versionIndex + 1)..<lines.count {
                                let build = lines[buildIndex]
                                if !build.isEmpty {
                                    return build.hasPrefix("==>") ? nil : build
                                }
                            }
                        }
                        return nil
                    }
                }
                return nil
            }
            if line.hasPrefix("==>") {
                return nil
            }
            if line.isEmpty {
                return (index + 1 < lines.count) ? lines[index + 1] : nil
            }
            return line
        }
        return nil
    }

    @discardableResult
    @objc open func getInformation() -> Bool {
        if self.information == nil {
            guard let provider = self.dataProvider() else {
                resetNeedsInformationFlag()
                return false
            }
            let infoSelector = self.cask
                ? NSSelectorFromString("informationForCaskName:")
                : NSSelectorFromString("informationForFormulaName:")
            guard (provider as AnyObject).responds(to: infoSelector) else {
                resetNeedsInformationFlag()
                return false
            }
            let fetchedInfo: String?
            if self.cask {
                fetchedInfo = provider.information?(forCaskName: self.name)
            } else {
                fetchedInfo = provider.information(forFormulaName: self.name)
            }
            guard let fetchedInfo, (fetchedInfo as NSString).range(of: "\n").location != NSNotFound else {
                return false
            }
            self.information = fetchedInfo
        }

        guard var output = self.information else {
            resetNeedsInformationFlag()
            return false
        }

        if output.isEmpty {
            resetNeedsInformationFlag()
            return true
        }

        if output.hasPrefix("Error") {
            NSLog("Error parsing formula with name: %@", self.name ?? "")
            resetNeedsInformationFlag()
            self.information = nil
            self.latestVersion = nil
            self.version = nil
            self.shortDescription = nil
            return true
        }

        if self.cask, let preprocessed = Self.preprocessedCaskInformation(output) {
            output = preprocessed
        }

        var lines = output.components(separatedBy: "\n")
        if !lines.isEmpty && lines[0].hasPrefix("==> ") {
            lines[0] = String(lines[0].dropFirst(4))
        }

        parseInformationBody(lines: lines, output: output)

        resetNeedsInformationFlag()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
        return true
    }

    private func parseInformationBody(lines: [String], output: String) {
        guard !lines.isEmpty else { return }
        let line0 = lines[0] as NSString
        let colonRange = line0.range(of: ":")
        guard colonRange.location != NSNotFound, colonRange.location + 2 <= line0.length else {
            return
        }
        self.latestVersion = line0.substring(from: colonRange.location + 2)

        var lineIndex = 1
        guard lineIndex < lines.count else { return }
        var line = lines[lineIndex]

        if Self.lineLooksLikeWebsite(line) {
            self.website = URL(string: line)
        } else {
            self.shortDescription = line
            lineIndex = 2
            guard lineIndex < lines.count else { return }
            line = lines[lineIndex]
            self.website = URL(string: line)
        }

        lineIndex += 1
        guard lineIndex < lines.count else { return }
        line = lines[lineIndex]
        if (line as NSString).range(of: "Conflicts with:").location != NSNotFound {
            if line == "Conflicts with:" {
                var conflictList: [String] = []
                repeat {
                    lineIndex += 1
                    guard lineIndex < lines.count else { return }
                    line = lines[lineIndex]
                    if line.hasPrefix("  ") {
                        conflictList.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } while line.hasPrefix("  ")
                self.conflicts = conflictList.joined(separator: ", ")
            } else {
                let nsLine = line as NSString
                guard 16 <= nsLine.length else { return }
                self.conflicts = nsLine.substring(from: 16)
                lineIndex += 1
            }
        }

        self.installPath = Self.installLocation(fromLines: lines, startingAtIndex: UInt(max(0, lineIndex)))

        let nsOutput = output as NSString
        let rangeOpts = nsOutput.range(of: Self.identifierOptions)
        var rangeCvts = nsOutput.range(of: Self.identifierCaveats)

        // Homebrew adds sections over time; dependencies end at any next header.
        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == Self.identifierDependencies }) {
            let finishedTitle = NSLocalizedString("Homebrew_Task_Finished", comment: "")
            let dependencyLines = lines.dropFirst(header + 1)
                .prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("==>") && !$0.contains(finishedTitle) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.dependencies = dependencyLines.isEmpty ? nil : dependencyLines.joined(separator: "; ")
        } else {
            self.dependencies = nil
        }

        if rangeOpts.location != NSNotFound {
            let startLoc = rangeOpts.length + rangeOpts.location + 1
            guard startLoc >= 0, startLoc <= nsOutput.length else { return }
            var optionsString = nsOutput.substring(from: startLoc) as NSString
            var parsedOptions: [BPFormulaOption] = []
            rangeCvts = optionsString.range(of: Self.identifierCaveats)
            if rangeCvts.location != NSNotFound {
                optionsString = optionsString.substring(to: rangeCvts.location) as NSString
            }
            var currentOption: BPFormulaOption?
            (optionsString as String).enumerateLines { optLine, stop in
                if optLine.hasPrefix("--") {
                    let opt = BPFormulaOption()
                    opt.name = optLine
                    currentOption = opt
                } else if let opt = currentOption {
                    opt.explanation = optLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    parsedOptions.append(opt)
                    currentOption = nil
                } else {
                    stop = true
                }
            }
            self.options = parsedOptions
        } else {
            self.options = nil
        }
    }

    @objc open func isInstalled() -> Bool {
        guard let mgr = bpSharedHomebrewManager() else { return false }
        return mgr.status(forFormula: self) != 0
    }

    @objc open func isOutdated() -> Bool {
        guard let mgr = bpSharedHomebrewManager() else { return false }
        return mgr.status(forFormula: self) == 2
    }

    open override var description: String {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        return "\(NSStringFromClass(type(of: self))) <\(ptr)> name:\(name ?? "(null)") version:\(version ?? "(null)") latestVerson:\(latestVersion ?? "(null)")"
    }

    @objc open var shortLatestVersion: String? {
        guard let latestVersion else { return nil }
        let components = latestVersion.components(separatedBy: " ")
        if components.count == 3 || components.count == 4 {
            return components[1]
        }
        return latestVersion
    }

    @objc open func dataProvider() -> (any BPFormulaDataProvider)? {
        if let customDataProvider {
            return customDataProvider
        }
        if let providerClass = type(of: self).defaultDataProviderClass as? NSObject.Type {
            return providerClass.init() as? any BPFormulaDataProvider
        }
        return bpSharedHomebrewInterface() as? any BPFormulaDataProvider
    }

    deinit {
        if isObservingNeedsInformation {
            super.removeObserver(self, forKeyPath: "needsInformation", context: &Self.kvoContext)
        }
    }
}

@objc(BPCustomFormula)
public final class BPCustomFormula: BPFormula, @unchecked Sendable {
    public override class var defaultDataProviderClass: AnyClass? {
        NSClassFromString("BPFormulaTestDataProvider")
    }
}

@objc(BPInformationCachedFormula)
public final class BPInformationCachedFormula: BPFormula, @unchecked Sendable {
    public override var information: String? {
        get { "cached mock information" }
        set { super.information = newValue }
    }
}

@objc(BPModernFormula)
public final class BPModernFormula: BPFormula, @unchecked Sendable {
    public override class var defaultDataProviderClass: AnyClass? {
        NSClassFromString("BPModernInfoDataProvider")
    }
}

@objc(BPCompatFormula)
public final class BPCompatFormula: BPFormula, @unchecked Sendable {
    @objc public var provider: (any BPFormulaDataProvider)? {
        get { customDataProvider }
        set { customDataProvider = newValue }
    }
}

