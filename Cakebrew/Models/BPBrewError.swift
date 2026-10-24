import CryptoKit
import Darwin
import Foundation

@objc(BPBrewError)
public final class BPBrewError: NSObject {
    public static let errorDomain = "com.brunophilipe.Cakebrew.ErrorDomain"
    public static let exitStatusKey = "BPBrewErrorExitStatus"
    private static let maximumReportedLines = 12
    private static let maximumReportedLength = 1500

    private static func tail(of output: String) -> String {
        var lines: [String] = []
        (output as NSString).enumerateLines { line, _ in
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(line)
            }
        }
        if lines.count > maximumReportedLines {
            lines.removeFirst(lines.count - maximumReportedLines)
        }
        let joined = lines.joined(separator: "\n") as NSString
        if joined.length > maximumReportedLength {
            return joined.substring(from: joined.length - maximumReportedLength)
        }
        return joined as String
    }

    @objc(errorForExitStatus:output:)
    public static func error(forExitStatus status: Int32, output: String?) -> NSError? {
        if status == 0 {
            return nil
        }
        let code = (status < 0) ? 1 : 2 // BPBrewErrorLaunchFailed = 1, BPBrewErrorNonZeroExit = 2
        let tailText = tail(of: output ?? "")
        let description: String
        if !tailText.isEmpty {
            description = tailText
        } else {
            description = String(format: NSLocalizedString("Error_Brew_Failed_No_Output", comment: ""), status)
        }
        return NSError(
            domain: errorDomain,
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: description,
                exitStatusKey: NSNumber(value: status)
            ]
        )
    }
}
