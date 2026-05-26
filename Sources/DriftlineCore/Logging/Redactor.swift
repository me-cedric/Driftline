import Foundation

public struct Redactor: Sendable {
    private let sensitiveKeys = ["password", "passphrase", "secret", "token", "privateKey"]

    public init() {}

    public func redact(_ message: String) -> String {
        var output = message
        for key in sensitiveKeys {
            let pattern = #"(?i)(\b\#(NSRegularExpression.escapedPattern(for: key))\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "$1<redacted>")
        }
        return output
    }
}
