import Foundation

enum JSEscaping {
    /// Escapes a string for safe embedding inside a JS template literal (backtick string).
    static func escapeForTemplateLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "`", with: "\\`")
         .replacingOccurrences(of: "$", with: "\\$")
    }

    /// Escapes a string for safe embedding inside a JS double-quoted string literal.
    static func escapeForStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}
