import CryptoKit
import Darwin
import Foundation

@objc(BPFormulaOption)
public final class BPFormulaOption: NSObject, NSSecureCoding, NSCopying {
    private static let nameKey = "formulaOptionName"
    private static let explanationKey = "formulaOptionExplanation"

    @objc public var explanation: String?
    @objc public var name: String?

    @objc public static var supportsSecureCoding: Bool { true }

    public override init() {
        super.init()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init()
        self.name = aDecoder.decodeObject(of: NSString.self, forKey: Self.nameKey) as String?
        self.explanation = aDecoder.decodeObject(of: NSString.self, forKey: Self.explanationKey) as String?
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(name as NSString?, forKey: Self.nameKey)
        aCoder.encode(explanation as NSString?, forKey: Self.explanationKey)
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let option = BPFormulaOption()
        option.name = self.name
        option.explanation = self.explanation
        return option
    }
}
